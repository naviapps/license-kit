import XCTest

@testable import LicenseKit

final class LicenseKeyNormalizerTests: XCTestCase {
  func testLicenseKeyNormalizerRemovesWhitespaceAndIgnoredFormatScalars() {
    let normalized = LicenseKeyNormalizer.normalize(
      "  A B\nC\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}  "
    )

    XCTAssertEqual(normalized, "ABC")
  }

  func testLicenseKeyNormalizerReturnsEmptyStringWhenOnlyIgnoredCharactersRemain() {
    let normalized = LicenseKeyNormalizer.normalize(
      " \n\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\t "
    )

    XCTAssertEqual(normalized, "")
  }

  func testLicenseKeyNormalizerPreservesProviderKeyCharacters() {
    let normalized = LicenseKeyNormalizer.normalize(" abc-def_123 ")

    XCTAssertEqual(normalized, "abc-def_123")
  }
}
