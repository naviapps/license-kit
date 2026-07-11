import XCTest

import LicenseKit

@MainActor
final class LicenseManagerRefreshDecisionTests: XCTestCase {
  func testNeedsRefreshUsesConfiguredInterval() throws {
    let activation = makeActivation(activatedAt: Date(timeIntervalSince1970: 0))
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertFalse(manager.needsRefresh(now: Date(timeIntervalSince1970: 9)))
    XCTAssertTrue(manager.needsRefresh(now: Date(timeIntervalSince1970: 10)))
  }

  func testNeedsRefreshReturnsTrueWhenActivationIsLocallyExpired() throws {
    let now = Date()
    let expiresAt = now.addingTimeInterval(60)
    let activation = makeActivation(activatedAt: now, expiresAt: expiresAt)
    let stateMetadataStorage = TestStateMetadataStorage(
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
      stateMetadataStorage: stateMetadataStorage
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

  func testNeedsRefreshReturnsFalseForNonFiniteDate() throws {
    let activation = makeActivation()
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation)
    )

    XCTAssertFalse(
      manager.needsRefresh(now: Date(timeIntervalSinceReferenceDate: .infinity))
    )
  }

  func testNeedsRefreshReturnsTrueWhenGracePeriodHasExpired() throws {
    let activation = makeActivation()
    let gracePeriodExpiresAt = Date().addingTimeInterval(60)
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(
        activation: activation,
        lastValidatedAt: gracePeriodExpiresAt,
        status: .gracePeriod,
        gracePeriodExpiresAt: gracePeriodExpiresAt,
        lastRefreshFailure: LicenseRefreshFailure(
          reason: .transportFailure,
          message: "offline",
          occurredAt: gracePeriodExpiresAt.addingTimeInterval(-60)
        )
      )
    )
    let manager = LicenseManager(
      provider: TestProvider(activation: activation),
      activationStorage: TestActivationStorage(activation: activation),
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 3_600,
        failureGracePeriod: 60,
        serverFailureGracePeriod: 30
      ),
      stateMetadataStorage: stateMetadataStorage
    )

    XCTAssertFalse(manager.needsRefresh(now: gracePeriodExpiresAt.addingTimeInterval(-1)))
    XCTAssertTrue(manager.needsRefresh(now: gracePeriodExpiresAt))
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

  func testRefreshInvalidatesExpiredGracePeriodEvenWhenRefreshPolicyIsDisabled() async throws {
    let activation = makeActivation()
    let gracePeriodExpiresAt = Date().addingTimeInterval(0.05)
    let provider = TestProvider(activation: activation)
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(
      state: makeState(
        activation: activation,
        status: .gracePeriod,
        gracePeriodExpiresAt: gracePeriodExpiresAt,
        lastRefreshFailure: LicenseRefreshFailure(
          reason: .transportFailure,
          message: "offline",
          occurredAt: gracePeriodExpiresAt.addingTimeInterval(-60)
        )
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
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .invalid)
    XCTAssertEqual(result.failure?.reason, .gracePeriodExpired)
    XCTAssertEqual(provider.validationCount, 0)
    XCTAssertEqual(manager.status, .invalid)
    XCTAssertGreaterThanOrEqual(manager.lastValidatedAt ?? .distantPast, refreshStartedAt)
    XCTAssertEqual(manager.lastRefreshFailure?.reason, .gracePeriodExpired)
    XCTAssertNil(manager.activation)
    XCTAssertNil(activationStorage.activation)
    XCTAssertNil(stateMetadataStorage.metadata)
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

}
