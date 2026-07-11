/// Persistent storage for the authoritative activation record.
///
/// Production apps should use secure storage because ``LicenseActivation`` may
/// contain a license key or provider activation identifier. Storage
/// implementation errors are reported by ``LicenseManager`` as
/// ``LicenseError/storageFailure(message:)``.
public protocol LicenseActivationStorage: Sendable {
  /// Persists the current activation, replacing any existing activation.
  func save(_ activation: LicenseActivation) throws

  /// Loads the persisted activation, or `nil` when no activation is stored.
  func load() throws -> LicenseActivation?

  /// Deletes the persisted activation if one exists.
  func delete() throws
}
