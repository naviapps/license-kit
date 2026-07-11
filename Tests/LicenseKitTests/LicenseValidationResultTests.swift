import XCTest

import LicenseKit

final class LicenseValidationResultTests: XCTestCase {
  func testValidationResultDefaultsAndNormalizesPlanIdentifier() throws {
    let expiration = Date(timeIntervalSince1970: 1_700_000_000)
    let validResult = try XCTUnwrap(
      LicenseValidationResult(
        isValid: true,
        planIdentifier: " team ",
        expiresAt: expiration
      ))
    let invalidResult = try XCTUnwrap(LicenseValidationResult(isValid: false))

    XCTAssertTrue(validResult.isValid)
    XCTAssertEqual(validResult.planIdentifier, "team")
    XCTAssertEqual(validResult.expiresAt, expiration)
    XCTAssertFalse(invalidResult.isValid)
    XCTAssertNil(invalidResult.planIdentifier)
    XCTAssertNil(invalidResult.expiresAt)
    XCTAssertNil(LicenseValidationResult(isValid: false, planIdentifier: "team"))
    XCTAssertNil(LicenseValidationResult(isValid: false, expiresAt: expiration))
    XCTAssertNil(LicenseValidationResult(isValid: true, planIdentifier: " \n "))
    XCTAssertNil(LicenseValidationResult(isValid: true, planIdentifier: " unlicensed "))
    XCTAssertNil(
      LicenseValidationResult(
        isValid: true,
        expiresAt: Date(timeIntervalSinceReferenceDate: .infinity)
      )
    )
  }

  func testValidationResultDecodeNormalizesValues() throws {
    let data = """
      {
        "isValid": true,
        "planIdentifier": " team "
      }
      """.data(using: .utf8)!

    let result = try JSONDecoder().decode(LicenseValidationResult.self, from: data)

    XCTAssertTrue(result.isValid)
    XCTAssertEqual(result.planIdentifier, "team")

    let invalidData = """
      {
        "isValid": false
      }
      """.data(using: .utf8)!

    let invalidResult = try JSONDecoder().decode(LicenseValidationResult.self, from: invalidData)

    XCTAssertFalse(invalidResult.isValid)
    XCTAssertNil(invalidResult.planIdentifier)
    XCTAssertNil(invalidResult.expiresAt)
  }

  func testValidationResultDecodeRejectsInvalidPayloads() {
    let invalidWithPlan = """
      {
        "isValid": false,
        "planIdentifier": "team"
      }
      """.data(using: .utf8)!
    let invalidWithExpiration = """
      {
        "isValid": false,
        "expiresAt": 1700000000
      }
      """.data(using: .utf8)!
    let blankPlan = """
      {
        "isValid": true,
        "planIdentifier": " \n "
      }
      """.data(using: .utf8)!
    let reservedPlan = """
      {
        "isValid": true,
        "planIdentifier": " unlicensed "
      }
      """.data(using: .utf8)!
    let nullPlan = """
      {
        "isValid": true,
        "planIdentifier": null
      }
      """.data(using: .utf8)!
    let unknownField = """
      {
        "isValid": true,
        "unexpected": "team"
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseValidationResult.self, from: invalidWithPlan))
    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseValidationResult.self, from: invalidWithExpiration)
    )
    XCTAssertThrowsError(try JSONDecoder().decode(LicenseValidationResult.self, from: blankPlan))
    XCTAssertThrowsError(try JSONDecoder().decode(LicenseValidationResult.self, from: reservedPlan))
    XCTAssertThrowsError(try JSONDecoder().decode(LicenseValidationResult.self, from: nullPlan))
    XCTAssertThrowsError(try JSONDecoder().decode(LicenseValidationResult.self, from: unknownField))
  }

}
