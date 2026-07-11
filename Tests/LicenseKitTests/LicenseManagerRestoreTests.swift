import XCTest

import LicenseKit

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

  func testInitialRestoreKeepsStateMetadataLoadFailureObservable() {
    let activation = makeActivation()
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.loadError = LicenseError.storageFailure(
      message: "Storage operation failed.")

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertEqual(
      manager.initialRestoreError, .storageFailure(message: "Storage operation failed."))
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
  }

  func testInitialRestoreKeepsStateMetadataDecodeFailureObservableAndClearsPayload() {
    let activation = makeActivation()
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.metadataData = Data("not json".utf8)

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateMetadataStorage: stateMetadataStorage
    )

    guard case .storageFailure(let message) = manager.initialRestoreError else {
      return XCTFail("Expected metadata decode failure to be exposed.")
    }
    XCTAssertFalse(message.isEmpty)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
    XCTAssertNil(stateMetadataStorage.metadataData)
  }

  func testInitialRestoreIgnoresStateMetadataDeleteFailureAfterDecodeFailure() {
    let activation = makeActivation()
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.metadataData = Data("not json".utf8)
    stateMetadataStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      stateMetadataStorage: stateMetadataStorage
    )

    guard case .storageFailure(let message) = manager.initialRestoreError else {
      return XCTFail("Expected metadata decode failure to be exposed.")
    }
    XCTAssertFalse(message.isEmpty)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
    XCTAssertNotNil(stateMetadataStorage.metadataData)
  }

  func testInitialRestoreClearsMetadataWhenActivationIsMissing() {
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(activation: makeActivation())
    )

    let manager = LicenseManager(
      provider: TestProvider(activation: makeActivation()),
      activationStorage: TestActivationStorage(),
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.status, .unlicensed)
    XCTAssertNil(manager.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreUsesMatchingStateMetadata() {
    let activation = makeActivation()
    let lastValidatedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let gracePeriodExpiresAt = Date().addingTimeInterval(60)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_050)
    )
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .gracePeriod)
    XCTAssertEqual(manager.lastValidatedAt, lastValidatedAt)
    XCTAssertEqual(manager.gracePeriodExpiresAt, gracePeriodExpiresAt)
    XCTAssertEqual(manager.lastRefreshFailure, failure)
  }

  func testInitialRestoreClearsMismatchedStateMetadata() {
    let activation = makeActivation()
    let staleActivation = makeActivation(
      activatedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.activation, activation)
    XCTAssertEqual(manager.status, .active)
    XCTAssertNil(manager.lastValidatedAt)
    XCTAssertNil(manager.gracePeriodExpiresAt)
    XCTAssertNil(manager.lastRefreshFailure)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreCanSkipPersistedActivation() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage,
      restorePersistedActivation: false
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.status, .unlicensed)
    XCTAssertNil(manager.activation)
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreInvalidatesExpiredGracePeriodAndClearsPersistence() throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1)
    )
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertEqual(manager.status, .invalid)
    XCTAssertEqual(manager.lastRefreshFailure, failure)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreKeepsActivationDeleteFailureObservable() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.deleteError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertEqual(
      manager.initialRestoreError,
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertEqual(activationStorage.activation, activation)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreIgnoresStateMetadataDeleteFailure() {
    let activation = makeActivation()
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1)
      )
    )
    stateMetadataStorage.deleteError = TestUnexpectedError(message: "defaults unavailable")

    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNotNil(stateMetadataStorage.metadata)
  }

  func testInitialRestoreExpiresPastActivationAndClearsPersistence() throws {
    let activation = makeActivation(
      activatedAt: Date(timeIntervalSince1970: 0),
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let provider = TestProvider(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertEqual(manager.status, .expired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
  }
}
