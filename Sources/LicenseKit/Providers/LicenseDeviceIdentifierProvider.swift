public protocol LicenseDeviceIdentifierProvider: Sendable {
  func deviceIdentifier() -> String?
}
