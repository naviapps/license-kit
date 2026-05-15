import XCTest

@testable import LicenseKit

@MainActor
final class LicenseManagerRefreshTests: XCTestCase {
  func testNeedsRefreshUsesConfiguredInterval() throws {
    let activation = makeActivation(activatedAt: Date(timeIntervalSince1970: 0))
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(activation: activation, lastValidatedAt: activation.activatedAt)
    )
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 100,
        serverFailureGracePeriod: 50
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertFalse(manager.needsRefresh(now: Date(timeIntervalSince1970: 9)))
    XCTAssertTrue(manager.needsRefresh(now: Date(timeIntervalSince1970: 10)))
  }

  func testNeedsRefreshReturnsTrueWhenActivationIsLocallyExpired() throws {
    let now = Date()
    let expiresAt = now.addingTimeInterval(60)
    let activation = makeActivation(activatedAt: now, expiresAt: expiresAt)
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(activation: activation, lastValidatedAt: now)
    )
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 3_600,
        failureGracePeriod: 100,
        serverFailureGracePeriod: 50
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertFalse(manager.needsRefresh(now: expiresAt.addingTimeInterval(-1)))
    XCTAssertTrue(manager.needsRefresh(now: expiresAt))
  }

  func testNeedsRefreshReturnsTrueWhenActivationHasNoValidationTimestamp() throws {
    let activation = makeActivation()
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation)
    )

    XCTAssertTrue(manager.needsRefresh())
  }

  func testNeverRefreshPolicyStillAllowsLocalExpiration() async throws {
    let activation = makeActivation(expiresAt: Date().addingTimeInterval(0.05))
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: .never
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue(manager.needsRefresh())
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(provider.validationCount, 0)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
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
    XCTAssertFalse(manager.isActivating)
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
    XCTAssertEqual(provider.validationCount, 1)
    XCTAssertTrue(results.contains { $0.outcome == .refreshed })
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
    XCTAssertTrue(manager.isActivating)
    _ = try await activationState
    XCTAssertFalse(manager.isActivating)
  }

  func testRefreshSkipsWhenThereIsNoActivation() async throws {
    let provider = TestProvider(activation: makeActivation())
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedNoActivation)
    XCTAssertEqual(manager.status, .unlicensed)
    XCTAssertFalse(manager.isRefreshing)
    XCTAssertNil(provider.lastValidationIdentifier)
  }

  func testRefreshUsesConfiguredValidationIdentifierWhenActivationIDIsMissing() async throws {
    let activation = makeActivation(activationID: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      validationIdentifierProvider: { " validation-1 " }
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "validation-1")
  }

  func testRefreshPrefersActivationIDOverConfiguredValidationIdentifier() async throws {
    let activation = makeActivation(activationID: "activation-1")
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      validationIdentifierProvider: { "validation-1" }
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "activation-1")
  }

  func testRefreshPassesNilWhenValidationIdentifierIsUnavailable() async throws {
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
      planID: " team "
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertTrue(result.state.isLicensed)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.plan.id, "team")
    XCTAssertEqual(manager.activation?.planID, "team")
    XCTAssertEqual(provider.lastValidatedActivation, activation)
    XCTAssertEqual(activationStorage.activation?.planID, "team")
  }

  func testRefreshActivationSaveFailurePreservesExistingState() async throws {
    let activation = makeActivation(planID: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: true, planID: "team")
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.saveError = TestUnexpectedError(message: "keychain unavailable")
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "keychain unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(manager.plan.id, "pro")
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
    }
  }

  func testRefreshSuccessReportsStateSnapshotStorageSaveFailure() async throws {
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
      XCTAssertEqual(error, .storageFailure(message: "defaults unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.plan.id, "team")
      XCTAssertEqual(activationStorage.activation?.planID, "team")
      XCTAssertNil(stateSnapshotStorage.snapshot)
    }
  }

  func testRefreshFailureEntersGraceAndKeepsReason() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 60,
        serverFailureGracePeriod: 30
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .transportFailure)
    XCTAssertEqual(manager.lastRefreshFailure?.message, "offline")
    XCTAssertNotNil(manager.gracePeriodExpiresAt)
    XCTAssertNotNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshFailureReportsStateSnapshotStorageSaveFailure() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "defaults unavailable"))
      XCTAssertEqual(manager.status, .gracePeriod)
      XCTAssertEqual(manager.lastRefreshFailure?.reason, .transportFailure)
      XCTAssertNotNil(manager.gracePeriodExpiresAt)
      XCTAssertNil(stateSnapshotStorage.snapshot)
    }
  }

  func testRefreshInvalidResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: false,
      expiresAt: nil
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshInvalidResultActivationDeleteFailurePreservesExistingState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "keychain unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
    }
  }

  func testRefreshInvalidResultSnapshotDeleteFailureReportsStorageAfterClearingActivation()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    stateSnapshotStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "defaults unavailable"))
      XCTAssertEqual(manager.status, .invalid)
      XCTAssertNil(manager.activation)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
    }
  }

  func testRefreshExpiredResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: false,
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshLocallyExpiredActivationClearsPersistedActivationWithoutProviderCall()
    async throws
  {
    let activation = makeActivation(expiresAt: Date().addingTimeInterval(0.05))
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(activation: activation, status: .active)
    )
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertNil(result.validationFailure)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
    XCTAssertEqual(provider.validationCount, 0)
  }

  func testRefreshExpiredValidResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = LicenseValidationResult(
      isValid: true,
      planID: "pro",
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshProviderInvalidLicenseErrorClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.validationFailure?.reason, .invalidLicense)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshProviderActivationLimitReachedClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.activationLimitReached
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.validationFailure?.reason, .activationLimitReached)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testRefreshProviderInvalidLicenseActivationDeleteFailurePreservesExistingState()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "keychain unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
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
        failureGracePeriod: 60,
        serverFailureGracePeriod: 30
      )
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .serverFailure)
    XCTAssertEqual(result.validationFailure?.statusCode, 503)
    XCTAssertEqual(manager.status, .gracePeriod)
  }

  func testRefreshFailureDuringActiveGraceKeepsOriginalGraceExpiration() async throws {
    let activation = makeActivation()
    let originalGraceExpiration = Date().addingTimeInterval(60)
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: originalGraceExpiration,
        lastRefreshFailure: LicenseRefreshFailure(
          reason: .transportFailure,
          message: "first failure",
          occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
      )
    )
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 3_600,
        serverFailureGracePeriod: 3_600
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.validationFailure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertEqual(manager.gracePeriodExpiresAt, originalGraceExpiration)
    XCTAssertEqual(manager.lastRefreshFailure?.message, "offline")
  }

  func testRefreshFailureAfterGraceExpirationInvalidatesAndClearsPersistedActivation()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 0,
        serverFailureGracePeriod: 0
      ),
      stateSnapshotStorage: stateSnapshotStorage
    )

    let graceResult = try await manager.refresh()
    let invalidResult = try await manager.refresh()

    XCTAssertEqual(graceResult.outcome, .gracePeriod)
    XCTAssertEqual(invalidResult.outcome, .invalid)
    XCTAssertEqual(invalidResult.validationFailure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(manager.gracePeriodExpiresAt)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
    XCTAssertEqual(provider.validationCount, 2)
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
    XCTAssertEqual(result.validationFailure?.reason, .transportFailure)
    XCTAssertEqual(result.validationFailure?.message, "boom")
    XCTAssertEqual(manager.status, .gracePeriod)
  }
}
