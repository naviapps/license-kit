import Foundation
import Security

/// ``LicenseActivationStorage`` backed by the system Keychain.
///
/// Use this storage for the authoritative activation record in production apps.
/// The activation is encoded as JSON and stored as a generic password item.
public final class KeychainLicenseActivationStorage: @unchecked Sendable,
  LicenseActivationStorage
{
  private let service: String
  private let account: String
  private let accessibility: CFString

  /// Creates Keychain-backed activation storage.
  ///
  /// - Parameters:
  ///   - service: The Keychain service used to identify the activation item.
  ///   - account: The Keychain account used to identify the activation item.
  ///   - accessibility: The Keychain accessibility class applied when saving.
  public init(
    service: String,
    account: String,
    accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  ) {
    let normalizedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(
      normalizedService.isEmpty == false,
      "KeychainLicenseActivationStorage service must not be empty."
    )
    precondition(
      normalizedAccount.isEmpty == false,
      "KeychainLicenseActivationStorage account must not be empty."
    )

    self.service = normalizedService
    self.account = normalizedAccount
    self.accessibility = accessibility
  }

  /// Persists the current activation.
  public func save(_ activation: LicenseActivation) throws {
    let data: Data
    do {
      data = try JSONEncoder().encode(activation)
    } catch {
      throw LicenseError.storageFailure(normalizing: error)
    }

    var query = baseQuery()
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = accessibility

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateStatus = SecItemUpdate(
        baseQuery() as CFDictionary,
        [
          kSecValueData as String: data,
          kSecAttrAccessible as String: accessibility,
        ] as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw keychainStorageFailure(operation: "update", status: updateStatus)
      }
      return
    }

    guard status == errSecSuccess else {
      throw keychainStorageFailure(operation: "save", status: status)
    }
  }

  /// Loads the persisted activation, if one exists.
  public func load() throws -> LicenseActivation? {
    var query = baseQuery()
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw keychainStorageFailure(operation: "load", status: status)
    }

    do {
      return try JSONDecoder().decode(LicenseActivation.self, from: data)
    } catch {
      throw LicenseError.storageFailure(normalizing: error)
    }
  }

  /// Deletes the persisted activation if one exists.
  public func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw keychainStorageFailure(operation: "delete", status: status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func keychainStorageFailure(operation: String, status: OSStatus) -> LicenseError {
    .storageFailure(message: "Keychain \(operation) failed with status \(status).")
  }
}
