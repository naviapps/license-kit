import Foundation

/// Persistent storage for encoded, non-authoritative license state metadata.
///
/// Metadata storage is optional. It restores local validation metadata such as
/// grace-period state, but it must not be treated as proof of entitlement
/// without a matching ``LicenseActivation``. The encoded payload is owned by
/// LicenseKit; custom storage implementations should persist and return the
/// data unchanged. Load errors are reported on manager initialization, while
/// save and delete errors are ignored because metadata is non-authoritative.
public protocol LicenseStateMetadataStorage: Sendable {
  /// Persists the current encoded state metadata, replacing any existing payload.
  func save(_ metadata: Data) throws

  /// Loads the persisted encoded state metadata, or `nil` when none is stored.
  func load() throws -> Data?

  /// Deletes the persisted encoded state metadata if it exists.
  func delete() throws
}
