public struct UnavailableLicenseProvider: LicenseProvider, Sendable {
  private let message: String

  public init(message: String = "License provider is unavailable.") {
    self.message = message
  }

  public func activate(
    licenseKey _: String,
    deviceName _: String
  ) async throws -> LicenseActivation {
    throw LicenseProviderError.requestFailure(message: message)
  }

  public func deactivate(_: LicenseActivation) async throws {
    throw LicenseProviderError.requestFailure(message: message)
  }

  public func validate(
    _: LicenseActivation,
    validationIdentifier _: String?
  ) async throws -> LicenseValidationResult {
    throw LicenseProviderError.requestFailure(message: message)
  }
}
