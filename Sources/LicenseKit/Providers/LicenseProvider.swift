public protocol LicenseProvider: Sendable {
  func activate(licenseKey: String, deviceName: String) async throws -> LicenseActivation
  func deactivate(_ activation: LicenseActivation) async throws
  func validate(_ activation: LicenseActivation, validationIdentifier: String?) async throws
    -> LicenseValidationResult
}
