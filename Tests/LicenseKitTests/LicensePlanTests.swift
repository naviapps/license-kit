import XCTest

import LicenseKit

final class LicensePlanTests: XCTestCase {
  func testPlanExpiration() {
    XCTAssertEqual(
      makePlan(identifier: " pro ", isLicensed: true, expiresAt: nil).identifier,
      "pro"
    )
    XCTAssertEqual(LicensePlan(identifier: "unlicensed", isLicensed: false), .unlicensed)
    XCTAssertNil(LicensePlan(identifier: " unlicensed ", isLicensed: false))
    XCTAssertNil(LicensePlan(identifier: "pro", isLicensed: false))
    XCTAssertNil(
      LicensePlan(
        identifier: "unlicensed",
        isLicensed: false,
        expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
    XCTAssertNil(LicensePlan(identifier: " ", isLicensed: true))
    XCTAssertNil(LicensePlan(identifier: " unlicensed ", isLicensed: true))
    XCTAssertNil(
      LicensePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSinceReferenceDate: .infinity)
      )
    )
    XCTAssertFalse(makePlan(identifier: "pro", isLicensed: true, expiresAt: nil).isExpired)
    XCTAssertFalse(
      makePlan(identifier: "pro", isLicensed: true, expiresAt: nil)
        .isExpired(at: Date(timeIntervalSinceReferenceDate: .infinity))
    )
    XCTAssertTrue(
      makePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
      .isExpired(at: Date(timeIntervalSince1970: 1_700_000_000))
    )
    XCTAssertFalse(
      makePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date().addingTimeInterval(60)
      ).isExpired
    )
    XCTAssertTrue(
      makePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date().addingTimeInterval(-60)
      ).isExpired
    )
  }

  func testPlanDecodeNormalizesIdentifier() throws {
    let data = """
      {
        "id": " pro ",
        "isLicensed": true
      }
      """.data(using: .utf8)!

    let plan = try JSONDecoder().decode(LicensePlan.self, from: data)

    XCTAssertEqual(plan.identifier, "pro")
    XCTAssertTrue(plan.isLicensed)
  }

  func testPlanCodableUsesCanonicalUnlicensedPlan() throws {
    let data = try JSONEncoder().encode(LicensePlan.unlicensed)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(object["id"] as? String, "unlicensed")
    XCTAssertEqual(object["isLicensed"] as? Bool, false)
    XCTAssertNil(object["expiresAt"])
    XCTAssertEqual(try JSONDecoder().decode(LicensePlan.self, from: data), .unlicensed)
  }

  func testPlanDecodeRejectsUnlicensedPlanWithLicensedPayload() {
    let data = """
      {
        "id": "pro",
        "isLicensed": false,
        "expiresAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsBlankUnlicensedIdentifier() {
    let data = """
      {
        "id": " ",
        "isLicensed": false
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsNonCanonicalUnlicensedIdentifier() {
    let data = """
      {
        "id": " unlicensed ",
        "isLicensed": false
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsMissingUnlicensedIdentifier() {
    let data = """
      {
        "isLicensed": false
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsBlankLicensedIdentifier() {
    let data = """
      {
        "id": " ",
        "isLicensed": true
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsReservedLicensedIdentifier() {
    let data = """
      {
        "id": " unlicensed ",
        "isLicensed": true
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsUnknownFields() {
    let data = """
      {
        "id": "pro",
        "isLicensed": true,
        "extra": true
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

  func testPlanDecodeRejectsNullExpiration() {
    let data = """
      {
        "id": "pro",
        "isLicensed": true,
        "expiresAt": null
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicensePlan.self, from: data))
  }

}
