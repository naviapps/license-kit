import Foundation

/// ``LicenseStateMetadataStorage`` backed by `UserDefaults`.
///
/// Use this storage only for non-authoritative state restoration metadata. The
/// authoritative ``LicenseActivation`` should be stored separately in secure
/// storage. The stored metadata payload is encoded and decoded by LicenseKit.
public final class UserDefaultsLicenseStateMetadataStorage: @unchecked Sendable,
  LicenseStateMetadataStorage
{
  private let defaults: UserDefaults
  private let storageKey: String

  /// Creates UserDefaults-backed metadata storage.
  ///
  /// - Parameters:
  ///   - defaults: The defaults instance used to store metadata.
  ///   - storageKey: The key used to store the encoded metadata.
  public init(
    defaults: UserDefaults = .standard,
    storageKey: String
  ) {
    let normalizedStorageKey = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(
      normalizedStorageKey.isEmpty == false,
      "UserDefaultsLicenseStateMetadataStorage storageKey must not be empty."
    )

    self.defaults = defaults
    self.storageKey = normalizedStorageKey
  }

  /// Persists the current encoded state metadata.
  public func save(_ metadata: Data) throws {
    defaults.set(metadata, forKey: storageKey)
  }

  /// Loads the persisted encoded state metadata, if it exists.
  public func load() throws -> Data? {
    defaults.data(forKey: storageKey)
  }

  /// Deletes the persisted state metadata if it exists.
  public func delete() throws {
    defaults.removeObject(forKey: storageKey)
  }
}
