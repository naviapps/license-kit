public protocol LicenseOfferingProvider: Sendable {
  func offerings(forCatalogID catalogID: String) async throws -> [LicenseOffering]
}
