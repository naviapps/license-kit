import XCTest

@testable import LicenseKit

final class LicenseStateStoreTests: XCTestCase {
  func testApplyActivationUpdatesPlanStatusAndSnapshot() {
    let activation = makeActivation(planID: "team")
    var store = LicenseStateStore()

    store.applyActivation(activation)

    XCTAssertEqual(store.plan.id, "team")
    XCTAssertEqual(store.status, .active)
    XCTAssertEqual(store.lastValidatedAt, activation.activatedAt)
    XCTAssertEqual(store.state.activation, activation)
    XCTAssertEqual(store.state.source, activation.source)
  }

  func testInitialStateNormalizesImpossibleActivationlessLicensedStatus() {
    let store = LicenseStateStore(
      initialActivation: nil,
      resolvedPlan: LicensePlan(id: "pro", isLicensed: true, expiresAt: nil),
      status: .gracePeriod,
      gracePeriodExpiresAt: Date().addingTimeInterval(60)
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .unlicensed)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }

  func testInitialStateKeepsGraceOnlyWhenActivationIsPresent() {
    let activation = makeActivation()
    let graceUntil = Date().addingTimeInterval(60)

    let graceStore = LicenseStateStore(
      initialActivation: activation,
      status: .gracePeriod,
      gracePeriodExpiresAt: graceUntil
    )
    XCTAssertEqual(graceStore.status, .gracePeriod)
    XCTAssertEqual(graceStore.gracePeriodExpiresAt, graceUntil)

    let activeStore = LicenseStateStore(
      initialActivation: activation,
      status: .active,
      gracePeriodExpiresAt: graceUntil
    )
    XCTAssertEqual(activeStore.status, .active)
    XCTAssertNil(activeStore.gracePeriodExpiresAt)
  }

  func testInitialStateNormalizesGraceWithoutExpiration() {
    let store = LicenseStateStore(
      initialActivation: makeActivation(),
      status: .gracePeriod,
      gracePeriodExpiresAt: nil
    )

    XCTAssertEqual(store.status, .active)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }

  func testInitialStateNormalizesActivationWithUnlicensedStatus() {
    let store = LicenseStateStore(
      initialActivation: makeActivation(),
      resolvedPlan: LicensePlan(id: "pro", isLicensed: true, expiresAt: nil),
      status: .expired,
      gracePeriodExpiresAt: Date().addingTimeInterval(60)
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .expired)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }

  func testInitialStateRebuildsUnlicensedPlanForLicensedActivation() {
    let activation = makeActivation(planID: "pro")
    let store = LicenseStateStore(
      initialActivation: activation,
      resolvedPlan: .unlicensed,
      status: .active
    )

    XCTAssertEqual(store.activation, activation)
    XCTAssertEqual(store.plan, LicensePlan.resolve(activation: activation))
    XCTAssertEqual(store.status, .active)
  }

  func testMarkGraceStoresExpirationAndFailure() {
    let activation = makeActivation()
    let failure = LicenseRefreshFailure(
      reason: .networkFailure,
      message: "offline",
      occurredAt: Date()
    )
    var store = LicenseStateStore(initialActivation: activation)
    let graceUntil = Date().addingTimeInterval(60)

    store.markGrace(until: graceUntil, failure: failure)

    XCTAssertEqual(store.status, .gracePeriod)
    XCTAssertEqual(store.gracePeriodExpiresAt, graceUntil)
    XCTAssertEqual(store.lastRefreshFailure, failure)
  }

  func testRecordRefreshFailureStoresReasonWithoutChangingStatus() {
    let failure = LicenseRefreshFailure(
      reason: .providerRequestFailure,
      message: "server unavailable",
      occurredAt: Date()
    )
    var store = LicenseStateStore()

    store.recordRefreshFailure(failure)

    XCTAssertEqual(store.status, .unlicensed)
    XCTAssertEqual(store.lastRefreshFailure, failure)
  }

  func testSetActivatingClearsGraceAndRefreshFailure() {
    let failure = LicenseRefreshFailure(
      reason: .networkFailure,
      message: "offline",
      occurredAt: Date()
    )
    var store = LicenseStateStore(initialActivation: makeActivation())
    store.markGrace(until: Date().addingTimeInterval(60), failure: failure)

    store.setActivating()

    XCTAssertEqual(store.status, .activating)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
  }

  func testSetOfferingsAndRefreshingUpdateState() {
    let offering = LicenseOffering(id: "team", name: "Team")
    var store = LicenseStateStore()

    store.setOfferings([offering])
    store.setRefreshing(true)

    XCTAssertEqual(store.offerings, [offering])
    XCTAssertTrue(store.isRefreshing)
    XCTAssertEqual(store.state.offerings, [offering])
    XCTAssertTrue(store.state.isRefreshing)
  }

  func testMarkInvalidClearsActivationPlanAndGraceButKeepsFailure() {
    let failure = LicenseRefreshFailure(
      reason: .invalidLicense,
      occurredAt: Date()
    )
    var store = LicenseStateStore(initialActivation: makeActivation())
    store.markGrace(until: Date().addingTimeInterval(60), failure: failure)

    store.markInvalid(failure: failure)

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .invalid)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertEqual(store.lastRefreshFailure, failure)
  }

  func testMarkDeactivatedClearsActivationValidationAndFailure() {
    let failure = LicenseRefreshFailure(
      reason: .networkFailure,
      message: "offline",
      occurredAt: Date()
    )
    var store = LicenseStateStore(initialActivation: makeActivation())
    store.markGrace(until: Date().addingTimeInterval(60), failure: failure)

    store.markDeactivated()

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertNil(store.lastValidatedAt)
    XCTAssertEqual(store.status, .deactivated)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
  }

  func testApplyValidationSnapshotUpdatesActivationAndClearsRefreshFailure() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(planID: "starter", customerID: "cus_old")
    var store = LicenseStateStore(initialActivation: activation)
    store.markGrace(
      until: checkedAt.addingTimeInterval(60),
      failure: LicenseRefreshFailure(
        reason: .networkFailure,
        message: "offline",
        occurredAt: checkedAt
      )
    )

    let updatedActivation = store.applyValidationSnapshot(
      LicenseValidationSnapshot(
        planID: "team",
        isLicensed: true,
        expiresAt: checkedAt.addingTimeInterval(3_600),
        remainingActivations: 2,
        customerID: "cus_new",
        checkedAt: checkedAt
      )
    )

    XCTAssertEqual(store.status, .active)
    XCTAssertEqual(store.plan.id, "team")
    XCTAssertEqual(store.lastValidatedAt, checkedAt)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
    XCTAssertEqual(updatedActivation?.planID, "team")
    XCTAssertEqual(updatedActivation?.customerID, "cus_new")
    XCTAssertEqual(updatedActivation?.remainingActivations, 2)
  }

  func testApplyValidationSnapshotClearsActivationWhenInvalidOrExpired() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    var invalidStore = LicenseStateStore(initialActivation: makeActivation())

    XCTAssertNil(
      invalidStore.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planID: nil,
          isLicensed: false,
          expiresAt: nil,
          remainingActivations: nil,
          customerID: nil,
          checkedAt: checkedAt
        )
      )
    )
    XCTAssertNil(invalidStore.activation)
    XCTAssertEqual(invalidStore.plan, .unlicensed)
    XCTAssertEqual(invalidStore.status, .invalid)

    var expiredStore = LicenseStateStore(initialActivation: makeActivation())
    XCTAssertNil(
      expiredStore.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planID: nil,
          isLicensed: false,
          expiresAt: checkedAt.addingTimeInterval(-1),
          remainingActivations: nil,
          customerID: nil,
          checkedAt: checkedAt
        )
      )
    )
    XCTAssertNil(expiredStore.activation)
    XCTAssertEqual(expiredStore.plan, .unlicensed)
    XCTAssertEqual(expiredStore.status, .expired)
  }

  func testResetClearsActivationValidationGraceAndFailure() {
    var store = LicenseStateStore(
      initialActivation: makeActivation(),
      lastValidatedAt: Date()
    )
    store.markGrace(
      until: Date().addingTimeInterval(60),
      failure: LicenseRefreshFailure(
        reason: .providerRequestFailure, message: "x", occurredAt: Date())
    )

    store.resetToUnlicensed()

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .unlicensed)
    XCTAssertNil(store.lastValidatedAt)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
  }
}
