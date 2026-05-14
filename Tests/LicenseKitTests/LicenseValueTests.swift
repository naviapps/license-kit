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
      expiresAt: nil,
      remainingActivations: nil,
      customerID: nil
    )

    XCTAssertEqual(LicensePlan.resolve(validationSnapshot: validationSnapshot), .unlicensed)
  }

  func testValidationSnapshotDefaultsToActivationPlanAndNormalizesStrings() {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = makeActivation(planID: "fallback")
    let snapshot = LicenseValidationSnapshot(
      result: LicenseValidationResult(
        isValid: true,
        planID: " \n ",
        customerID: " cus_123 "
      ),
      activation: activation,
      checkedAt: checkedAt
    )

    XCTAssertEqual(snapshot.planID, "fallback")
    XCTAssertTrue(snapshot.isLicensed)
    XCTAssertNil(snapshot.expiresAt)
    XCTAssertNil(snapshot.remainingActivations)
    XCTAssertEqual(snapshot.customerID, "cus_123")
    XCTAssertEqual(snapshot.checkedAt, checkedAt)
  }

  func testPlanExpiration() {
    XCTAssertEqual(LicensePlan(id: " pro ", isLicensed: true, expiresAt: nil).id, "pro")
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
      customerID: " customer ",
      deviceName: " \n ",
      activationID: " activation ",
      activatedAt: activatedAt
    )

    XCTAssertEqual(activation.source, .default)
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planID, "pro")
    XCTAssertEqual(activation.customerID, "customer")
    XCTAssertNil(activation.deviceName)
    XCTAssertEqual(activation.activationID, "activation")
    XCTAssertEqual(activation.activatedAt, activatedAt)
    XCTAssertNil(activation.expiresAt)
    XCTAssertNil(activation.remainingActivations)
  }

  func testActivationDecodeNormalizesValues() throws {
    let data = """
      {
        "licenseKey": " KEY ",
        "planID": " pro ",
        "customerID": " customer ",
        "deviceName": " \\n ",
        "activationID": " activation ",
        "activatedAt": 1700000000,
        "remainingActivations": 0
      }
      """.data(using: .utf8)!

    let activation = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertEqual(activation.source, .default)
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planID, "pro")
    XCTAssertEqual(activation.customerID, "customer")
    XCTAssertNil(activation.deviceName)
    XCTAssertEqual(activation.activationID, "activation")
    XCTAssertEqual(activation.activatedAt, Date(timeIntervalSinceReferenceDate: 1_700_000_000))
    XCTAssertEqual(activation.remainingActivations, 0)
  }

  func testActivationDecodeRejectsInvalidValues() {
    let blankPlanID = """
      {
        "planID": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!
    let negativeRemainingActivations = """
      {
        "planID": "pro",
        "activatedAt": 1700000000,
        "remainingActivations": -1
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: blankPlanID))
    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseActivation.self, from: negativeRemainingActivations)
    )
  }

  func testActivationPreservesNonNegativeRemainingActivations() {
    let activation = LicenseActivation(planID: "pro", remainingActivations: 0)

    XCTAssertEqual(activation.remainingActivations, 0)
  }

  func testActivationUsesCurrentDateWhenActivatedAtIsOmitted() {
    let before = Date()
    let activation = LicenseActivation(planID: "pro")
    let after = Date()

    XCTAssertGreaterThanOrEqual(activation.activatedAt, before)
    XCTAssertLessThanOrEqual(activation.activatedAt, after)
    XCTAssertNil(activation.deviceName)
  }

  func testValidationResultDefaultsAndNormalizesCustomerID() {
    let validResult = LicenseValidationResult(
      isValid: true,
      planID: " team ",
      remainingActivations: 0,
      customerID: " customer "
    )
    let invalidResult = LicenseValidationResult(isValid: false, customerID: " \n ")

    XCTAssertTrue(validResult.isValid)
    XCTAssertEqual(validResult.planID, "team")
    XCTAssertNil(validResult.expiresAt)
    XCTAssertEqual(validResult.remainingActivations, 0)
    XCTAssertEqual(validResult.customerID, "customer")
    XCTAssertFalse(invalidResult.isValid)
    XCTAssertNil(invalidResult.planID)
    XCTAssertNil(invalidResult.customerID)
  }

  func testValidationResultDecodeNormalizesValues() throws {
    let data = """
      {
        "isValid": true,
        "planID": " team ",
        "remainingActivations": 0,
        "customerID": " customer "
      }
      """.data(using: .utf8)!

    let result = try JSONDecoder().decode(LicenseValidationResult.self, from: data)

    XCTAssertTrue(result.isValid)
    XCTAssertEqual(result.planID, "team")
    XCTAssertEqual(result.remainingActivations, 0)
    XCTAssertEqual(result.customerID, "customer")
  }

  func testValidationResultDecodeRejectsNegativeRemainingActivations() {
    let data = """
      {
        "isValid": true,
        "remainingActivations": -1
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseValidationResult.self, from: data))
  }

  func testSourceNormalizesBlankValuesToDefault() {
    XCTAssertEqual(LicenseSource(rawValue: " source-a ").rawValue, "source-a")
    XCTAssertEqual(LicenseSource(rawValue: " \n ").rawValue, "default")
    XCTAssertEqual(LicenseSource(stringLiteral: "").rawValue, "default")
  }

  func testOfferingCodableRoundTrip() throws {
    let offering = LicenseOffering(
      id: " pro ",
      name: " Pro ",
      kind: .recurring,
      billingPeriod: .year,
      priceInMinorUnits: 9900,
      currencyCode: " usd ",
      formattedPrice: nil
    )

    let data = try JSONEncoder().encode(offering)
    let decoded = try JSONDecoder().decode(LicenseOffering.self, from: data)

    XCTAssertEqual(decoded, offering)
    XCTAssertEqual(decoded.id, "pro")
    XCTAssertEqual(decoded.name, "Pro")
    XCTAssertEqual(decoded.currencyCode, "USD")
  }

  func testOfferingDecodeNormalizesValues() throws {
    let data = """
      {
        "id": " pro ",
        "name": " Pro ",
        "kind": "recurring",
        "billingPeriod": {
          "unit": " month ",
          "count": 3
        },
        "priceInMinorUnits": 9900,
        "currencyCode": " usd ",
        "description": " Pro license ",
        "formattedPrice": " "
      }
      """.data(using: .utf8)!

    let offering = try JSONDecoder().decode(LicenseOffering.self, from: data)

    XCTAssertEqual(offering.id, "pro")
    XCTAssertEqual(offering.name, "Pro")
    XCTAssertEqual(offering.kind, .recurring)
    XCTAssertEqual(offering.billingPeriod, LicenseBillingPeriod(unit: .month, count: 3))
    XCTAssertEqual(offering.priceInMinorUnits, 9900)
    XCTAssertEqual(offering.currencyCode, "USD")
    XCTAssertEqual(offering.description, "Pro license")
    XCTAssertNil(offering.formattedPrice)
  }

  func testOfferingDecodeMapsUnknownKind() throws {
    let data = """
      {
        "id": "pro",
        "name": "Pro",
        "kind": "provider_specific"
      }
      """.data(using: .utf8)!

    let offering = try JSONDecoder().decode(LicenseOffering.self, from: data)

    XCTAssertEqual(offering.kind, .unknown)
  }

  func testOfferingKindDecodeTrimsWhitespace() throws {
    let data = #"" recurring ""#.data(using: .utf8)!

    let kind = try JSONDecoder().decode(LicenseOfferingKind.self, from: data)

    XCTAssertEqual(kind, .recurring)
  }

  func testBillingPeriodDefaultsAndDecoding() throws {
    XCTAssertEqual(LicenseBillingPeriod.day, LicenseBillingPeriod(unit: .day))
    XCTAssertEqual(LicenseBillingPeriod.week, LicenseBillingPeriod(unit: .week))
    XCTAssertEqual(LicenseBillingPeriod.month, LicenseBillingPeriod(unit: .month))
    XCTAssertEqual(LicenseBillingPeriod.year, LicenseBillingPeriod(unit: .year))

    let countedPeriod = """
      {
        "unit": " year ",
        "count": 2
      }
      """.data(using: .utf8)!
    let uncountedPeriod = """
      {
        "unit": "month"
      }
      """.data(using: .utf8)!

    let period = try JSONDecoder().decode(LicenseBillingPeriod.self, from: countedPeriod)
    let defaultedPeriod = try JSONDecoder().decode(
      LicenseBillingPeriod.self,
      from: uncountedPeriod
    )

    XCTAssertEqual(period, LicenseBillingPeriod(unit: .year, count: 2))
    XCTAssertEqual(defaultedPeriod, .month)
  }

  func testBillingPeriodDecodeRejectsInvalidValues() {
    let invalidUnit = """
      {
        "unit": "quarter",
        "count": 1
      }
      """.data(using: .utf8)!
    let invalidCount = """
      {
        "unit": "month",
        "count": 0
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseBillingPeriod.self, from: invalidUnit))
    XCTAssertThrowsError(try JSONDecoder().decode(LicenseBillingPeriod.self, from: invalidCount))
  }

  func testOfferingDecodeRejectsNegativePrice() {
    let data = """
      {
        "id": "pro",
        "name": "Pro",
        "priceInMinorUnits": -1
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseOffering.self, from: data))
  }

  func testOfferingDecodeRejectsInvalidCurrencyCode() {
    let data = """
      {
        "id": "pro",
        "name": "Pro",
        "currencyCode": "US"
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseOffering.self, from: data))
  }

  func testOfferingDecodeRejectsPositivePriceWithoutCurrencyCode() {
    let data = """
      {
        "id": "pro",
        "name": "Pro",
        "priceInMinorUnits": 9900
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseOffering.self, from: data))
  }

  func testOfferingNormalizesBlankCurrencyCodeToNil() {
    let offering = LicenseOffering(id: "free", name: "Free", currencyCode: " ")

    XCTAssertNil(offering.currencyCode)
  }

  func testOfferingNormalizesOptionalDisplayStrings() {
    let offering = LicenseOffering(
      id: "pro",
      name: "Pro",
      description: " Pro license ",
      formattedPrice: " "
    )

    XCTAssertEqual(offering.description, "Pro license")
    XCTAssertNil(offering.formattedPrice)
  }

  func testOfferingAcceptsZeroPrice() {
    let offering = LicenseOffering(id: "free", name: "Free", priceInMinorUnits: 0)

    XCTAssertEqual(offering.priceInMinorUnits, 0)
  }

  func testOfferingNormalizesEmptyMetadataToNil() {
    let offering = LicenseOffering(id: "pro", name: "Pro", metadata: [:])

    XCTAssertNil(offering.metadata)
  }

  func testStateSnapshotActivationIdentityNormalizesPlanID() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = LicenseStateSnapshot.ActivationIdentity(
      source: "external",
      planID: " pro ",
      activationID: "activation",
      activatedAt: activatedAt
    )

    XCTAssertEqual(identity.source, "external")
    XCTAssertEqual(identity.planID, "pro")
    XCTAssertEqual(identity.activationID, "activation")
    XCTAssertEqual(identity.activatedAt, activatedAt)
  }

  func testStateSnapshotActivationIdentityDecodeNormalizesAndRejectsInvalidPlanID() throws {
    let data = """
      {
        "source": " external ",
        "planID": " pro ",
        "activationID": "activation",
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

  func testStatusLicensedConvenience() {
    XCTAssertEqual(
      LicenseStatus.allCases,
      [.unlicensed, .activating, .active, .gracePeriod, .expired, .invalid, .deactivated]
    )
    XCTAssertTrue(LicenseStatus.active.isLicensed)
    XCTAssertTrue(LicenseStatus.gracePeriod.isLicensed)
    XCTAssertFalse(LicenseStatus.unlicensed.isLicensed)
    XCTAssertFalse(LicenseStatus.activating.isLicensed)
    XCTAssertFalse(LicenseStatus.expired.isLicensed)
    XCTAssertFalse(LicenseStatus.invalid.isLicensed)
    XCTAssertFalse(LicenseStatus.deactivated.isLicensed)
  }

  func testErrorDescriptions() {
    let cases: [(LicenseError, LicenseErrorCode, String)] = [
      (.invalidLicenseKey, .invalidLicenseKey, "invalid_license_key"),
      (.storageFailure, .storageFailure, "storage_failure"),
      (.invalidLicense, .invalidLicense, "invalid_license"),
      (.activationLimitReached, .activationLimitReached, "activation_limit_reached"),
      (.invalidProviderURL, .invalidProviderURL, "invalid_provider_url"),
      (.activationInProgress, .activationInProgress, "activation_in_progress"),
      (.refreshInProgress, .refreshInProgress, "refresh_in_progress"),
      (.unexpectedProviderResponse, .unexpectedProviderResponse, "unexpected_provider_response"),
    ]

    for (error, code, description) in cases {
      XCTAssertEqual(error.code, code)
      XCTAssertEqual(error.description, description)
      XCTAssertEqual(error.errorDescription, description)
      XCTAssertNil(error.message)
      XCTAssertNil(error.statusCode)
    }

    XCTAssertEqual(
      LicenseError.providerServerFailure(statusCode: 404).description,
      "provider_server_failure(404)"
    )
    XCTAssertEqual(
      LicenseError.providerServerFailure(statusCode: 404).errorDescription,
      "provider_server_failure(404)"
    )
    XCTAssertEqual(LicenseError.providerServerFailure(statusCode: 404).statusCode, 404)
    XCTAssertEqual(
      LicenseError.providerRequestFailure(message: "timeout").description,
      "provider_request_failure(timeout)"
    )
    XCTAssertEqual(
      LicenseError.providerRequestFailure(message: "timeout").errorDescription,
      "provider_request_failure(timeout)"
    )
    XCTAssertEqual(LicenseError.providerRequestFailure(message: "timeout").message, "timeout")
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
        .invalidProviderURL,
        LicenseRefreshFailure(reason: .invalidProviderURL, occurredAt: occurredAt)
      ),
      (
        .responseDecodingFailure,
        LicenseRefreshFailure(reason: .unexpectedProviderResponse, occurredAt: occurredAt)
      ),
      (
        .networkFailure(message: "offline"),
        LicenseRefreshFailure(reason: .networkFailure, message: "offline", occurredAt: occurredAt)
      ),
      (
        .serverFailure(statusCode: 503),
        LicenseRefreshFailure(
          reason: .providerServerFailure,
          statusCode: 503,
          occurredAt: occurredAt
        )
      ),
      (
        .requestFailure(message: "bad request"),
        LicenseRefreshFailure(
          reason: .providerRequestFailure,
          message: "bad request",
          occurredAt: occurredAt
        )
      ),
    ]

    for (error, expectedFailure) in cases {
      XCTAssertEqual(LicenseRefreshFailure(error: error, occurredAt: occurredAt), expectedFailure)
    }
  }

  func testRefreshFailureNormalizesBlankMessage() throws {
    let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
    let failure = LicenseRefreshFailure(
      reason: .networkFailure,
      message: " \n\t ",
      occurredAt: occurredAt
    )

    XCTAssertNil(failure.message)

    let data = try JSONEncoder().encode(failure)
    let decoded = try JSONDecoder().decode(LicenseRefreshFailure.self, from: data)
    XCTAssertNil(decoded.message)

    let encodedBlankMessage = """
      {
        "reason": "networkFailure",
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

  func testRefreshResultDefaultsFailures() {
    let state = LicenseState(status: .unlicensed)
    let result = LicenseRefreshResult(
      outcome: .skippedNoActivation,
      state: state
    )

    XCTAssertEqual(result.outcome, .skippedNoActivation)
    XCTAssertEqual(result.state, state)
    XCTAssertNil(result.validationFailure)
    XCTAssertNil(result.offeringLoadFailure)
  }

  func testStateDefaultsAndConveniences() {
    let state = LicenseState()
    XCTAssertEqual(state.plan, .unlicensed)
    XCTAssertNil(state.activation)
    XCTAssertNil(state.source)
    XCTAssertFalse(state.isRefreshing)
    XCTAssertTrue(state.offerings.isEmpty)
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
}
