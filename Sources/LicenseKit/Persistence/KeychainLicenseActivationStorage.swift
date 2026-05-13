import Foundation
import Security

public final class KeychainLicenseActivationStorage: @unchecked Sendable,
  LicenseActivationStorage
{
  private let service: String
  private let account: String
  private let accessibility: CFString

  public init(
    service: String,
    account: String
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
    accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  }

  public func save(_ activation: LicenseActivation) throws {
    let data: Data
    do {
      data = try JSONEncoder().encode(activation)
    } catch {
      throw LicenseError.storageFailure
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
      guard updateStatus == errSecSuccess else { throw LicenseError.storageFailure }
      return
    }

    guard status == errSecSuccess else { throw LicenseError.storageFailure }
  }

  public func load() throws -> LicenseActivation? {
    var query = baseQuery()
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw LicenseError.storageFailure
    }

    do {
      return try JSONDecoder().decode(LicenseActivation.self, from: data)
    } catch {
      throw LicenseError.storageFailure
    }
  }

  public func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw LicenseError.storageFailure
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
