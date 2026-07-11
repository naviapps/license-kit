import XCTest

import LicenseKit

@MainActor
final class LicenseManagerRefreshFailureTests: XCTestCase {
  func testRefreshFailureEntersGraceAndKeepsReason() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateMetadataStorage = TestStateMetadataStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 60,
        serverFailureGracePeriod: 30
      ),
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.failure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .transportFailure)
    XCTAssertEqual(manager.lastRefreshFailure?.message, "offline")
    XCTAssertNotNil(manager.gracePeriodExpiresAt)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testRefreshFailureRecordsFailureCompletionTime() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 60,
        serverFailureGracePeriod: 30
      )
    )

    let refreshStartedAt = Date()
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    let completionThreshold = refreshStartedAt.addingTimeInterval(0.03)
    XCTAssertGreaterThanOrEqual(
      result.failure?.occurredAt ?? .distantPast,
      completionThreshold
    )
    XCTAssertGreaterThanOrEqual(
      manager.lastRefreshFailure?.occurredAt ?? .distantPast,
      completionThreshold
    )
  }

  func testRefreshFailureIgnoresStateMetadataStorageSaveFailure() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .transportFailure)
    XCTAssertNotNil(manager.gracePeriodExpiresAt)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshInvalidResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshInvalidResultActivationDeleteFailureKeepsInvalidState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .invalid)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(activationStorage.activation, activation)
      let retainedMetadataState = try stateMetadataStorage.state(matching: activation)
      XCTAssertEqual(retainedMetadataState?.status, .invalid)
      XCTAssertEqual(retainedMetadataState?.lastValidatedAt, manager.lastValidatedAt)

      let restoredManager = LicenseManager(
        provider: provider,
        activationStorage: activationStorage,
        stateMetadataStorage: stateMetadataStorage
      )
      XCTAssertEqual(restoredManager.status, .invalid)
      XCTAssertNil(restoredManager.activation)
    }
  }

  func testRefreshInvalidResultIgnoresStateMetadataStorageDeleteFailure()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(isValid: false)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    stateMetadataStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testRefreshExpiredResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(
      isValid: true,
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshLocallyExpiredActivationClearsPersistedActivationWithoutProviderCall()
    async throws
  {
    let activation = makeActivation(expiresAt: Date().addingTimeInterval(0.05))
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(activation: activation, status: .active)
    )
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertNil(result.failure)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
    XCTAssertEqual(provider.validationCount, 0)
  }

  func testRefreshLocallyExpiredActivationDeleteFailureKeepsExpiredState()
    async throws
  {
    let activation = makeActivation(expiresAt: Date().addingTimeInterval(0.05))
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(activation: activation, status: .active)
    )
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .expired)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(activationStorage.activation, activation)
      let retainedMetadataState = try stateMetadataStorage.state(matching: activation)
      XCTAssertEqual(retainedMetadataState?.status, .expired)
      XCTAssertEqual(retainedMetadataState?.lastValidatedAt, manager.lastValidatedAt)
      XCTAssertEqual(provider.validationCount, 0)

      let restoredManager = LicenseManager(
        provider: provider,
        activationStorage: activationStorage,
        stateMetadataStorage: stateMetadataStorage
      )
      XCTAssertEqual(restoredManager.status, .expired)
      XCTAssertNil(restoredManager.activation)
    }
  }

  func testRefreshExpiredValidResultClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(
      isValid: true,
      planIdentifier: "pro",
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .expired)
    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshProviderInvalidLicenseErrorClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.failure?.reason, .invalidLicense)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshProviderActivationLimitReachedClearsPersistedActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.activationLimitReached
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.failure?.reason, .activationLimitReached)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshProviderInvalidLicenseActivationDeleteFailureKeepsInvalidState()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.invalidLicense
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .invalid)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(activationStorage.activation, activation)
      let retainedMetadataState = try stateMetadataStorage.state(matching: activation)
      XCTAssertEqual(retainedMetadataState?.status, .invalid)
      XCTAssertEqual(retainedMetadataState?.lastRefreshFailure?.reason, .invalidLicense)

      let restoredManager = LicenseManager(
        provider: provider,
        activationStorage: activationStorage,
        stateMetadataStorage: stateMetadataStorage
      )
      XCTAssertEqual(restoredManager.status, .invalid)
      XCTAssertNil(restoredManager.activation)
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
    XCTAssertEqual(result.failure?.reason, .serverFailure)
    XCTAssertEqual(result.failure?.statusCode, 503)
    XCTAssertEqual(manager.status, .gracePeriod)
  }

  func testRefreshServerFailureWithZeroGracePeriodInvalidatesAndClearsPersistedActivation()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.serverFailure(statusCode: 503)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 60,
        serverFailureGracePeriod: 0
      ),
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.failure?.reason, .serverFailure)
    XCTAssertEqual(result.failure?.statusCode, 503)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshFailureDuringActiveGraceKeepsOriginalGraceExpiration() async throws {
    let activation = makeActivation()
    let originalGraceExpiration = Date().addingTimeInterval(60)
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .gracePeriod)
    XCTAssertEqual(result.failure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertEqual(manager.gracePeriodExpiresAt, originalGraceExpiration)
    XCTAssertEqual(manager.lastRefreshFailure?.message, "offline")
  }

  func testRefreshExpiredGracePeriodActivationDeleteFailureKeepsInvalidState()
    async throws
  {
    let activation = makeActivation()
    let expiredGraceExpiration = Date().addingTimeInterval(0.05)
    let originalFailure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: expiredGraceExpiration,
        lastRefreshFailure: originalFailure
      )
    )
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: .never,
      stateMetadataStorage: stateMetadataStorage
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    let refreshStartedAt = Date()
    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .invalid)
      XCTAssertGreaterThanOrEqual(manager.lastValidatedAt ?? .distantPast, refreshStartedAt)
      XCTAssertNil(manager.activation)
      XCTAssertNil(manager.gracePeriodExpiresAt)
      XCTAssertEqual(manager.lastRefreshFailure?.reason, .gracePeriodExpired)
      XCTAssertEqual(activationStorage.activation, activation)
      let retainedMetadataState = try stateMetadataStorage.state(matching: activation)
      XCTAssertEqual(retainedMetadataState?.status, .invalid)
      XCTAssertEqual(
        retainedMetadataState?.lastRefreshFailure?.reason,
        .gracePeriodExpired
      )
      XCTAssertEqual(provider.validationCount, 0)

      let restoredManager = LicenseManager(
        provider: provider,
        activationStorage: activationStorage,
        refreshPolicy: .never,
        stateMetadataStorage: stateMetadataStorage
      )
      XCTAssertEqual(restoredManager.status, .invalid)
      XCTAssertNil(restoredManager.activation)
    }
  }

  func testRefreshFailureWithZeroGracePeriodInvalidatesAndClearsPersistedActivation()
    async throws
  {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 10,
        failureGracePeriod: 0,
        serverFailureGracePeriod: 0
      ),
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.failure?.reason, .transportFailure)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(manager.gracePeriodExpiresAt)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
    XCTAssertEqual(provider.validationCount, 1)
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
    XCTAssertEqual(result.failure?.reason, .transportFailure)
    XCTAssertEqual(result.failure?.message, "Transport failed.")
    XCTAssertEqual(manager.status, .gracePeriod)
  }

  func testRefreshPropagatesCancellationWithoutChangingState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationError = CancellationError()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertFalse(manager.isRefreshing)
      XCTAssertNil(manager.lastRefreshFailure)
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateMetadataStorage.metadata)
    }
  }

}
