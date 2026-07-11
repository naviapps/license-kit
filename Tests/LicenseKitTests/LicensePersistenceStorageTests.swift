import Security
import XCTest

import LicenseKit

final class LicensePersistenceStorageTests: XCTestCase {
  func testKeychainActivationStorageRoundTripAndDelete() throws {
    let storage = KeychainLicenseActivationStorage(
      service: "LicenseKitTests.\(UUID().uuidString)",
      account: "license"
    )
    defer { try? storage.delete() }
    let activation = makeActivation(source: makeSource("source-a"))
    let updatedActivation = makeActivation(source: makeSource("source-b"), planIdentifier: "team")

    try storage.delete()
    XCTAssertNil(try storage.load())

    try storage.save(activation)
    XCTAssertEqual(try storage.load(), activation)

    try storage.save(updatedActivation)
    XCTAssertEqual(try storage.load(), updatedActivation)

    try storage.delete()
    try storage.delete()
    XCTAssertNil(try storage.load())
  }

  func testKeychainActivationStorageReportsDecodingFailure() throws {
    let service = "LicenseKitTests.\(UUID().uuidString)"
    let account = "license"
    let storage = KeychainLicenseActivationStorage(
      service: service,
      account: account
    )
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data("not json".utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    defer { try? storage.delete() }

    try storage.delete()
    XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

    XCTAssertThrowsError(try storage.load()) { error in
      guard case .storageFailure(let message) = error as? LicenseError else {
        return XCTFail("Expected storage failure.")
      }
      XCTAssertFalse(message.isEmpty)
    }
  }

  func testKeychainActivationStorageAcceptsConfiguredAccessibility() throws {
    let service = "LicenseKitTests.\(UUID().uuidString)"
    let account = "license"
    let storage = KeychainLicenseActivationStorage(
      service: service,
      account: account,
      accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    )
    defer { try? storage.delete() }

    try storage.delete()
    let activation = makeActivation(source: makeSource("custom-accessibility"))

    try storage.save(activation)

    XCTAssertEqual(try storage.load(), activation)
  }

  func testUserDefaultsStateMetadataStorageRoundTripOverwriteAndDelete() throws {
    let suiteName = "LicenseKitTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsLicenseStateMetadataStorage(
      defaults: defaults,
      storageKey: "metadata"
    )
    let metadataData = Data("metadata-v1".utf8)
    let updatedMetadataData = Data("metadata-v2".utf8)

    XCTAssertNil(try storage.load())

    try storage.save(metadataData)
    XCTAssertEqual(try storage.load(), metadataData)

    try storage.save(updatedMetadataData)
    XCTAssertEqual(try storage.load(), updatedMetadataData)

    try storage.delete()
    try storage.delete()
    XCTAssertNil(try storage.load())
  }

  func testUserDefaultsStateMetadataStoragePreservesOpaqueData() throws {
    let suiteName = "LicenseKitTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsLicenseStateMetadataStorage(
      defaults: defaults,
      storageKey: "metadata"
    )
    defaults.set(Data("not json".utf8), forKey: "metadata")

    XCTAssertEqual(try storage.load(), Data("not json".utf8))
  }
}
