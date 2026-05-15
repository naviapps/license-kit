import XCTest

@testable import LicenseKit

final class LicenseValueTests: XCTestCase {
  func testPlanResolvesFromActivation() {
    let activation = makeActivation(planID: " team ", expiresAt: nil)

    let plan = LicensePlan.resolve(activation: activation)

    XCTAssertEqual(plan, LicensePlan(id: "team", isLicensed: true, expiresAt: nil))
  }

  func testPlanResolvesUnlicensedFromInvalidValidationSnapshot() {
    let validationSnapshot = LicenseValidationSnapshot(
      planID: "pro",
      isLicensed: false,
      expiresAt: nil
    )

    XCTAssertEqual(LicensePlan.resolve(validationSnapshot: validationSnapshot), .unlicensed)
  }

  func testValidationSnapshotDefaultsToActivationPlanAndNormalizesStrings() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(planID: "fallback")
    let snapshot = LicenseValidationSnapshot(
      result: LicenseValidationResult(
        isValid: true,
        planID: " \n "
      ),
      activation: activation,
      checkedAt: checkedAt
    )

    XCTAssertEqual(snapshot.planID, "fallback")
    XCTAssertTrue(snapshot.isLicensed)
    XCTAssertNil(snapshot.expiresAt)
    XCTAssertEqual(snapshot.checkedAt, checkedAt)
  }

  func testPlanExpiration() {
    XCTAssertEqual(LicensePlan(id: " pro ", isLicensed: true, expiresAt: nil).id, "pro")
    XCTAssertEqual(
      LicensePlan(
        id: "pro",
        isLicensed: false,
        expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      .unlicensed
    )
    XCTAssertFalse(LicensePlan(id: "pro", isLicensed: true, expiresAt: nil).isExpired)
    XCTAssertTrue(
      LicensePlan(
        id: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
      .isExpired(at: Date(timeIntervalSince1970: 1_700_000_000))
    )
    XCTAssertFalse(
      LicensePlan(
        id: "pro",
        isLicensed: true,
        expiresAt: Date().addingTimeInterval(60)
      ).isExpired
    )
    XCTAssertTrue(
      LicensePlan(
        id: "pro",
        isLicensed: true,
        expiresAt: Date().addingTimeInterval(-60)
      ).isExpired
    )
  }

  func testPlanDecodeNormalizesID() throws {
    let data = """
      {
        "id": " pro ",
        "isLicensed": true
      }
      """.data(using: .utf8)!

    let plan = try JSONDecoder().decode(LicensePlan.self, from: data)

    XCTAssertEqual(plan.id, "pro")
    XCTAssertTrue(plan.isLicensed)
  }

  func testPlanDecodeNormalizesUnlicensedPlan() throws {
    let data = """
      {
        "id": "pro",
        "isLicensed": false,
        "expiresAt": 1700000000
      }
      """.data(using: .utf8)!

    let plan = try JSONDecoder().decode(LicensePlan.self, from: data)

    XCTAssertEqual(plan, .unlicensed)
  }

  func testPlanDecodeRejectsBlankID() {
    let data = """
      {
        "id": " ",
        "isLicensed": false
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testActivationCodableRoundTrip() throws {
    let activation = makeActivation(source: "source-a")

    let data = try JSONEncoder().encode(activation)
    let decoded = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertEqual(decoded, activation)
    XCTAssertEqual(decoded.source, LicenseSource(rawValue: "source-a"))
  }

  func testSourceCodableUsesRawString() throws {
    let data = try JSONEncoder().encode(LicenseSource(rawValue: " source-a "))

    XCTAssertEqual(String(data: data, encoding: .utf8), #""source-a""#)
    XCTAssertEqual(
      try JSONDecoder().decode(LicenseSource.self, from: #"" \n ""#.data(using: .utf8)!),
      .default
    )
  }

  func testActivationDefaultsAndNormalizesOptionalStrings() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = LicenseActivation(
      licenseKey: " KEY ",
      planID: " pro ",
      activationID: " activation ",
      activatedAt: activatedAt
    )

    XCTAssertEqual(activation.source, .default)
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planID, "pro")
    XCTAssertEqual(activation.activationID, "activation")
    XCTAssertEqual(activation.activatedAt, activatedAt)
    XCTAssertNil(activation.expiresAt)
  }

  func testActivationDecodeNormalizesValues() throws {
    let data = """
      {
        "licenseKey": " KEY ",
        "planID": " pro ",
        "activationID": " activation ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    let activation = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertEqual(activation.source, .default)
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planID, "pro")
    XCTAssertEqual(activation.activationID, "activation")
    XCTAssertEqual(activation.activatedAt, Date(timeIntervalSinceReferenceDate: 1_700_000_000))
  }

  func testActivationDecodeRejectsInvalidValues() {
    let blankPlanID = """
      {
        "planID": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: blankPlanID))
  }

  func testActivationUsesCurrentDateWhenActivatedAtIsOmitted() {
    let before = Date()
    let activation = LicenseActivation(planID: "pro")
    let after = Date()

    XCTAssertGreaterThanOrEqual(activation.activatedAt, before)
    XCTAssertLessThanOrEqual(activation.activatedAt, after)
  }

  func testActivationExpiration() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    XCTAssertFalse(makeActivation(expiresAt: nil).isExpired(at: now))
    XCTAssertFalse(makeActivation(expiresAt: now.addingTimeInterval(1)).isExpired(at: now))
    XCTAssertTrue(makeActivation(expiresAt: now).isExpired(at: now))
    XCTAssertTrue(makeActivation(expiresAt: now.addingTimeInterval(-1)).isExpired(at: now))
  }

  func testValidationResultDefaultsAndNormalizesPlanID() {
    let expiration = Date(timeIntervalSince1970: 1_700_000_000)
    let validResult = LicenseValidationResult(
      isValid: true,
      planID: " team ",
      expiresAt: expiration
    )
    let invalidResult = LicenseValidationResult(
      isValid: false,
      planID: "team",
      expiresAt: expiration
    )

    XCTAssertTrue(validResult.isValid)
    XCTAssertEqual(validResult.planID, "team")
    XCTAssertEqual(validResult.expiresAt, expiration)
    XCTAssertFalse(invalidResult.isValid)
    XCTAssertNil(invalidResult.planID)
    XCTAssertEqual(invalidResult.expiresAt, expiration)
  }

  func testValidationResultDecodeNormalizesValues() throws {
    let data = """
      {
        "isValid": true,
        "planID": " team "
      }
      """.data(using: .utf8)!

    let result = try JSONDecoder().decode(LicenseValidationResult.self, from: data)

    XCTAssertTrue(result.isValid)
    XCTAssertEqual(result.planID, "team")

    let invalidData = """
      {
        "isValid": false,
        "planID": " team "
      }
      """.data(using: .utf8)!

    let invalidResult = try JSONDecoder().decode(LicenseValidationResult.self, from: invalidData)

    XCTAssertFalse(invalidResult.isValid)
    XCTAssertNil(invalidResult.planID)
  }

  func testSourceNormalizesBlankValuesToDefault() {
    XCTAssertEqual(LicenseSource(rawValue: " source-a ").rawValue, "source-a")
    XCTAssertEqual(LicenseSource(rawValue: " \n ").rawValue, "default")
    XCTAssertEqual(LicenseSource(stringLiteral: "").rawValue, "default")
  }

  func testStateSnapshotActivationIdentityNormalizesAndMatchesActivation() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = LicenseStateSnapshot.ActivationIdentity(
      source: "external",
      planID: " pro ",
      activationID: " activation ",
      activatedAt: activatedAt
    )
    let blankActivationID = LicenseStateSnapshot.ActivationIdentity(
      source: "external",
      planID: "pro",
      activationID: " \n ",
      activatedAt: activatedAt
    )
    let matchingActivation = LicenseActivation(
      source: "external",
      licenseKey: "KEY",
      planID: "pro",
      activationID: "activation",
      activatedAt: activatedAt,
      expiresAt: activatedAt.addingTimeInterval(60)
    )

    XCTAssertEqual(identity.source, "external")
    XCTAssertEqual(identity.planID, "pro")
    XCTAssertEqual(identity.activationID, "activation")
    XCTAssertEqual(identity.activatedAt, activatedAt)
    XCTAssertNil(blankActivationID.activationID)
    XCTAssertTrue(identity.matches(activation: matchingActivation))
    XCTAssertTrue(
      blankActivationID.matches(
        activation: LicenseActivation(
          source: "external",
          planID: "pro",
          activatedAt: activatedAt
        )
      )
    )
    XCTAssertFalse(
      identity.matches(
        activation: LicenseActivation(
          source: "other",
          planID: "pro",
          activationID: "activation",
          activatedAt: activatedAt
        )
      )
    )
  }

  func testStateSnapshotActivationIdentityDecodeNormalizesAndRejectsInvalidPlanID() throws {
    let data = """
      {
        "source": " external ",
        "planID": " pro ",
        "activationID": " activation ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!
    let blankPlanID = """
      {
        "source": "external",
        "planID": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    let identity = try JSONDecoder().decode(
      LicenseStateSnapshot.ActivationIdentity.self,
      from: data
    )

    XCTAssertEqual(identity.source, "external")
    XCTAssertEqual(identity.planID, "pro")
    XCTAssertEqual(identity.activationID, "activation")
    XCTAssertEqual(identity.activatedAt, Date(timeIntervalSinceReferenceDate: 1_700_000_000))
    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseStateSnapshot.ActivationIdentity.self, from: blankPlanID)
    )
  }

  func testStateSnapshotRejectsImpossibleRestorableState() {
    let identity = LicenseStateSnapshot.ActivationIdentity(
      source: .default,
      planID: "pro",
      activationID: "activation",
      activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let failure = LicenseRefreshFailure(
      reason: .requestFailure,
      message: "unavailable",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    XCTAssertNil(
      LicenseStateSnapshot(
        activationIdentity: identity,
        plan: .unlicensed,
        lastValidatedAt: nil,
        status: .invalid,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_200),
        lastRefreshFailure: failure
      ))
    XCTAssertNil(
      LicenseStateSnapshot(
        activationIdentity: identity,
        plan: LicensePlan(id: "team", isLicensed: true, expiresAt: nil),
        lastValidatedAt: nil,
        status: .gracePeriod,
        gracePeriodExpiresAt: nil,
        lastRefreshFailure: failure
      ))
    XCTAssertNil(
      LicenseStateSnapshot(
        activationIdentity: identity,
        plan: LicensePlan(id: "team", isLicensed: true, expiresAt: nil),
        lastValidatedAt: nil,
        status: .active,
        gracePeriodExpiresAt: nil
      ))
    let expiredPlanSnapshot = LicenseStateSnapshot(
      activationIdentity: identity,
      plan: LicensePlan(
        id: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1)
      ),
      lastValidatedAt: nil,
      status: .active,
      gracePeriodExpiresAt: nil
    )
    let activeSnapshot = LicenseStateSnapshot(
      activationIdentity: identity,
      plan: .unlicensed,
      lastValidatedAt: nil,
      status: .active,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_200),
      lastRefreshFailure: failure
    )

    XCTAssertEqual(expiredPlanSnapshot?.status, .active)
    XCTAssertEqual(expiredPlanSnapshot?.plan.expiresAt, Date(timeIntervalSince1970: 1))
    XCTAssertEqual(
      expiredPlanSnapshot?.restoreState(activation: makeActivation(planID: "pro")).status,
      .expired
    )
    XCTAssertEqual(activeSnapshot?.status, .active)
    XCTAssertEqual(activeSnapshot?.plan, LicensePlan(id: "pro", isLicensed: true, expiresAt: nil))
    XCTAssertNil(activeSnapshot?.gracePeriodExpiresAt)
    XCTAssertNil(activeSnapshot?.lastRefreshFailure)
  }

  func testStateSnapshotDecodeRejectsImpossibleRestorableState() {
    let data = """
      {
        "activationIdentity": {
          "source": "default",
          "planID": "pro",
          "activationID": "activation",
          "activatedAt": 1700000000
        },
        "plan": {
          "id": "unlicensed",
          "isLicensed": false
        },
        "status": "invalid",
        "gracePeriodExpiresAt": 1700000200,
        "lastRefreshFailure": {
          "reason": "requestFailure",
          "message": "unavailable",
          "occurredAt": 1700000100
        }
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseStateSnapshot.self, from: data))
  }

  func testStateSnapshotDecodePreservesExpiredPlanForRestoreNormalization() throws {
    let data = """
      {
        "activationIdentity": {
          "source": "default",
          "planID": "pro",
          "activationID": "activation",
          "activatedAt": 1700000000
        },
        "plan": {
          "id": "pro",
          "isLicensed": true,
          "expiresAt": 1
        },
        "status": "active"
      }
      """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(LicenseStateSnapshot.self, from: data)

    XCTAssertEqual(snapshot.plan.expiresAt, Date(timeIntervalSinceReferenceDate: 1))
    XCTAssertEqual(
      snapshot.restoreState(activation: makeActivation(planID: "pro")).status,
      .expired
    )
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

  func testErrorDescriptions() {
    let cases: [(LicenseError, String)] = [
      (.invalidLicenseKey, "invalid_license_key"),
      (.invalidLicense, "invalid_license"),
      (.expiredLicense, "expired_license"),
      (.activationLimitReached, "activation_limit_reached"),
      (
        .invalidProviderConfiguration,
        "invalid_provider_configuration"
      ),
      (.activationInProgress, "activation_in_progress"),
      (.refreshInProgress, "refresh_in_progress"),
      (.unexpectedProviderResponse, "unexpected_provider_response"),
    ]

    for (error, description) in cases {
      XCTAssertEqual(error.description, description)
      XCTAssertEqual(error.errorDescription, description)
      XCTAssertNil(error.message)
      XCTAssertNil(error.statusCode)
    }

    XCTAssertEqual(
      LicenseError.serverFailure(statusCode: 404).description,
      "server_failure(404)"
    )
    XCTAssertEqual(
      LicenseError.serverFailure(statusCode: 404).errorDescription,
      "server_failure(404)"
    )
    XCTAssertEqual(LicenseError.serverFailure(statusCode: 404).statusCode, 404)
    XCTAssertEqual(
      LicenseError.requestFailure(message: "timeout").description,
      "request_failure(timeout)"
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: "timeout").errorDescription,
      "request_failure(timeout)"
    )
    XCTAssertEqual(LicenseError.requestFailure(message: "timeout").message, "timeout")
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t ").description,
      "request_failure(Request failed.)"
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t ").message,
      "Request failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").description,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").errorDescription,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").message,
      "Storage operation failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "decode failed").description,
      "storage_failure(decode failed)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "decode failed").errorDescription,
      "storage_failure(decode failed)"
    )
    XCTAssertEqual(LicenseError.storageFailure(message: "decode failed").message, "decode failed")
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t ").description,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t ").message,
      "Storage operation failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(TestUnexpectedError(message: " \n ")),
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t "),
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t "),
      .requestFailure(message: "Request failed.")
    )
    XCTAssertNotEqual(
      LicenseError.storageFailure(message: "Storage operation failed."),
      .requestFailure(message: "Storage operation failed.")
    )
  }

  func testRefreshFailureMapsProviderErrors() {
    let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
    let cases: [(LicenseProviderError, LicenseRefreshFailure)] = [
      (
        .invalidLicense,
        LicenseRefreshFailure(reason: .invalidLicense, occurredAt: occurredAt)
      ),
      (
        .activationLimitReached,
        LicenseRefreshFailure(reason: .activationLimitReached, occurredAt: occurredAt)
      ),
      (
        .invalidConfiguration,
        LicenseRefreshFailure(reason: .invalidProviderConfiguration, occurredAt: occurredAt)
      ),
      (
        .responseDecodingFailure,
        LicenseRefreshFailure(reason: .unexpectedProviderResponse, occurredAt: occurredAt)
      ),
      (
        .transportFailure(message: "offline"),
        LicenseRefreshFailure(reason: .transportFailure, message: "offline", occurredAt: occurredAt)
      ),
      (
        .serverFailure(statusCode: 503),
        LicenseRefreshFailure(
          reason: .serverFailure,
          statusCode: 503,
          occurredAt: occurredAt
        )
      ),
      (
        .requestFailure(message: "bad request"),
        LicenseRefreshFailure(
          reason: .requestFailure,
          message: "bad request",
          occurredAt: occurredAt
        )
      ),
    ]

    for (error, expectedFailure) in cases {
      XCTAssertEqual(LicenseRefreshFailure(error: error, occurredAt: occurredAt), expectedFailure)
    }
  }

  func testProviderErrorDescriptions() {
    let cases: [(LicenseProviderError, String)] = [
      (.invalidConfiguration, "invalid_configuration"),
      (.transportFailure(message: "offline"), "transport_failure(offline)"),
      (.transportFailure(message: " \n\t "), "transport_failure(Transport failed.)"),
      (.responseDecodingFailure, "response_decoding_failure"),
      (.invalidLicense, "invalid_license"),
      (.activationLimitReached, "activation_limit_reached"),
      (.requestFailure(message: "bad request"), "request_failure(bad request)"),
      (.requestFailure(message: " \n\t "), "request_failure(Request failed.)"),
      (.serverFailure(statusCode: 503), "server_failure(503)"),
    ]

    for (error, description) in cases {
      XCTAssertEqual(error.description, description)
      XCTAssertEqual(error.errorDescription, description)
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
      validationFailure: failure
    )
    let graceResult = LicenseRefreshResult(
      outcome: .gracePeriod,
      state: state,
      validationFailure: failure
    )
    let invalidResult = LicenseRefreshResult(
      outcome: .invalid,
      state: state,
      validationFailure: failure
    )

    XCTAssertEqual(result.outcome, .skippedNoActivation)
    XCTAssertEqual(result.state, state)
    XCTAssertNil(result.validationFailure)
    XCTAssertNil(refreshedResult.validationFailure)
    XCTAssertEqual(graceResult.validationFailure, failure)
    XCTAssertEqual(invalidResult.validationFailure, failure)
  }

  func testStateDefaultsAndConveniences() {
    let state = LicenseState()
    XCTAssertEqual(state.plan, .unlicensed)
    XCTAssertNil(state.activation)
    XCTAssertNil(state.source)
    XCTAssertFalse(state.isActivating)
    XCTAssertFalse(state.isRefreshing)
    XCTAssertNil(state.lastValidatedAt)
    XCTAssertEqual(state.status, .unlicensed)
    XCTAssertFalse(state.isLicensed)
    XCTAssertNil(state.gracePeriodExpiresAt)
    XCTAssertNil(state.lastRefreshFailure)

    let activation = LicenseActivation(source: "store", planID: "pro")
    let licensedState = LicenseState(
      plan: LicensePlan.resolve(activation: activation),
      activation: activation,
      status: .active
    )
    XCTAssertEqual(licensedState.source, "store")
    XCTAssertTrue(licensedState.isLicensed)
  }

  func testStateInitializersNormalizeImpossibleCombinations() {
    let activation = LicenseActivation(source: "store", planID: "pro")
    let failure = LicenseRefreshFailure(
      reason: .transportFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let activationlessActive = LicenseState(
      plan: LicensePlan(id: "pro", isLicensed: true, expiresAt: nil),
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
      plan: LicensePlan(id: "pro", isLicensed: true, expiresAt: nil),
      activation: activation,
      status: .expired,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_100),
      lastRefreshFailure: failure
    )
    let expiredActivation = makeActivation(expiresAt: Date(timeIntervalSince1970: 1))
    let expiredActivationState = LicenseState(
      plan: LicensePlan.resolve(activation: expiredActivation),
      activation: expiredActivation,
      status: .active
    )
    let expiredPlanState = LicenseState(
      plan: LicensePlan(
        id: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1)
      ),
      activation: activation,
      status: .active
    )
    let concurrentOperationState = LicenseState(
      plan: LicensePlan.resolve(activation: activation),
      activation: activation,
      isActivating: true,
      isRefreshing: true,
      status: .active
    )
    let activationlessRefreshing = LicenseState(
      isRefreshing: true,
      status: .unlicensed
    )

    XCTAssertEqual(activationlessActive.status, .unlicensed)
    XCTAssertEqual(activationlessActive.plan, .unlicensed)
    XCTAssertNil(activationlessActive.activation)
    XCTAssertNil(activationlessActive.gracePeriodExpiresAt)
    XCTAssertNil(activationlessActive.lastRefreshFailure)

    XCTAssertEqual(graceWithoutExpiration.status, .active)
    XCTAssertEqual(graceWithoutExpiration.plan, LicensePlan.resolve(activation: activation))
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

    XCTAssertFalse(activationlessRefreshing.isActivating)
    XCTAssertFalse(activationlessRefreshing.isRefreshing)
  }
}
