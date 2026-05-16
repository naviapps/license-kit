import Foundation

/// A provider-neutral activation request.
public enum LicenseActivationRequest: Sendable, Equatable {
  /// Activates from the provider's current local or runtime entitlement.
  case automatic

  /// Activates with a user-entered license key.
  case licenseKey(String)
}
