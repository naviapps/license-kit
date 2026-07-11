/// A provider-neutral request to start license activation.
public enum LicenseActivationRequest: Sendable, Equatable, Hashable {
  /// Activates from the provider's current local or runtime entitlement.
  case automatic

  /// Activates with a user-entered license key.
  ///
  /// ``LicenseManager`` normalizes and rejects blank keys before forwarding the
  /// request to a provider.
  case licenseKey(String)
}
