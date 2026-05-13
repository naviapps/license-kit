import Foundation

public struct LicenseConfiguration: Equatable, Sendable {
  public let offerings: [LicenseOffering]
  public let dynamicOfferingsCatalogID: String?

  public var usesDynamicOfferings: Bool {
    dynamicOfferingsCatalogID != nil
  }

  public init(offerings: [LicenseOffering] = []) {
    self.offerings = offerings
    dynamicOfferingsCatalogID = nil
  }

  public init(offerings: [LicenseOffering] = [], dynamicOfferingsCatalogID: String) throws {
    guard let catalogID = dynamicOfferingsCatalogID.licenseKitTrimmedNonEmpty else {
      throw LicenseConfigurationError.invalidDynamicOfferingsCatalogID
    }

    self.offerings = offerings
    self.dynamicOfferingsCatalogID = catalogID
  }

  public static let empty = LicenseConfiguration()
}
