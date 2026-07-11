import XCTest

import LicenseKit

final class LicenseStateValueTests: XCTestCase {
  func testStateResolvesPlanFromActivation() {
    let activation = makeActivation(planIdentifier: " team ", expiresAt: nil)

    let state = LicenseState(
      plan: .unlicensed,
      activation: activation,
      status: .active
    )

    XCTAssertEqual(state.plan, makePlan(identifier: "team", isLicensed: true, expiresAt: nil))
  }

  func testStatusLicensedConvenience() {
    XCTAssertEqual(
      LicenseStatus.allCases,
      [.unlicensed, .active, .gracePeriod, .expired, .invalid, .deactivated]
    )
    XCTAssertTrue(LicenseStatus.active.isLicensed)
    XCTAssertTrue(LicenseStatus.gracePeriod.isLicensed)
    XCTAssertFalse(LicenseStatus.unlicensed.isLicensed)
    XCTAssertFalse(LicenseStatus.expired.isLicensed)
    XCTAssertFalse(LicenseStatus.invalid.isLicensed)
    XCTAssertFalse(LicenseStatus.deactivated.isLicensed)
  }

  func testStatusCodableRawValues() throws {
    XCTAssertEqual(
      LicenseStatus.allCases.map(\.rawValue),
      ["unlicensed", "active", "gracePeriod", "expired", "invalid", "deactivated"]
    )

    for status in LicenseStatus.allCases {
      let data = try JSONEncoder().encode(status)
      XCTAssertEqual(try JSONDecoder().decode(LicenseStatus.self, from: data), status)
    }
  }

  func testStateDefaultsAndConveniences() throws {
    let state = LicenseState()
    XCTAssertEqual(state.plan, .unlicensed)
    XCTAssertNil(state.activation)
    XCTAssertNil(state.source)
    XCTAssertFalse(state.isActivating)
    XCTAssertFalse(state.isRefreshing)
    XCTAssertFalse(state.isDeactivating)
    XCTAssertNil(state.lastValidatedAt)
    XCTAssertEqual(state.status, .unlicensed)
    XCTAssertFalse(state.isLicensed)
    XCTAssertNil(state.gracePeriodExpiresAt)
    XCTAssertNil(state.lastRefreshFailure)

    let activation = try XCTUnwrap(
      LicenseActivation(
        source: makeSource("store"),
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
    let licensedState = LicenseState(
      plan: makePlan(
        identifier: activation.planIdentifier, isLicensed: true, expiresAt: activation.expiresAt),
      activation: activation,
      status: .active
    )
    XCTAssertEqual(licensedState.source, makeSource("store"))
    XCTAssertTrue(licensedState.isLicensed)
  }

  func testStateInitializersNormalizeImpossibleCombinations() throws {
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: makeSource("store"),
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let activationlessActive = LicenseState(
      plan: makePlan(identifier: "pro", isLicensed: true, expiresAt: nil),
      activation: nil,
      status: .active,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_100),
      lastRefreshFailure: failure
    )
    let graceWithoutExpiration = LicenseState(
      plan: .unlicensed,
      activation: activation,
      status: .gracePeriod,
      gracePeriodExpiresAt: nil,
      lastRefreshFailure: failure
    )
    let terminalWithActivation = LicenseState(
      plan: makePlan(identifier: "pro", isLicensed: true, expiresAt: nil),
      activation: activation,
      status: .expired,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_100),
      lastRefreshFailure: failure
    )
    let expiredActivation = makeActivation(
      activatedAt: Date(timeIntervalSince1970: 0),
      expiresAt: Date(timeIntervalSince1970: 1)
    )
    let expiredActivationState = LicenseState(
      plan: makePlan(
        identifier: expiredActivation.planIdentifier,
        isLicensed: true,
        expiresAt: expiredActivation.expiresAt
      ),
      activation: expiredActivation,
      status: .active
    )
    let expiredPlanState = LicenseState(
      plan: makePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1)
      ),
      activation: activation,
      status: .active
    )
    let concurrentOperationState = LicenseState(
      plan: makePlan(
        identifier: activation.planIdentifier, isLicensed: true, expiresAt: activation.expiresAt),
      activation: activation,
      isActivating: true,
      isRefreshing: true,
      isDeactivating: true,
      status: .active
    )
    let activationlessRefreshing = LicenseState(
      isRefreshing: true,
      status: .unlicensed
    )
    let deactivationDuringInactiveState = LicenseState(
      isDeactivating: true,
      status: .deactivated
    )

    XCTAssertEqual(activationlessActive.status, .unlicensed)
    XCTAssertEqual(activationlessActive.plan, .unlicensed)
    XCTAssertNil(activationlessActive.activation)
    XCTAssertNil(activationlessActive.gracePeriodExpiresAt)
    XCTAssertNil(activationlessActive.lastRefreshFailure)

    XCTAssertEqual(graceWithoutExpiration.status, .active)
    XCTAssertEqual(
      graceWithoutExpiration.plan,
      makePlan(
        identifier: activation.planIdentifier,
        isLicensed: true,
        expiresAt: activation.expiresAt
      )
    )
    XCTAssertEqual(graceWithoutExpiration.activation, activation)
    XCTAssertNil(graceWithoutExpiration.gracePeriodExpiresAt)
    XCTAssertNil(graceWithoutExpiration.lastRefreshFailure)

    XCTAssertEqual(terminalWithActivation.status, .expired)
    XCTAssertEqual(terminalWithActivation.plan, .unlicensed)
    XCTAssertNil(terminalWithActivation.activation)
    XCTAssertNil(terminalWithActivation.gracePeriodExpiresAt)
    XCTAssertEqual(terminalWithActivation.lastRefreshFailure, failure)

    XCTAssertEqual(expiredActivationState.status, .expired)
    XCTAssertEqual(expiredActivationState.plan, .unlicensed)
    XCTAssertNil(expiredActivationState.activation)
    XCTAssertFalse(expiredActivationState.isLicensed)

    XCTAssertEqual(expiredPlanState.status, .expired)
    XCTAssertEqual(expiredPlanState.plan, .unlicensed)
    XCTAssertNil(expiredPlanState.activation)
    XCTAssertFalse(expiredPlanState.isLicensed)

    XCTAssertTrue(concurrentOperationState.isActivating)
    XCTAssertFalse(concurrentOperationState.isRefreshing)
    XCTAssertFalse(concurrentOperationState.isDeactivating)

    XCTAssertFalse(activationlessRefreshing.isActivating)
    XCTAssertFalse(activationlessRefreshing.isRefreshing)
    XCTAssertTrue(deactivationDuringInactiveState.isDeactivating)
  }

}
