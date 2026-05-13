import XCTest

@testable import LicenseKit

@MainActor
final class LicenseManagerTests: XCTestCase {
  func testActivateNormalizesKeyPersistsActivationAndSnapshot() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage,
      deviceNameProvider: { " Work Mac " }
    )

    let state = try await manager.activate(licenseKey: " KEY ")

    XCTAssertEqual(provider.lastActivationLicenseKey, "KEY")
    XCTAssertEqual(provider.lastActivationDeviceName, "Work Mac")
    XCTAssertEqual(state.plan.id, "pro")
    XCTAssertEqual(state.status, .active)
    XCTAssertEqual(manager.plan.id, "pro")
    XCTAssertEqual(manager.status, .active)
    XCTAssertEqual(activationStorage.activation?.licenseKey, "KEY")
    XCTAssertEqual(try stateSnapshotStorage.state(matching: activation)?.plan.id, "pro")
  }

  func testActivateRejectsBlankLicenseKey() async throws {
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: TestActivationStorage()
    )

    do {
      try await manager.activate(licenseKey: " \n\t ")
      XCTFail("Expected invalidLicenseKey")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .invalidLicenseKey)
      XCTAssertEqual(manager.status, .unlicensed)
    }
  }

  func testApplyActivationPersistsProviderResolvedActivation() throws {
    let activation = makeActivation(
      source: "source-b",
      licenseKey: nil,
      planID: "external"
    )
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
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
    XCTAssertEqual(
      try stateSnapshotStorage.state(matching: activation)?.activation?.source,
      LicenseSource(rawValue: "source-b")
    )
  }

  func testActivatePreservesProviderSource() async throws {
    let activation = makeActivation(source: "source-a", licenseKey: nil)
    let activationStorage = TestActivationStorage()
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage
    )

    let state = try await manager.activate(licenseKey: " KEY ")

    XCTAssertEqual(state.activation?.source, LicenseSource(rawValue: "source-a"))
    XCTAssertEqual(state.activation?.licenseKey, "KEY")
    XCTAssertEqual(
      activationStorage.activation?.source,
      LicenseSource(rawValue: "source-a")
    )
  }

  func testActivateMapsProviderErrors() async throws {
    let cases: [(LicenseProviderError, LicenseError)] = [
      (.invalidLicense, .invalidLicense),
      (.activationLimitReached, .activationLimitReached),
      (.invalidProviderURL, .invalidProviderURL),
      (.serverFailure(statusCode: 503), .providerServerFailure(statusCode: 503)),
      (.responseDecodingFailure, .unexpectedProviderResponse),
      (.requestFailure(message: "bad request"), .providerRequestFailure(message: "bad request")),
      (.networkFailure(message: "offline"), .providerRequestFailure(message: "offline")),
    ]

    for (providerError, expectedError) in cases {
      let provider = TestProvider(activation: makeActivation())
      provider.activationError = providerError
      let manager = LicenseManager(
        provider: provider,
        activationStorage: TestActivationStorage()
      )

      do {
        try await manager.activate(licenseKey: "KEY")
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
    activationStorage.saveError = LicenseError.storageFailure
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(licenseKey: "KEY")
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .unlicensed)
    }
  }

  func testActivateReportsStateSnapshotStorageSaveFailure() async throws {
    let activation = makeActivation(planID: "pro")
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(),
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.activate(licenseKey: "KEY")
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation?.planID, "pro")
    }
  }

  func testActivateProviderFailurePreservesExistingActivation() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let provider = TestProvider(activation: makeActivation(licenseKey: "NEW-KEY", planID: "team"))
    provider.activationError = LicenseProviderError.networkFailure(message: "offline")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: existingActivation)
    )

    do {
      try await manager.activate(licenseKey: "NEW-KEY")
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .providerRequestFailure(message: "offline"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(manager.plan.id, "pro")
    }
  }

  func testActivateStorageFailurePreservesExistingActivation() async throws {
    let existingActivation = makeActivation(licenseKey: "OLD-KEY", planID: "pro")
    let activationStorage = TestActivationStorage(activation: existingActivation)
    activationStorage.saveError = LicenseError.storageFailure
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation(licenseKey: "NEW-KEY", planID: "team")),
      activationStorage: activationStorage
    )

    do {
      try await manager.activate(licenseKey: "NEW-KEY")
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, existingActivation)
      XCTAssertEqual(manager.plan.id, "pro")
      XCTAssertEqual(activationStorage.activation, existingActivation)
    }
  }

  func testInitialRestoreKeepsStorageFailureObservable() {
    let activationStorage = TestActivationStorage()
    activationStorage.loadError = LicenseError.storageFailure

    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: activationStorage
    )

    XCTAssertEqual(manager.initialRestoreError, .storageFailure)
    XCTAssertEqual(manager.status, .unlicensed)
  }

  func testInitialStateRestoreFailureIsObservable() {
    let activation = makeActivation()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.loadError = LicenseError.storageFailure

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(manager.initialRestoreError, .storageFailure)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
  }

  func testActivateReportsUnexpectedProviderFailureAndResetsState() async throws {
    let provider = TestProvider(activation: makeActivation())
    provider.activationError = TestUnexpectedError(message: "boom")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    do {
      try await manager.activate(licenseKey: "KEY")
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .providerRequestFailure(message: "boom"))
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
      try await manager.activate(licenseKey: "KEY")
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
      try await manager.activate(licenseKey: "NEW-KEY")
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

    async let first: LicenseState = manager.activate(licenseKey: "KEY")
    try await Task.sleep(nanoseconds: 10_000_000)

    do {
      try await manager.activate(licenseKey: "KEY")
      XCTFail("Expected activationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .activationInProgress)
    }

    _ = try await first
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
    try await Task.sleep(nanoseconds: 10_000_000)

    do {
      try await manager.activate(licenseKey: "KEY")
      XCTFail("Expected refreshInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .refreshInProgress)
    }

    _ = try await refresh
  }

  func testDeactivateRejectsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let activationState: LicenseState = manager.activate(licenseKey: "KEY")
    try await Task.sleep(nanoseconds: 10_000_000)

    do {
      try await manager.deactivate()
      XCTFail("Expected activationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .activationInProgress)
    }

    _ = try await activationState
  }

  func testDeactivateRejectsConcurrentRefresh() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let refresh = manager.refresh()
    try await Task.sleep(nanoseconds: 10_000_000)

    do {
      try await manager.deactivate()
      XCTFail("Expected refreshInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .refreshInProgress)
    }

    _ = try await refresh
  }

  func testDeactivateReportsProviderFailureAfterLocalCleanup() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationError = LicenseProviderError.networkFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .providerRequestFailure(message: "offline"))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertNil(manager.activation)
      XCTAssertNil(activationStorage.activation)
    }
  }

  func testDeactivateReportsActivationStorageDeleteFailureWithoutClearingState() async throws {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(activationStorage.activation, activation)
    }
  }

  func testDeactivateReportsStateSnapshotStorageDeleteFailureAfterClearingActivation() async throws
  {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    stateSnapshotStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertNil(manager.activation)
      XCTAssertNil(activationStorage.activation)
    }
  }

  func testDeactivateReturnsUpdatedState() async throws {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertNil(state.activation)
    XCTAssertNil(activationStorage.activation)
  }

  func testRefreshUsesConfiguredInterval() throws {
    let activation = makeActivation(activatedAt: Date(timeIntervalSince1970: 0))
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(activation: activation, lastValidatedAt: activation.activatedAt)
    )
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        recoverableFailureGracePeriod: 100,
        serverFailureGracePeriod: 50
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertFalse(manager.needsRefresh(now: Date(timeIntervalSince1970: 9)))
    XCTAssertTrue(manager.needsRefresh(now: Date(timeIntervalSince1970: 10)))
    XCTAssertTrue(
      manager.needsRefresh(
        now: Date(timeIntervalSince1970: 5),
        validationInterval: 5
      )
    )
  }

  func testNeverRefreshPolicySkipsRefreshWithoutCallingProvider() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: .never
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedRefreshDisabled)
    XCTAssertFalse(manager.needsRefresh())
    XCTAssertFalse(manager.isRefreshing)
    XCTAssertNil(provider.lastValidationIdentifier)
  }

  func testRefreshIsGuardedAgainstMultipleConcurrentRuns() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let first = manager.refresh()
    async let second = manager.refresh()
    let results = try await [first, second]

    XCTAssertFalse(manager.isRefreshing)
    XCTAssertTrue(results.contains { $0.outcome == .skippedRefreshInProgress })
  }

  func testRefreshSkipsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let activationState: LicenseState = manager.activate(licenseKey: "KEY")
    try await Task.sleep(nanoseconds: 10_000_000)

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedActivationInProgress)
    _ = try await activationState
  }

  func testRefreshSkipsWhenThereIsNoActivation() async throws {
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: TestActivationStorage()
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedNoActivation)
    XCTAssertEqual(manager.status, .unlicensed)
  }

  func testRefreshUsesConfiguredDeviceIdentifierWhenActivationIDIsMissing() async throws {
    let activation = makeActivation(activationID: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      deviceIdentifierProvider: TestDeviceIdentifierProvider(identifier: " device-1 ")
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "device-1")
  }

  func testRefreshPrefersActivationIDOverConfiguredDeviceIdentifier() async throws {
    let activation = makeActivation(activationID: "activation-1")
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      deviceIdentifierProvider: TestDeviceIdentifierProvider(identifier: "device-1")
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "activation-1")
  }

  func testRefreshPassesNilWhenActivationIDAndDeviceIdentifierAreMissing() async throws {
    let activation = makeActivation(activationID: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    _ = try await manager.refresh()

    XCTAssertNil(provider.lastValidationIdentifier)
  }

  func testRefreshCanUpdatePlanFromValidationResult() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: true,
      planID: " team ",
      customerID: " customer-updated "
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertTrue(result.state.isLicensed)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.plan.id, "team")
    XCTAssertEqual(manager.activation?.planID, "team")
    XCTAssertEqual(manager.activation?.customerID, "customer-updated")
    XCTAssertEqual(activationStorage.activation?.planID, "team")
  }

  func testRefreshActivationSaveFailurePreservesExistingState() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: true, planID: "team")
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.saveError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(manager.plan.id, "pro")
      XCTAssertEqual(activationStorage.activation, activation)
    }
  }

  func testRefreshReportsStateSnapshotStorageSaveFailure() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: true, planID: "team")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.plan.id, "team")
      XCTAssertEqual(activationStorage.activation?.planID, "team")
    }
  }

  func testSetOfferingsReturnsUpdatedState() throws {
    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: TestActivationStorage()
    )
    let offering = LicenseOffering(id: "team", name: "Team")

    let state = manager.setOfferings([offering])

    XCTAssertEqual(state.offerings, [offering])
    XCTAssertEqual(manager.offerings, [offering])
  }

  func testRefreshFailureEntersGraceAndKeepsReason() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.networkFailure(message: "offline")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        recoverableFailureGracePeriod: 60,
        serverFailureGracePeriod: 30
      )
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .networkFailure)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .networkFailure)
    XCTAssertEqual(manager.lastRefreshFailure?.message, "offline")
    XCTAssertNotNil(manager.gracePeriodExpiresAt)
  }

  func testRefreshInvalidResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: false,
      expiresAt: nil,
      remainingActivations: nil
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
  }

  func testRefreshInvalidResultDeleteFailurePreservesExistingState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(activationStorage.activation, activation)
    }
  }

  func testRefreshExpiredResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: false,
      expiresAt: Date(timeIntervalSince1970: 1),
      remainingActivations: nil
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
  }

  func testRefreshReportsOfferingLoadFailure() async throws {
    let activation = makeActivation()
    let offeringProvider = TestOfferingProvider(offerings: [])
    offeringProvider.error = LicenseProviderError.networkFailure(message: "catalog offline")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      configuration: try LicenseConfiguration(dynamicOfferingsCatalogID: "catalog"),
      offeringProvider: offeringProvider
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertEqual(result.offeringLoadFailure?.reason, .offeringLoadFailure)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .offeringLoadFailure)
  }

  func testRefreshLoadsDynamicOfferings() async throws {
    let activation = makeActivation()
    let offering = LicenseOffering(id: "team", name: "Team")
    let offeringProvider = TestOfferingProvider(offerings: [offering])
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      configuration: try LicenseConfiguration(dynamicOfferingsCatalogID: "catalog"),
      offeringProvider: offeringProvider
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertEqual(result.state.offerings, [offering])
    XCTAssertEqual(manager.offerings, [offering])
  }

  func testRefreshProviderInvalidLicenseErrorClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.validationFailure?.reason, .invalidLicense)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
  }

  func testRefreshProviderInvalidDeleteFailurePreservesExistingState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure)
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(activationStorage.activation, activation)
    }
  }

  func testRefreshServerFailureUsesProviderGracePeriod() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.serverFailure(statusCode: 503)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        recoverableFailureGracePeriod: 60,
        serverFailureGracePeriod: 30
      )
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .providerServerFailure)
    XCTAssertEqual(result.validationFailure?.statusCode, 503)
    XCTAssertEqual(manager.status, .gracePeriod)
  }

  func testRefreshExpiredGracePeriodInvalidatesOnProviderFailure() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.networkFailure(message: "offline")
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
  }

  func testRefreshUnexpectedErrorEntersGracePeriod() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = TestUnexpectedError(message: "boom")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .networkFailure)
    XCTAssertEqual(result.validationFailure?.message, "boom")
    XCTAssertEqual(manager.status, .gracePeriod)
  }

  func testRefreshExpiredGracePeriodInvalidatesOnUnexpectedProviderFailure() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = TestUnexpectedError(message: "boom")
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.validationFailure?.reason, .networkFailure)
    XCTAssertEqual(result.validationFailure?.message, "boom")
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
  }

  func testCustomerPortalURLUsesActivationCustomerID() async throws {
    let expectedURL = try XCTUnwrap(URL(string: "https://example.com/portal"))
    let activation = makeActivation(customerID: "customer")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      customerPortalProvider: TestCustomerPortalProvider(url: expectedURL)
    )

    let url = try await manager.customerPortalURL()

    XCTAssertEqual(url, expectedURL)
  }

  func testCustomerPortalURLReturnsNilWhenProviderOrCustomerIsMissing() async throws {
    let managerWithoutProvider = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: TestActivationStorage(activation: makeActivation())
    )
    let urlWithoutProvider = try await managerWithoutProvider.customerPortalURL()
    XCTAssertNil(urlWithoutProvider)

    let activationWithoutCustomer = makeActivation(customerID: nil)
    let managerWithoutCustomer = LicenseManager(
      provider: TestProvider(activation: activationWithoutCustomer),
      activationStorage: TestActivationStorage(activation: activationWithoutCustomer),
      customerPortalProvider: TestCustomerPortalProvider(url: URL(string: "https://example.com"))
    )
    let urlWithoutCustomer = try await managerWithoutCustomer.customerPortalURL()
    XCTAssertNil(urlWithoutCustomer)
  }

  func testCustomerPortalURLMapsProviderFailure() async throws {
    let portalProvider = TestCustomerPortalProvider(url: nil)
    portalProvider.error = LicenseProviderError.serverFailure(statusCode: 503)
    let activation = makeActivation(customerID: "customer")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      customerPortalProvider: portalProvider
    )

    do {
      _ = try await manager.customerPortalURL()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .providerServerFailure(statusCode: 503))
    }
  }

  func testCustomerPortalURLMapsUnexpectedFailure() async throws {
    let portalProvider = TestCustomerPortalProvider(url: nil)
    portalProvider.error = TestUnexpectedError(message: "boom")
    let activation = makeActivation(customerID: "customer")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      customerPortalProvider: portalProvider
    )

    do {
      _ = try await manager.customerPortalURL()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .providerRequestFailure(message: "boom"))
    }
  }
}
