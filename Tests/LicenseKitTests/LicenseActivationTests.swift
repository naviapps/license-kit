import XCTest

import LicenseKit

final class LicenseActivationTests: XCTestCase {
  func testActivationCodableRoundTrip() throws {
    let activation = makeActivation(source: makeSource("source-a"))

    let data = try JSONEncoder().encode(activation)
    let decoded = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertEqual(decoded, activation)
    XCTAssertEqual(decoded.source, makeSource("source-a"))
  }

  func testActivationEncodesCanonicalFieldNames() throws {
    let data = try JSONEncoder().encode(makeActivation())
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertNotNil(object["planIdentifier"])
    XCTAssertNotNil(object["activationIdentifier"])
  }

  func testActivationDefaultsAndNormalizesOptionalDetails() throws {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: " pro ",
        activatedAt: activatedAt,
        licenseKey: " K E\u{200B}Y ",
        activationIdentifier: " activation "
      ))

    XCTAssertEqual(activation.source, .unspecified)
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planIdentifier, "pro")
    XCTAssertEqual(activation.activationIdentifier, "activation")
    XCTAssertEqual(activation.activatedAt, activatedAt)
    XCTAssertNil(activation.expiresAt)
    XCTAssertNil(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: " \n\t ",
        activatedAt: activatedAt
      )
    )
    XCTAssertNil(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: " unlicensed ",
        activatedAt: activatedAt
      )
    )
  }

  func testActivationDropsBlankOptionalIdentifiers() throws {
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        licenseKey: " \n\t ",
        activationIdentifier: " \n\t "
      ))

    XCTAssertNil(activation.licenseKey)
    XCTAssertNil(activation.activationIdentifier)
  }

  func testActivationPreservesProviderOpaqueIdentifierCharacters() throws {
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        activationIdentifier: " provider\u{200B} instance "
      ))

    XCTAssertEqual(activation.activationIdentifier, "provider\u{200B} instance")
  }

  func testActivationDecodeNormalizesValues() throws {
    let data = """
      {
        "source": "provider-a",
        "licenseKey": " K E\\u200BY ",
        "planIdentifier": " pro ",
        "activationIdentifier": " activation ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    let activation = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertEqual(activation.source, makeSource("provider-a"))
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(activation.planIdentifier, "pro")
    XCTAssertEqual(activation.activationIdentifier, "activation")
    XCTAssertEqual(activation.activatedAt, Date(timeIntervalSinceReferenceDate: 1_700_000_000))
  }

  func testActivationDecodeRejectsNonCanonicalSource() {
    let data = """
      {
        "source": " provider-a ",
        "planIdentifier": "pro",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
  }

  func testActivationDecodeDropsBlankOptionalIdentifiers() throws {
    let data = """
      {
        "source": "provider-a",
        "licenseKey": " ",
        "planIdentifier": "pro",
        "activationIdentifier": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    let activation = try JSONDecoder().decode(LicenseActivation.self, from: data)

    XCTAssertNil(activation.licenseKey)
    XCTAssertNil(activation.activationIdentifier)
  }

  func testActivationDecodeRejectsReservedPlanIdentifier() throws {
    let data = """
      {
        "source": "provider-a",
        "planIdentifier": " unlicensed ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
  }

  func testActivationDecodeRejectsMissingSource() throws {
    let data = """
      {
        "licenseKey": " KEY ",
        "planIdentifier": " pro ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
  }

  func testActivationDecodeRejectsMissingActivatedAt() throws {
    let data = """
      {
        "source": "provider-a",
        "licenseKey": " KEY ",
        "planIdentifier": " pro "
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
  }

  func testActivationDecodeRejectsInvalidValues() {
    let blankPlanIdentifier = """
      {
        "source": "provider-a",
        "planIdentifier": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseActivation.self, from: blankPlanIdentifier)
    )
  }

  func testActivationDecodeRejectsUnknownFields() {
    let data = """
      {
        "source": "provider-a",
        "planIdentifier": "pro",
        "activatedAt": 1700000000,
        "unexpected": true
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
  }

  func testActivationDecodeRejectsNullOptionalFields() {
    for fieldName in ["licenseKey", "activationIdentifier", "expiresAt"] {
      let data = """
        {
          "source": "provider-a",
          "planIdentifier": "pro",
          "activatedAt": 1700000000,
          "\(fieldName)": null
        }
        """.data(using: .utf8)!

      XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
    }
  }

  func testActivationRequiresExplicitActivatedAt() throws {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: activatedAt
      )
    )

    XCTAssertEqual(activation.activatedAt, activatedAt)
  }

  func testActivationRejectsExpirationAtOrBeforeActivationTime() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    XCTAssertNil(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: activatedAt,
        expiresAt: activatedAt
      )
    )
    XCTAssertNil(
      LicenseActivation(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: activatedAt,
        expiresAt: activatedAt.addingTimeInterval(-1)
      )
    )
  }

  func testActivationRejectsNonFiniteDates() {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let nonFiniteDates = [
      Date(timeIntervalSinceReferenceDate: .nan),
      Date(timeIntervalSinceReferenceDate: .infinity),
      Date(timeIntervalSinceReferenceDate: -.infinity),
    ]

    for date in nonFiniteDates {
      XCTAssertNil(
        LicenseActivation(
          source: .unspecified,
          planIdentifier: "pro",
          activatedAt: date
        )
      )
      XCTAssertNil(
        LicenseActivation(
          source: .unspecified,
          planIdentifier: "pro",
          activatedAt: activatedAt,
          expiresAt: date
        )
      )
    }
  }

  func testActivationDecodeRejectsNonFiniteDates() {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    for dateValue in ["NaN", "Infinity", "-Infinity"] {
      let nonFiniteActivatedAt = """
        {
          "source": "provider-a",
          "planIdentifier": "pro",
          "activatedAt": "\(dateValue)"
        }
        """.data(using: .utf8)!
      let nonFiniteExpiresAt = """
        {
          "source": "provider-a",
          "planIdentifier": "pro",
          "activatedAt": 1700000000,
          "expiresAt": "\(dateValue)"
        }
        """.data(using: .utf8)!

      XCTAssertThrowsError(try decoder.decode(LicenseActivation.self, from: nonFiniteActivatedAt))
      XCTAssertThrowsError(try decoder.decode(LicenseActivation.self, from: nonFiniteExpiresAt))
    }
  }

  func testActivationDecodeRejectsExpirationAtOrBeforeActivationTime() {
    let invalidExpirationValues = [
      "1700000000",
      "1699999999",
    ]

    for expiresAt in invalidExpirationValues {
      let data = """
        {
          "source": "provider-a",
          "planIdentifier": "pro",
          "activatedAt": 1700000000,
          "expiresAt": \(expiresAt)
        }
        """.data(using: .utf8)!

      XCTAssertThrowsError(try JSONDecoder().decode(LicenseActivation.self, from: data))
    }
  }

  func testActivationExpiration() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let beforeNow = now.addingTimeInterval(-1)

    XCTAssertFalse(makeActivation(expiresAt: nil).isExpired(at: now))
    XCTAssertFalse(makeActivation(expiresAt: now.addingTimeInterval(1)).isExpired(at: now))
    XCTAssertTrue(makeActivation(activatedAt: beforeNow, expiresAt: now).isExpired(at: now))
    XCTAssertFalse(
      makeActivation(activatedAt: beforeNow, expiresAt: now).isExpired(
        at: Date(timeIntervalSinceReferenceDate: .infinity)
      )
    )
    XCTAssertTrue(
      makeActivation(
        activatedAt: beforeNow.addingTimeInterval(-1),
        expiresAt: beforeNow
      ).isExpired(at: now)
    )
  }

}
