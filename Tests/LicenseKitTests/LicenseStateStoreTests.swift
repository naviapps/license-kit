import XCTest

@testable import LicenseKit

final class LicenseStateStoreTests: XCTestCase {
  func testApplyActivationUpdatesPlanStatusAndState() {
    let activation = makeActivation(planIdentifier: "team")
    var store = LicenseStateStore(isActivating: true)

    store.applyActivation(activation)

    XCTAssertFalse(store.isActivating)
    XCTAssertFalse(store.state.isActivating)
    XCTAssertEqual(store.plan.identifier, "team")
    XCTAssertEqual(store.status, .active)
    XCTAssertEqual(store.lastValidatedAt, activation.activatedAt)
    XCTAssertEqual(store.state.activation, activation)
    XCTAssertEqual(store.state.source, activation.source)
  }

  func testApplyActivationExpiresPastActivation() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(
      planIdentifier: "team",
      activatedAt: now.addingTimeInterval(-1),
      expiresAt: now
    )
    var store = LicenseStateStore(initialActivation: makeActivation())
    store.markGrace(
      until: now.addingTimeInterval(60),
      failure: LicenseRefreshFailure(
        reason: .transportFailure,
        message: "offline",
        occurredAt: now
      )
    )

    XCTAssertFalse(store.applyActivation(activation, now: now))

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .expired)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
  }

  func testValidationSnapshotWithoutPlanIdentifierKeepsCurrentActivationPlan() {
    let activation = makeActivation(planIdentifier: "team")
    var store = LicenseStateStore(initialActivation: activation)

    let updatedActivation = store.applyValidationSnapshot(
      LicenseValidationSnapshot(
        planIdentifier: nil,
        isLicensed: true,
        expiresAt: nil,
        checkedAt: Date(timeIntervalSince1970: 1_700_000_100)
      )
    )

    XCTAssertEqual(updatedActivation?.planIdentifier, "team")
    XCTAssertEqual(store.activation?.planIdentifier, "team")
    XCTAssertEqual(store.plan, makePlan(identifier: "team", isLicensed: true))
    XCTAssertEqual(store.status, .active)
  }

  func testValidationSnapshotDefaultsToActivationPlanWhenPlanIdentifierIsOmitted() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(planIdentifier: "fallback")
    let snapshot = LicenseValidationSnapshot(
      result: makeValidationResult(
        isValid: true,
        planIdentifier: nil
      ),
      activation: activation,
      checkedAt: checkedAt
    )

    XCTAssertEqual(snapshot.planIdentifier, "fallback")
    XCTAssertTrue(snapshot.isLicensed)
    XCTAssertNil(snapshot.expiresAt)
    XCTAssertEqual(snapshot.checkedAt, checkedAt)
  }

  func testValidationSnapshotDoesNotNormalizeExplicitPlanIdentifier() {
    let snapshot = LicenseValidationSnapshot(
      planIdentifier: " \n ",
      isLicensed: true,
      expiresAt: nil,
      checkedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertEqual(snapshot.planIdentifier, " \n ")
  }

  func testInitialStateNormalizesImpossibleActivationlessLicensedStatus() {
    let store = LicenseStateStore(
      initialActivation: nil,
      resolvedPlan: makePlan(identifier: "pro", isLicensed: true, expiresAt: nil),
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

  func testInitialStateExpiresPastActivation() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(
      activatedAt: now.addingTimeInterval(-1),
      expiresAt: now
    )
    let store = LicenseStateStore(
      initialActivation: activation,
      status: .active,
      now: now
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .expired)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }

  func testInitialStateInvalidatesExpiredGracePeriod() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation()
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: now.addingTimeInterval(-60)
    )
    let store = LicenseStateStore(
      initialActivation: activation,
      status: .gracePeriod,
      gracePeriodExpiresAt: now,
      lastRefreshFailure: failure,
      now: now
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .invalid)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertEqual(store.lastRefreshFailure, failure)
  }

  func testInitialStateNormalizesActivationWithUnlicensedStatus() {
    let store = LicenseStateStore(
      initialActivation: makeActivation(),
      resolvedPlan: makePlan(identifier: "pro", isLicensed: true, expiresAt: nil),
      status: .expired,
      gracePeriodExpiresAt: Date().addingTimeInterval(60)
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .expired)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }

  func testInitialStateRebuildsUnlicensedPlanForLicensedActivation() {
    let activation = makeActivation(planIdentifier: "pro")
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
      reason: .transportFailure,
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

  func testMarkGraceRequiresActivation() {
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date()
    )
    var store = LicenseStateStore()

    store.markGrace(until: Date().addingTimeInterval(60), failure: failure)

    XCTAssertEqual(store.status, .unlicensed)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
  }

  func testSetActivatingPreservesPreviousState() {
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date()
    )
    var store = LicenseStateStore(initialActivation: makeActivation())
    let graceUntil = Date().addingTimeInterval(60)
    store.markGrace(until: graceUntil, failure: failure)
    store.setRefreshing(true)

    store.setActivating()

    XCTAssertTrue(store.isActivating)
    XCTAssertFalse(store.isRefreshing)
    XCTAssertEqual(store.status, .gracePeriod)
    XCTAssertEqual(store.gracePeriodExpiresAt, graceUntil)
    XCTAssertEqual(store.lastRefreshFailure, failure)
  }

  func testSetRefreshingMarksLicensedStoreRefreshing() {
    var store = LicenseStateStore(initialActivation: makeActivation())

    store.setRefreshing(true)

    XCTAssertTrue(store.isRefreshing)
    XCTAssertTrue(store.state.isRefreshing)
  }

  func testSetRefreshingCanClearRefreshState() {
    var store = LicenseStateStore(initialActivation: makeActivation())
    store.setRefreshing(true)

    store.setRefreshing(false)

    XCTAssertFalse(store.isRefreshing)
    XCTAssertFalse(store.state.isRefreshing)
  }

  func testSetRefreshingRequiresActivationAndNoActivationInProgress() {
    var activationlessStore = LicenseStateStore()
    var activatingStore = LicenseStateStore(
      initialActivation: makeActivation(),
      isActivating: true,
      isRefreshing: true
    )

    activationlessStore.setRefreshing(true)
    activatingStore.setRefreshing(true)

    XCTAssertFalse(activationlessStore.isRefreshing)
    XCTAssertFalse(activationlessStore.state.isRefreshing)
    XCTAssertFalse(activatingStore.isRefreshing)
    XCTAssertFalse(activatingStore.state.isRefreshing)
  }

  func testInitialRefreshingRequiresResolvedLicensedState() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let expiredStore = LicenseStateStore(
      initialActivation: makeActivation(
        activatedAt: now.addingTimeInterval(-1),
        expiresAt: now
      ),
      isRefreshing: true,
      status: .active,
      now: now
    )
    let unlicensedStore = LicenseStateStore(
      initialActivation: makeActivation(),
      isRefreshing: true,
      status: .invalid
    )

    XCTAssertFalse(expiredStore.isRefreshing)
    XCTAssertFalse(expiredStore.state.isRefreshing)
    XCTAssertFalse(unlicensedStore.isRefreshing)
    XCTAssertFalse(unlicensedStore.state.isRefreshing)
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
      reason: .transportFailure,
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
    let activation = makeActivation(planIdentifier: "starter")
    var store = LicenseStateStore(initialActivation: activation)
    store.markGrace(
      until: checkedAt.addingTimeInterval(60),
      failure: LicenseRefreshFailure(
        reason: .transportFailure,
        message: "offline",
        occurredAt: checkedAt
      )
    )

    let updatedActivation = store.applyValidationSnapshot(
      LicenseValidationSnapshot(
        planIdentifier: "team",
        isLicensed: true,
        expiresAt: checkedAt.addingTimeInterval(3_600),
        checkedAt: checkedAt
      )
    )

    XCTAssertEqual(store.status, .active)
    XCTAssertEqual(store.plan.identifier, "team")
    XCTAssertEqual(store.lastValidatedAt, checkedAt)
    XCTAssertNil(store.gracePeriodExpiresAt)
    XCTAssertNil(store.lastRefreshFailure)
    XCTAssertEqual(store.activation, updatedActivation)
    XCTAssertEqual(updatedActivation?.planIdentifier, "team")
    XCTAssertEqual(updatedActivation?.source, activation.source)
    XCTAssertEqual(updatedActivation?.licenseKey, activation.licenseKey)
    XCTAssertEqual(updatedActivation?.activationIdentifier, activation.activationIdentifier)
    XCTAssertEqual(updatedActivation?.activatedAt, activation.activatedAt)
    XCTAssertEqual(updatedActivation?.expiresAt, checkedAt.addingTimeInterval(3_600))
  }

  func testApplyValidationSnapshotClearsActivationWhenInvalidOrExpired() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    var invalidStore = LicenseStateStore(initialActivation: makeActivation())

    XCTAssertNil(
      invalidStore.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planIdentifier: nil,
          isLicensed: false,
          expiresAt: nil,
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
          planIdentifier: nil,
          isLicensed: false,
          expiresAt: checkedAt.addingTimeInterval(-1),
          checkedAt: checkedAt
        )
      )
    )
    XCTAssertNil(expiredStore.activation)
    XCTAssertEqual(expiredStore.plan, .unlicensed)
    XCTAssertEqual(expiredStore.status, .expired)

    var expiredValidStore = LicenseStateStore(initialActivation: makeActivation())
    XCTAssertNil(
      expiredValidStore.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planIdentifier: "pro",
          isLicensed: true,
          expiresAt: checkedAt,
          checkedAt: checkedAt
        )
      )
    )
    XCTAssertNil(expiredValidStore.activation)
    XCTAssertEqual(expiredValidStore.plan, .unlicensed)
    XCTAssertEqual(expiredValidStore.status, .expired)
  }

  func testApplyValidationSnapshotClearsActivationWhenExpirationPrecedesActivation() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let checkedAt = activatedAt.addingTimeInterval(-20)
    var store = LicenseStateStore(initialActivation: makeActivation(activatedAt: activatedAt))

    XCTAssertNil(
      store.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planIdentifier: "pro",
          isLicensed: true,
          expiresAt: activatedAt.addingTimeInterval(-10),
          checkedAt: checkedAt
        )
      )
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .invalid)
  }

  func testApplyValidationSnapshotRequiresActivationForLicensedState() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    var store = LicenseStateStore()

    XCTAssertNil(
      store.applyValidationSnapshot(
        LicenseValidationSnapshot(
          planIdentifier: "pro",
          isLicensed: true,
          expiresAt: checkedAt.addingTimeInterval(3_600),
          checkedAt: checkedAt
        )
      )
    )

    XCTAssertNil(store.activation)
    XCTAssertEqual(store.plan, .unlicensed)
    XCTAssertEqual(store.status, .unlicensed)
    XCTAssertNil(store.gracePeriodExpiresAt)
  }
}
