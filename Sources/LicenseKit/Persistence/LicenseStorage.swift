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

/// Persistent storage for non-authoritative state restoration metadata.
///
/// Snapshot storage is optional. It restores local validation metadata such as
/// grace-period state, but it must not be treated as proof of entitlement
/// without a matching ``LicenseActivation``. Storage implementation errors are
/// reported by ``LicenseManager`` as ``LicenseError/storageFailure(message:)``.
public protocol LicenseStateSnapshotStorage: Sendable {
  /// Persists the current state snapshot, replacing any existing snapshot.
  func save(_ snapshot: LicenseStateSnapshot) throws

  /// Loads the persisted state snapshot, or `nil` when no snapshot is stored.
  func load() throws -> LicenseStateSnapshot?

  /// Deletes the persisted state snapshot if one exists.
  func delete() throws
}
