import XCTest

@testable import LicenseKit

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
    provider.deactivationError = LicenseProviderError.transportFailure(message: "offline")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "offline"))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(provider.deactivationCount, 1)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNil(stateSnapshotStorage.snapshot)
    }
  }

  func testDeactivateReportsUnexpectedProviderFailureAfterLocalCleanup() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.deactivationError = TestUnexpectedError(message: "boom")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected provider failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .requestFailure(message: "boom"))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertNil(manager.activation)
      XCTAssertEqual(provider.deactivationCount, 1)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNil(stateSnapshotStorage.snapshot)
    }
  }

  func testDeactivateReportsActivationStorageDeleteFailureWithoutClearingState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    do {
      try await manager.deactivate()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "keychain unavailable"))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(provider.deactivationCount, 1)
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
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
      XCTAssertEqual(error, .storageFailure(message: "defaults unavailable"))
      XCTAssertEqual(manager.status, .deactivated)
      XCTAssertNil(manager.activation)
      XCTAssertNil(activationStorage.activation)
      XCTAssertNotNil(stateSnapshotStorage.snapshot)
    }
  }

  func testDeactivateWithoutActivationSkipsProviderAndClearsPersistence() async throws {
    let provider = TestProvider(activation: makeActivation())
    let activationStorage = TestActivationStorage()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertNil(state.activation)
    XCTAssertEqual(provider.deactivationCount, 0)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testDeactivateReturnsUpdatedState() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    let state = try await manager.deactivate()

    XCTAssertEqual(state.status, .deactivated)
    XCTAssertNil(state.activation)
    XCTAssertEqual(provider.deactivationCount, 1)
    XCTAssertEqual(provider.lastDeactivatedActivation, activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }
}
