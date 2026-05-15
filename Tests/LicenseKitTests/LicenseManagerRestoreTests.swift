import XCTest

@testable import LicenseKit

@MainActor
final class LicenseManagerRestoreTests: XCTestCase {
  func testInitialRestoreKeepsActivationStorageLoadFailureObservable() {
    let activationStorage = TestActivationStorage()
    activationStorage.loadError = LicenseError.storageFailure(message: "Storage operation failed.")

    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: activationStorage
    )

    XCTAssertEqual(
      manager.initialRestoreError, .storageFailure(message: "Storage operation failed."))
    XCTAssertEqual(manager.status, .unlicensed)
  }

  func testInitialRestoreKeepsStateSnapshotLoadFailureObservable() {
    let activation = makeActivation()
    let stateSnapshotStorage = TestStateSnapshotStorage()
    stateSnapshotStorage.loadError = LicenseError.storageFailure(
      message: "Storage operation failed.")

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(
      manager.initialRestoreError, .storageFailure(message: "Storage operation failed."))
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
  }

  func testInitialRestoreUsesMatchingStateSnapshot() {
    let activation = makeActivation()
    let lastValidatedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let gracePeriodExpiresAt = Date().addingTimeInterval(60)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_050)
    )
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        lastValidatedAt: lastValidatedAt,
        status: .gracePeriod,
        gracePeriodExpiresAt: gracePeriodExpiresAt,
        lastRefreshFailure: failure
      )
    )

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertEqual(manager.lastValidatedAt, lastValidatedAt)
    XCTAssertEqual(manager.gracePeriodExpiresAt, gracePeriodExpiresAt)
    XCTAssertEqual(manager.lastRefreshFailure, failure)
  }

  func testInitialRestoreIgnoresMismatchedStateSnapshot() {
    let activation = makeActivation(activationID: "current-instance")
    let staleActivation = makeActivation(activationID: "stale-instance")
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: staleActivation,
        lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        status: .gracePeriod,
        gracePeriodExpiresAt: Date().addingTimeInterval(60),
        lastRefreshFailure: LicenseRefreshFailure(
          reason: .transportFailure,
          message: "offline",
          occurredAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
      )
    )

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
    XCTAssertNil(manager.lastValidatedAt)
    XCTAssertNil(manager.gracePeriodExpiresAt)
    XCTAssertNil(manager.lastRefreshFailure)
    XCTAssertNotNil(stateSnapshotStorage.snapshot)
  }

  func testInitialRestoreCanSkipPersistedActivation() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(state: makeState(activation: activation))

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage,
      restorePersistedActivation: false
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.status, .unlicensed)
    XCTAssertNil(manager.activation)
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertNotNil(stateSnapshotStorage.snapshot)
  }

  func testInitialRestoreInvalidatesExpiredGracePeriodAndClearsPersistence() throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1)
    )
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1),
        lastRefreshFailure: failure
      )
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(manager.status, .invalid)
    XCTAssertEqual(manager.lastRefreshFailure, failure)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }

  func testInitialRestoreKeepsActivationDeleteFailureObservable() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(manager.initialRestoreError, .storageFailure(message: "keychain unavailable"))
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertNotNil(stateSnapshotStorage.snapshot)
  }

  func testInitialRestoreKeepsStateSnapshotDeleteFailureObservable() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )
    stateSnapshotStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(manager.initialRestoreError, .storageFailure(message: "defaults unavailable"))
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNotNil(stateSnapshotStorage.snapshot)
  }

  func testInitialRestoreExpiresPastActivationAndClearsPersistence() throws {
    let activation = makeActivation(expiresAt: Date(timeIntervalSince1970: 1))
    let provider = TestProvider(activation: activation)
    let stateSnapshotStorage = TestStateSnapshotStorage(
      state: makeState(
        activation: activation,
        status: .active,
        gracePeriodExpiresAt: nil
      )
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateSnapshotStorage: stateSnapshotStorage
    )

    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateSnapshotStorage.snapshot)
  }
}
