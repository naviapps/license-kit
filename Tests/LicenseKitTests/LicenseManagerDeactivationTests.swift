import XCTest

import LicenseKit

@MainActor
final class LicenseManagerDeactivationTests: XCTestCase {
  func testDeactivateRejectsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let activationState: LicenseState = manager.activate(.licenseKey("KEY"))
    try await waitForManagerState { manager.isActivating }

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
    try await waitForManagerState { manager.isRefreshing }

    do {
      try await manager.deactivate()
      XCTFail("Expected refreshInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .refreshInProgress)
    }

    _ = try await refresh
  }

  func testActivateRejectsConcurrentDeactivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let deactivationState: LicenseState = manager.deactivate()
    try await waitForManagerState { manager.isDeactivating }

    do {
      try await manager.activate(.licenseKey("KEY"))
      XCTFail("Expected deactivationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .deactivationInProgress)
    }

    let finalState = try await deactivationState
    XCTAssertFalse(finalState.isDeactivating)
  }

  func testApplyActivationRejectsConcurrentDeactivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let deactivationState: LicenseState = manager.deactivate()
    try await waitForManagerState { manager.isDeactivating }

    do {
      try manager.applyActivation(activation)
      XCTFail("Expected deactivationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .deactivationInProgress)
    }

    let finalState = try await deactivationState
    XCTAssertFalse(finalState.isDeactivating)
  }

  func testRefreshSkipsConcurrentDeactivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let deactivationState: LicenseState = manager.deactivate()
    try await waitForManagerState { manager.isDeactivating }

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedDeactivationInProgress)
    XCTAssertTrue(result.state.isDeactivating)
    let finalState = try await deactivationState
    XCTAssertFalse(finalState.isDeactivating)
  }

  func testDeactivateRejectsConcurrentDeactivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let deactivationState: LicenseState = manager.deactivate()
    try await waitForManagerState { manager.isDeactivating }

    do {
      try await manager.deactivate()
      XCTFail("Expected deactivationInProgress")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .deactivationInProgress)
    }

    let finalState = try await deactivationState
    XCTAssertFalse(finalState.isDeactivating)
  }

  func testDeactivateReportsProviderFailureAfterLocalCleanup() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "offline"))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertFalse(manager.isDeactivating)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(provider.deactivationCount, 1)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNil(stateMetadataStorage.metadata)
    }
  }

  func testDeactivateReportsUnexpectedProviderFailureAfterLocalCleanup() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationError = TestUnexpectedError(message: "boom")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "Transport failed."))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertFalse(manager.isDeactivating)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(provider.deactivationCount, 1)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNil(stateMetadataStorage.metadata)
    }
  }

  func testDeactivatePropagatesCancellationAfterLocalCleanup() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationError = CancellationError()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertFalse(manager.isDeactivating)
      XCTAssertNil(manager.activation)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNil(stateMetadataStorage.metadata)
      XCTAssertEqual(provider.deactivationCount, 1)
    }
  }

  func testDeactivateReportsActivationStorageDeleteFailureBeforeProviderCall() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertFalse(manager.isDeactivating)
      XCTAssertEqual(provider.deactivationCount, 0)
      XCTAssertNil(provider.lastDeactivatedActivation)
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateMetadataStorage.metadata)
    }
  }

  func testDeactivateIgnoresStateMetadataStorageDeleteFailureAfterClearingActivation() async throws
  {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    stateMetadataStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertEqual(manager.status, .deactivated)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testDeactivateWithoutActivationSkipsProviderAndClearsPersistence() async throws {
    let provider = TestProvider(activation: makeActivation())
    let activationStorage = TestActivationStorage()
    let stateMetadataStorage = TestStateMetadataStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertNil(state.activation)
    XCTAssertEqual(provider.deactivationCount, 0)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testDeactivateReturnsUpdatedState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertNil(state.activation)
    XCTAssertEqual(provider.deactivationCount, 1)
    XCTAssertEqual(provider.lastDeactivatedActivation, activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }
}
