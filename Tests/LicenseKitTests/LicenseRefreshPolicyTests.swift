import XCTest

@testable import LicenseKit

final class LicenseRefreshPolicyTests: XCTestCase {
  func testInitializerAcceptsZeroAndPositiveIntervals() throws {
    let zeroPolicy = try LicenseRefreshPolicy(
      validationInterval: 0,
      failureGracePeriod: 0,
      serverFailureGracePeriod: 0
    )
    let positivePolicy = try LicenseRefreshPolicy(
      validationInterval: 1,
      failureGracePeriod: 1,
      serverFailureGracePeriod: 2
    )

    XCTAssertTrue(zeroPolicy.isEnabled)
    XCTAssertEqual(zeroPolicy.validationInterval, 0)
    XCTAssertEqual(zeroPolicy.failureGracePeriod, 0)
    XCTAssertEqual(zeroPolicy.serverFailureGracePeriod, 0)
    XCTAssertTrue(positivePolicy.isEnabled)
    XCTAssertEqual(positivePolicy.validationInterval, 1)
    XCTAssertEqual(positivePolicy.failureGracePeriod, 1)
    XCTAssertEqual(positivePolicy.serverFailureGracePeriod, 2)
  }

  func testDefaultPolicyEnablesRefreshWithConservativeIntervals() {
    XCTAssertTrue(LicenseRefreshPolicy.default.isEnabled)
    XCTAssertEqual(LicenseRefreshPolicy.default.validationInterval, 24 * 60 * 60)
    XCTAssertEqual(LicenseRefreshPolicy.default.failureGracePeriod, 7 * 24 * 60 * 60)
    XCTAssertEqual(LicenseRefreshPolicy.default.serverFailureGracePeriod, 24 * 60 * 60)
  }

  func testNeverPolicyDisablesProviderRefresh() {
    XCTAssertFalse(LicenseRefreshPolicy.never.isEnabled)
    XCTAssertEqual(LicenseRefreshPolicy.never.validationInterval, 0)
    XCTAssertEqual(LicenseRefreshPolicy.never.failureGracePeriod, 0)
    XCTAssertEqual(LicenseRefreshPolicy.never.serverFailureGracePeriod, 0)
  }

  func testErrorDescriptions() {
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidValidationInterval.description,
      "invalid_validation_interval"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidValidationInterval.errorDescription,
      "invalid_validation_interval"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidFailureGracePeriod.description,
      "invalid_failure_grace_period"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidFailureGracePeriod.errorDescription,
      "invalid_failure_grace_period"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidServerFailureGracePeriod.description,
      "invalid_server_failure_grace_period"
    )
    XCTAssertEqual(
      LicenseRefreshPolicyError.invalidServerFailureGracePeriod.errorDescription,
      "invalid_server_failure_grace_period"
    )
  }

  func testInitializerRejectsNegativeAndNonFiniteIntervals() {
    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: -1,
        failureGracePeriod: 1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidValidationInterval)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        failureGracePeriod: -1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        failureGracePeriod: 1,
        serverFailureGracePeriod: -1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidServerFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: .infinity,
        failureGracePeriod: 1,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidValidationInterval)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        failureGracePeriod: .nan,
        serverFailureGracePeriod: 1
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidFailureGracePeriod)
    }

    XCTAssertThrowsError(
      try LicenseRefreshPolicy(
        validationInterval: 1,
        failureGracePeriod: 1,
        serverFailureGracePeriod: .infinity
      )
    ) { error in
      XCTAssertEqual(error as? LicenseRefreshPolicyError, .invalidServerFailureGracePeriod)
    }
  }
}
