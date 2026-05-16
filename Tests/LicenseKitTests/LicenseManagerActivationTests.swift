import XCTest

@testable import LicenseKit

@MainActor
final class LicenseManagerActivationTests: XCTestCase {
  func testActivateNormalizesKeyPersistsActivationAndSnapshot() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let state = try await manager.activate(.licenseKey(" KEY "))

    XCTAssertEqual(provider.lastActivationRequest, .licenseKey("KEY"))
    XCTAssertEqual(provider.lastActivationLicenseKey, "KEY")
    XCTAssertEqual(provider.activationCount, 1)
    XCTAssertEqual(state.plan.id, "pro")
    XCTAssertEqual(state.status, .active)
    XCTAssertEqual(manager.plan.id, "pro")
    XCTAssertEqual(manager.status, .active)
    XCTAssertEqual(activationStorage.activation?.licenseKey, "KEY")
    XCTAssertEqual(try stateSnapshotStorage.state(matching: activation)?.plan.id, "pro")
  }

  func testActivateRejectsBlankLicenseKey() async throws {
    let provider = TestProvider(activation: makeActivation())
    let activationStorage = TestActivationStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(.licenseKey(" \n\t "))
      XCTFail("Expected invalidLicenseKey")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .invalidLicenseKey)
      XCTAssertEqual(manager.status, .unlicensed)
    }
    XCTAssertEqual(provider.activationCount, 0)
    XCTAssertNil(provider.lastActivationRequest)
    XCTAssertNil(provider.lastActivationLicenseKey)
    XCTAssertNil(activationStorage.activation)
  }

  func testActivateWithAutomaticRequestPersistsKeylessActivation() async throws {
    let activation = makeActivation(source: "runtime-entitlement", licenseKey: nil, planID: "pro")
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let state = try await manager.activate(.automatic)

    XCTAssertEqual(provider.lastActivationRequest, .automatic)
    XCTAssertNil(provider.lastActivationLicenseKey)
    XCTAssertEqual(provider.activationCount, 1)
    XCTAssertEqual(state.activation?.source, LicenseSource(rawValue: "runtime-entitlement"))
    XCTAssertNil(state.activation?.licenseKey)
    XCTAssertEqual(state.plan.id, "pro")
    XCTAssertEqual(state.status, .active)
    XCTAssertEqual(activationStorage.activation, activation)
  }

  func testApplyActivationPersistsResolvedActivationAndSnapshot() throws {
    let activation = makeActivation(
      source: "source-b",
      licenseKey: nil,
      planID: "external"
    )
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let state = try manager.applyActivation(activation)

    XCTAssertEqual(state.activation?.source, LicenseSource(rawValue: "source-b"))
    XCTAssertEqual(state.source, LicenseSource(rawValue: "source-b"))
    XCTAssertEqual(manager.source, LicenseSource(rawValue: "source-b"))
    XCTAssertNil(state.activation?.licenseKey)
    XCTAssertEqual(state.plan.id, "external")
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertEqual(provider.activationCount, 0)
    XCTAssertNil(provider.lastActivationRequest)
    XCTAssertNil(provider.lastActivationLicenseKey)
    XCTAssertEqual(
      try stateSnapshotStorage.state(matching: activation)?.activation?.source,
      LicenseSource(rawValue: "source-b")
    )
  }

  func testApplyActivationRejectsExpiredActivationWithoutChangingState() throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let expiredActivation = makeActivation(
      licenseKey: nil,
      planID: "expired",
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let activationStorage = TestActivationStorage(activation: existingActivation)
    let manager = LicenseManager(
      provider: TestProvider(activation: expiredActivation),
      activationStorage: activationStorage
    )

    XCTAssertThrowsError(try manager.applyActivation(expiredActivation)) { error in
      XCTAssertEqual(error as? LicenseError, .expiredLicense)
    }
    XCTAssertEqual(manager.activation, existingActivation)
    XCTAssertEqual(activationStorage.activation, existingActivation)
  }

  func testApplyActivationStorageFailurePreservesExistingActivation() throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let activationStorage = TestActivationStorage(activation: existingActivation)
    activationStorage.saveError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation(planID: "team")),
      activationStorage: activationStorage
    )

    XCTAssertThrowsError(try manager.applyActivation(makeActivation(planID: "team"))) { error in
      XCTAssertEqual(error as? LicenseError, .storageFailure(message: "keychain unavailable"))
    }
    XCTAssertEqual(manager.activation, existingActivation)
    XCTAssertEqual(manager.plan.id, "pro")
    XCTAssertEqual(activationStorage.activation, existingActivation)
  }

  func testApplyActivationReportsStateSnapshotStorageSaveFailure() throws {
    let activation = makeActivation(planID: "pro")
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertThrowsError(try manager.applyActivation(activation)) { error in
      XCTAssertEqual(error as? LicenseError, .storageFailure(message: "defaults unavailable"))
    }
    XCTAssertEqual(manager.status, .active)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(activationStorage.activation, activation)
  }

  func testApplyActivationRejectsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let first: LicenseState = manager.activate(.licenseKey("KEY"))
    try await waitForManagerState { manager.isActivating }

    XCTAssertThrowsError(try manager.applyActivation(activation)) { error in
      XCTAssertEqual(error as? LicenseError, .activationInProgress)
    }

    _ = try await first
    XCTAssertEqual(provider.activationCount, 1)
  }

  func testApplyActivationRejectsConcurrentRefresh() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let refresh = manager.refresh()
    try await waitForManagerState { manager.isRefreshing }

    XCTAssertThrowsError(try manager.applyActivation(makeActivation(planID: "team"))) { error in
      XCTAssertEqual(error as? LicenseError, .refreshInProgress)
    }

    _ = try await refresh
  }

  func testActivatePreservesProviderSource() async throws {
    let activation = makeActivation(source: "source-a", licenseKey: nil)
    let activationStorage = TestActivationStorage()
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage
    )

    let state = try await manager.activate(.licenseKey(" KEY "))

    XCTAssertEqual(state.activation?.source, LicenseSource(rawValue: "source-a"))
    XCTAssertEqual(state.activation?.licenseKey, "KEY")
    XCTAssertEqual(
      activationStorage.activation?.source,
      LicenseSource(rawValue: "source-a")
    )
    XCTAssertEqual(activationStorage.activation?.licenseKey, "KEY")
  }

  func testActivatePreservesProviderResolvedLicenseKey() async throws {
    let activation = makeActivation(licenseKey: "PROVIDER-KEY")
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let state = try await manager.activate(.licenseKey(" USER-KEY "))

    XCTAssertEqual(provider.lastActivationLicenseKey, "USER-KEY")
    XCTAssertEqual(state.activation?.licenseKey, "PROVIDER-KEY")
    XCTAssertEqual(activationStorage.activation?.licenseKey, "PROVIDER-KEY")
  }

  func testActivateRejectsExpiredProviderActivationWithoutChangingState() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let expiredActivation = makeActivation(
      licenseKey: nil,
      planID: "expired",
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let provider = TestProvider(activation: expiredActivation)
    let activationStorage = TestActivationStorage(activation: existingActivation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(.licenseKey("NEW-KEY"))
      XCTFail("Expected expiredLicense")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .expiredLicense)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(activationStorage.activation, existingActivation)
    }
  }

  func testActivateMapsProviderErrors() async throws {
    let cases: [(LicenseProviderError, LicenseError)] = [
      (.invalidLicense, .invalidLicense),
      (.activationLimitReached, .activationLimitReached),
      (.invalidConfiguration, .invalidProviderConfiguration),
      (.serverFailure(statusCode: 503), .serverFailure(statusCode: 503)),
      (.responseDecodingFailure, .unexpectedProviderResponse),
      (.requestFailure(message: "bad request"), .requestFailure(message: "bad request")),
      (.requestFailure(message: " \n\t "), .requestFailure(message: "Request failed.")),
      (.transportFailure(message: "offline"), .requestFailure(message: "offline")),
      (.transportFailure(message: " \n\t "), .requestFailure(message: "Transport failed.")),
    ]

    for (providerError, expectedError) in cases {
      let provider = TestProvider(activation: makeActivation())
      provider.activationError = providerError
      let manager = LicenseManager(
        provider: provider,
        activationStorage: TestActivationStorage()
      )

      do {
        try await manager.activate(.licenseKey("KEY"))
        XCTFail("Expected \(expectedError)")
      } catch let error as LicenseError {
        XCTAssertEqual(error, expectedError)
        XCTAssertEqual(manager.status, .unlicensed)
      }
    }
  }

  func testActivateReportsStorageFailureToCaller() async throws {
    let provider = TestProvider(activation: makeActivation())
    let activationStorage = TestActivationStorage()
    activationStorage.saveError = LicenseError.storageFailure(message: "Storage operation failed.")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .unlicensed)
    }
  }

  func testActivateReportsStateSnapshotStorageSaveFailure() async throws {
    let activation = makeActivation(planID: "pro")
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "defaults unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation?.planID, "pro")
      XCTAssertEqual(activationStorage.activation, activation)
    }
  }

  func testActivateProviderFailurePreservesExistingActivation() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let provider = TestProvider(activation: makeActivation(licenseKey: "NEW-KEY", planID: "team"))
    provider.activationError = LicenseProviderError.transportFailure(message: "offline")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: existingActivation)
    )

    do {
      try await manager.activate(.licenseKey("NEW-KEY"))
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "offline"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(manager.plan.id, "pro")
    }
  }

  func testActivateStorageFailurePreservesExistingActivation() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let activationStorage = TestActivationStorage(activation: existingActivation)
    activationStorage.saveError = LicenseError.storageFailure(message: "Storage operation failed.")
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation(licenseKey: "NEW-KEY", planID: "team")),
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(.licenseKey("NEW-KEY"))
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(manager.plan.id, "pro")
      XCTAssertEqual(activationStorage.activation, existingActivation)
    }
  }

  func testActivateReportsUnexpectedProviderFailureAndResetsState() async throws {
    let provider = TestProvider(activation: makeActivation())
    provider.activationError = TestUnexpectedError(message: "boom")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "boom"))
      XCTAssertEqual(manager.status, .unlicensed)
      XCTAssertNil(manager.activation)
    }
  }

  func testActivateProviderLicenseErrorRestoresState() async throws {
    let provider = TestProvider(activation: makeActivation())
    provider.activationError = LicenseError.invalidLicense
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected license failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .invalidLicense)
      XCTAssertEqual(manager.status, .unlicensed)
      XCTAssertNil(manager.activation)
    }
  }

  func testActivateProviderLicenseErrorPreservesExistingActivation() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let provider = TestProvider(activation: makeActivation(licenseKey: "NEW-KEY", planID: "team"))
    provider.activationError = LicenseError.invalidLicense
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: existingActivation)
    )

    do {
      try await manager.activate(.licenseKey("NEW-KEY"))
      XCTFail("Expected license failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .invalidLicense)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(manager.plan.id, "pro")
    }
  }

  func testActivateRejectsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let first: LicenseState = manager.activate(.licenseKey("KEY"))
    try await waitForManagerState { manager.isActivating }

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected activationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .activationInProgress)
    }

    _ = try await first
    XCTAssertEqual(provider.activationCount, 1)
  }

  func testActivateRejectsConcurrentRefresh() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let refresh = manager.refresh()
    try await waitForManagerState { manager.isRefreshing }

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected refreshInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .refreshInProgress)
    }

    _ = try await refresh
    XCTAssertEqual(provider.activationCount, 0)
  }
}
