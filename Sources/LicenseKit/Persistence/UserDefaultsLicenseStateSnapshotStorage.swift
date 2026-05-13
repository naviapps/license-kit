import Foundation

public final class UserDefaultsLicenseStateSnapshotStorage: @unchecked Sendable,
  LicenseStateSnapshotStorage
{
  private let defaults: UserDefaults
  private let storageKey: String

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

  public func save(_ snapshot: LicenseStateSnapshot) throws {
    do {
      defaults.set(try JSONEncoder().encode(snapshot), forKey: storageKey)
    } catch {
      throw LicenseError.storageFailure
    }
  }

  public func load() throws -> LicenseStateSnapshot? {
    guard let data = defaults.data(forKey: storageKey) else { return nil }
    do {
      return try JSONDecoder().decode(LicenseStateSnapshot.self, from: data)
    } catch {
      throw LicenseError.storageFailure
    }
  }

  public func delete() throws {
    defaults.removeObject(forKey: storageKey)
  }
}
