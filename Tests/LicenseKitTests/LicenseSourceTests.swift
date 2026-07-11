import XCTest

import LicenseKit

final class LicenseSourceTests: XCTestCase {
  func testSourceCodableUsesIdentifierString() throws {
    let source = try XCTUnwrap(LicenseSource(identifier: " source-a "))
    let data = try JSONEncoder().encode(source)

    XCTAssertEqual(String(data: data, encoding: .utf8), #""source-a""#)
    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseSource.self, from: #"" \n ""#.data(using: .utf8)!)
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(LicenseSource.self, from: #"" source-a ""#.data(using: .utf8)!)
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        LicenseSource.self,
        from: #"" unspecified ""#.data(using: .utf8)!
      )
    )
    XCTAssertEqual(
      try JSONDecoder().decode(LicenseSource.self, from: #""unspecified""#.data(using: .utf8)!),
      .unspecified
    )
  }

  func testSourceNormalizesIdentifierAndRejectsBlankValues() {
    XCTAssertEqual(LicenseSource(identifier: " source-a ")?.identifier, "source-a")
    XCTAssertEqual(LicenseSource.unspecified.identifier, "unspecified")
    XCTAssertNil(LicenseSource(identifier: "unspecified"))
    XCTAssertNil(LicenseSource(identifier: " unspecified "))
    XCTAssertNil(LicenseSource(identifier: " \n "))
  }

}
