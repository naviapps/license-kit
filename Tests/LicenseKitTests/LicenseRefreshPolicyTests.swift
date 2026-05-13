import XCTest

@testable import LicenseKit

final class LicenseRefreshPolicyTests: XCTestCase {
  func testAcceptsNonNegativeIntervals() throws {
    let policy = try LicenseRefreshPolicy(
      validationInterval: 0,
      recoverableFailureGracePeriod: 1,
      serverFailureGracePeriod: 2
    )

    XCTAssertTrue(policy.isEnabled)
    XCTAssertEqual(policy.validationInterval, 0)
    XCTAssertEqual(policy.recoverableFailureGracePeriod, 1)
    XCTAssertEqual(policy.serverFailureGracePeriod, 2)
  }

  func testDefaultPolicyEnablesRefreshWithConservativeIntervals() {
    XCTAssertTrue(LicenseRefreshPolicy.default.isEnabled)
    XCTAssertEqual(LicenseRefreshPolicy.default.validationInterval, 24 * 60 * 60)
    XCTAssertEqual(LicenseRefreshPolicy.default.recoverableFailureGracePeriod, 7 * 24 * 60 * 60)
    XCTAssertEqual(LicenseRefreshPolicy.default.serverFailureGracePeriod, 24 * 60 * 60)
  }

  func testNeverDisablesRefresh() {
    XCTAssertFalse(LicenseRefreshPolicy.never.isEnabled)
    XCTAssertEqual(LicenseRefreshPolicy.never.validationInterval, 0)
    XCTAssertEqual(LicenseRefreshPolicy.never.recoverableFailureGracePeriod, 0)
    XCTAssertEqual(LicenseRefreshPolicy.never.serverFailureGracePeriod, 0)
  }

  func testErrorDescriptions() {
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidValidationInterval.description,
      "invalid_validation_interval"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidRecoverableFailureGracePeriod.description,
      "invalid_recoverable_failure_grace_period"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidServerFailureGracePeriod.description,
      "invalid_server_failure_grace_period"
    )
  }

  func testRejectsInvalidIntervals() {
    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: -1,
        recoverableFailureGracePeriod: 1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidValidationInterval)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        recoverableFailureGracePeriod: -1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidRecoverableFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        recoverableFailureGracePeriod: 1,
        serverFailureGracePeriod: -1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidServerFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: .infinity,
        recoverableFailureGracePeriod: 1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidValidationInterval)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        recoverableFailureGracePeriod: .nan,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidRecoverableFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        recoverableFailureGracePeriod: 1,
        serverFailureGracePeriod: .infinity
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidServerFailureGracePeriod)
    }
  }
}
