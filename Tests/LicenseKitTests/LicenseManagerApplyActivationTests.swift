import XCTest

import LicenseKit

@MainActor
final class LicenseManagerApplyActivationTests: XCTestCase {
  func testApplyActivationPersistsResolvedActivationAndMetadata() throws {
    let activation = makeActivation(
      source: makeSource("source-b"),
      licenseKey: nil,
      planIdentifier: "external"
    )
    let activationStorage = TestActivationStorage()
    let stateMetadataStorage = TestStateMetadataStorage()
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let state = try manager.applyActivation(activation)

    XCTAssertEqual(state.activation?.source, makeSource("source-b"))
    XCTAssertEqual(state.source, makeSource("source-b"))
    XCTAssertEqual(manager.source, makeSource("source-b"))
    XCTAssertNil(state.activation?.licenseKey)
    XCTAssertEqual(state.plan.identifier, "external")
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertEqual(provider.activationCount, 0)
    XCTAssertNil(provider.lastActivationRequest)
    XCTAssertNil(provider.lastActivationLicenseKey)
    XCTAssertEqual(
      try stateMetadataStorage.state(matching: activation)?.activation?.source,
      makeSource("source-b")
    )
  }

  func testApplyActivationRejectsExpiredActivationWithoutChangingState() throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planIdentifier: "pro")
    let expiredActivation = makeActivation(
      licenseKey: nil,
      planIdentifier: "expired",
      activatedAt: Date(timeIntervalSince1970: 0),
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
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planIdentifier: "pro")
    let activationStorage = TestActivationStorage(activation: existingActivation)
    activationStorage.saveError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation(planIdentifier: "team")),
      activationStorage: activationStorage
    )

    XCTAssertThrowsError(try manager.applyActivation(makeActivation(planIdentifier: "team"))) {
      error in
      XCTAssertEqual(error as? LicenseError, .storageFailure(message: "Storage operation failed."))
    }
    XCTAssertEqual(manager.activation, existingActivation)
    XCTAssertEqual(manager.plan.identifier, "pro")
    XCTAssertEqual(activationStorage.activation, existingActivation)
  }

  func testApplyActivationIgnoresStateMetadataStorageSaveFailure() throws {
    let activation = makeActivation(planIdentifier: "pro")
    let activationStorage = TestActivationStorage()
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let state = try manager.applyActivation(activation)

    XCTAssertEqual(state.status, .active)
    XCTAssertEqual(manager.status, .active)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertNil(stateMetadataStorage.metadata)
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

    XCTAssertThrowsError(try manager.applyActivation(makeActivation(planIdentifier: "team"))) {
      error in
      XCTAssertEqual(error as? LicenseError, .refreshInProgress)
    }

    _ = try await refresh
  }

}
