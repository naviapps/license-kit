import Foundation

/// ``LicenseStateSnapshotStorage`` backed by `UserDefaults`.
///
/// Use this storage only for non-authoritative state restoration metadata. The
/// authoritative ``LicenseActivation`` should be stored separately in secure
/// storage.
public final class UserDefaultsLicenseStateSnapshotStorage: @unchecked Sendable,
  LicenseStateSnapshotStorage
{
  private let defaults: UserDefaults
  private let storageKey: String

  /// Creates UserDefaults-backed snapshot storage.
  ///
  /// - Parameters:
  ///   - defaults: The defaults instance used to store snapshot data.
  ///   - storageKey: The key used to store the encoded snapshot.
  public init(
    defaults: UserDefaults = .standard,
    storageKey: String
  ) {
    let normalizedStorageKey = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(
      normalizedStorageKey.isEmpty == false,
      "UserDefaultsLicenseStateSnapshotStorage storageKey must not be empty."
    )

    self.defaults = defaults
    self.storageKey = normalizedStorageKey
  }

  /// Persists the current state snapshot.
  public func save(_ snapshot: LicenseStateSnapshot) throws {
    do {
      defaults.set(try JSONEncoder().encode(snapshot), forKey: storageKey)
    } catch {
      throw LicenseError.storageFailure(error)
    }
  }

  /// Loads the persisted state snapshot, if one exists.
  public func load() throws -> LicenseStateSnapshot? {
    guard let data = defaults.data(forKey: storageKey) else { return nil }
    do {
      return try JSONDecoder().decode(LicenseStateSnapshot.self, from: data)
    } catch {
      throw LicenseError.storageFailure(error)
    }
  }

  /// Deletes the persisted state snapshot if one exists.
  public func delete() throws {
    defaults.removeObject(forKey: storageKey)
  }
}
