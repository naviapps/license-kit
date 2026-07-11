import XCTest

@testable import LicenseKit

final class LicenseInternalNormalizationTests: XCTestCase {
  private static let copiedWhitespaceScalars =
    " \n\t\u{00A0}\u{1680}\u{2028}\u{2029}\u{3000}"

  private static let copiedInvisibleScalars =
    "\u{0000}\u{0007}\u{007F}"
    + "\u{00AD}\u{061C}\u{200B}\u{200C}\u{200D}\u{200E}"
    + "\u{200F}\u{202E}\u{2060}\u{2066}\u{2069}\u{FEFF}"

  func testTrimmedNonEmptyStringHelperTrimsOnlyEdges() {
    XCTAssertEqual(" value ".licenseKitTrimmedNonEmpty, "value")
    XCTAssertEqual("provider instance".licenseKitTrimmedNonEmpty, "provider instance")
    XCTAssertEqual("provider\u{200B}instance".licenseKitTrimmedNonEmpty, "provider\u{200B}instance")
    XCTAssertNil(" \n\t ".licenseKitTrimmedNonEmpty)
  }

  func testLicenseKeyNormalizerRemovesWhitespaceAndInvisibleScalars() {
    let input =
      "\(Self.copiedWhitespaceScalars)A B\nC"
      + "\(Self.copiedInvisibleScalars)\(Self.copiedWhitespaceScalars)"
    let normalized = LicenseKeyNormalizer.normalize(input)

    XCTAssertEqual(normalized, "ABC")
  }

  func testLicenseKeyNormalizerReturnsEmptyStringWhenOnlyIgnoredCharactersRemain() {
    let normalized = LicenseKeyNormalizer.normalize(
      "\(Self.copiedWhitespaceScalars)\(Self.copiedInvisibleScalars)"
    )

    XCTAssertEqual(normalized, "")
  }

  func testLicenseKeyNormalizerPreservesProviderKeyCharacters() {
    let normalized = LicenseKeyNormalizer.normalize(" abc-def_123+/=: ")

    XCTAssertEqual(normalized, "abc-def_123+/=:")
  }

  func testStorageFailureMapsUnexpectedErrors() {
    XCTAssertEqual(
      LicenseError.storageFailure(
        normalizing: TestUnexpectedError(message: "keychain unavailable")
      ),
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(
      LicenseError.storageFailure(normalizing: TestUnexpectedError(message: " \n ")),
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(
      LicenseError.storageFailure(
        normalizing: LicenseError.storageFailure(message: "explicit storage failure")
      ),
      .storageFailure(message: "explicit storage failure")
    )
  }

  func testRequestFailureNormalizesMessages() {
    XCTAssertEqual(
      LicenseError.requestFailure(normalizing: nil),
      .requestFailure(message: "Request failed.")
    )
    XCTAssertEqual(
      LicenseError.requestFailure(normalizing: " \n\t "),
      .requestFailure(message: "Request failed.")
    )
    XCTAssertEqual(
      LicenseError.requestFailure(normalizing: " offline "),
      .requestFailure(message: "offline")
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
        .transportFailure(message: " \n\t "),
        LicenseRefreshFailure(
          reason: .transportFailure,
          message: "Transport failed.",
          occurredAt: occurredAt
        )
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
      (
        .requestFailure(message: " \n\t "),
        LicenseRefreshFailure(
          reason: .requestFailure,
          message: "Request failed.",
          occurredAt: occurredAt
        )
      ),
    ]

    for (error, expectedFailure) in cases {
      XCTAssertEqual(LicenseRefreshFailure(error: error, occurredAt: occurredAt), expectedFailure)
    }
  }
}
