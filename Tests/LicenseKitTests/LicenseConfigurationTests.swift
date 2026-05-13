import XCTest

@testable import LicenseKit

final class LicenseConfigurationTests: XCTestCase {
  func testStaticConfigurationPreservesOfferings() {
    let offering = LicenseOffering(id: "pro", name: "Pro", kind: .recurring)
    let configuration = LicenseConfiguration(offerings: [offering])

    XCTAssertEqual(configuration.offerings, [offering])
    XCTAssertNil(configuration.dynamicOfferingsCatalogID)
    XCTAssertFalse(configuration.usesDynamicOfferings)
  }

  func testTrimsDynamicOfferingsCatalogID() throws {
    let offering = LicenseOffering(id: "pro", name: "Pro", kind: .recurring)
    let configuration = try LicenseConfiguration(
      offerings: [offering],
      dynamicOfferingsCatalogID: " catalog "
    )

    XCTAssertEqual(configuration.offerings, [offering])
    XCTAssertEqual(configuration.dynamicOfferingsCatalogID, "catalog")
    XCTAssertTrue(configuration.usesDynamicOfferings)
    XCTAssertEqual(
      configuration,
      try LicenseConfiguration(offerings: [offering], dynamicOfferingsCatalogID: "catalog")
    )
  }

  func testRejectsBlankDynamicOfferingsCatalogID() {
    XCTAssertThrowsError(try LicenseConfiguration(dynamicOfferingsCatalogID: " \n ")) { error in
      XCTAssertEqual(error as? LicenseConfigurationError, .invalidDynamicOfferingsCatalogID)
      XCTAssertEqual(
        String(describing: error),
        "invalid_dynamic_offerings_catalog_id"
      )
    }
  }

  func testEmptyIsStaticConfigurationWithoutOfferings() {
    let configuration = LicenseConfiguration.empty

    XCTAssertTrue(configuration.offerings.isEmpty)
    XCTAssertNil(configuration.dynamicOfferingsCatalogID)
    XCTAssertFalse(configuration.usesDynamicOfferings)
  }
}
