import Foundation

public protocol LicenseCustomerPortalProvider: Sendable {
  func customerPortalURL(forCustomerID customerID: String) async throws -> URL?
}
