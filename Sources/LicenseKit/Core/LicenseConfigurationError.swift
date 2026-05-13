import Foundation

public enum LicenseConfigurationError: Error, Equatable, Sendable {
  case invalidDynamicOfferingsCatalogID
}

extension LicenseConfigurationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidDynamicOfferingsCatalogID:
      "invalid_dynamic_offerings_catalog_id"
    }
  }
}
