import XCTest

import LicenseKit

final class LicenseRefreshValueTests: XCTestCase {
  func testRefreshRawEnumsCodableRoundTrip() throws {
    XCTAssertEqual(
      LicenseRefreshFailureReason.allCases.map(\.rawValue),
      [
        "invalidLicense",
        "activationLimitReached",
        "invalidProviderConfiguration",
        "unexpectedProviderResponse",
        "transportFailure",
        "serverFailure",
        "requestFailure",
        "gracePeriodExpired",
      ]
    )

    for reason in LicenseRefreshFailureReason.allCases {
      let data = try JSONEncoder().encode(reason)
      XCTAssertEqual(try JSONDecoder().decode(LicenseRefreshFailureReason.self, from: data), reason)
    }

    XCTAssertEqual(
      LicenseRefreshOutcome.allCases.map(\.rawValue),
      [
        "refreshed",
        "gracePeriod",
        "invalid",
        "expired",
        "skippedActivationInProgress",
        "skippedRefreshDisabled",
        "skippedRefreshInProgress",
        "skippedDeactivationInProgress",
        "skippedNoActivation",
      ]
    )

    for outcome in LicenseRefreshOutcome.allCases {
      let data = try JSONEncoder().encode(outcome)
      XCTAssertEqual(try JSONDecoder().decode(LicenseRefreshOutcome.self, from: data), outcome)
    }
  }

  func testRefreshFailureNormalizesBlankMessage() throws {
    let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: " \n\t ",
      occurredAt: occurredAt
    )

    XCTAssertNil(failure.message)

    let data = try JSONEncoder().encode(failure)
    let decoded = try JSONDecoder().decode(LicenseRefreshFailure.self, from: data)
    XCTAssertNil(decoded.message)

    let encodedBlankMessage = """
      {
        "reason": "transportFailure",
        "message": " \\n\\t ",
        "occurredAt": 1700000000
      }
      """.data(using: .utf8)!
    let decodedBlankMessage = try JSONDecoder().decode(
      LicenseRefreshFailure.self,
      from: encodedBlankMessage
    )
    XCTAssertNil(decodedBlankMessage.message)
  }

  func testRefreshFailureKeepsStatusCodeOnlyForServerFailure() throws {
    let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)

    let transportFailure = LicenseRefreshFailure(
      reason: .transportFailure,
      statusCode: 503,
      occurredAt: occurredAt
    )
    let serverFailure = LicenseRefreshFailure(
      reason: .serverFailure,
      statusCode: 503,
      occurredAt: occurredAt
    )
    let decodedTransportFailure = try JSONDecoder().decode(
      LicenseRefreshFailure.self,
      from: """
        {
          "reason": "transportFailure",
          "statusCode": 503,
          "occurredAt": 1700000000
        }
        """.data(using: .utf8)!
    )

    XCTAssertNil(transportFailure.statusCode)
    XCTAssertEqual(serverFailure.statusCode, 503)
    XCTAssertNil(decodedTransportFailure.statusCode)
  }

  func testRefreshResultDefaultsFailures() {
    let state = LicenseState(status: .unlicensed)
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let result = LicenseRefreshResult(
      outcome: .skippedNoActivation,
      state: state
    )
    let refreshedResult = LicenseRefreshResult(
      outcome: .refreshed,
      state: state,
      failure: failure
    )
    let graceResult = LicenseRefreshResult(
      outcome: .gracePeriod,
      state: state,
      failure: failure
    )
    let invalidResult = LicenseRefreshResult(
      outcome: .invalid,
      state: state,
      failure: failure
    )

    XCTAssertEqual(result.outcome, .skippedNoActivation)
    XCTAssertEqual(result.state, state)
    XCTAssertNil(result.failure)
    XCTAssertNil(refreshedResult.failure)
    XCTAssertEqual(graceResult.failure, failure)
    XCTAssertEqual(invalidResult.failure, failure)
  }

}
