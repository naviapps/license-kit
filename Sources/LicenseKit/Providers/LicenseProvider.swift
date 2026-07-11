/// A provider-neutral contract for activating, validating, and deactivating licenses.
public protocol LicenseProvider: Sendable {
  /// Activates a license from a provider-neutral request and returns the resolved activation.
  func activate(_ request: LicenseActivationRequest) async throws -> LicenseActivation

  /// Deactivates the current activation with the provider.
  func deactivate(_ activation: LicenseActivation) async throws

  /// Validates an activation and returns the provider's completed validation result.
  func validate(_ activation: LicenseActivation, validationIdentifier: String?) async throws
    -> LicenseValidationResult
}
