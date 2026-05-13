import Security
import XCTest

@testable import LicenseKit

final class LicenseStorageTests: XCTestCase {
  func testKeychainActivationStorageRoundTripAndDelete() throws {
    let storage = KeychainLicenseActivationStorage(
      service: "LicenseKitTests.\(UUID().uuidString)",
      account: "license"
    )
    defer { try? storage.delete() }
    let activation = makeActivation(source: "source-a")
    let updatedActivation = makeActivation(source: "source-b", planID: "team")

    try storage.delete()
    XCTAssertNil(try storage.load())

    try storage.save(activation)
    XCTAssertEqual(try storage.load(), activation)

    try storage.save(updatedActivation)
    XCTAssertEqual(try storage.load(), updatedActivation)

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
      XCTAssertEqual(error as? LicenseError, .storageFailure)
    }
  }

  func testUserDefaultsStateStorageRoundTripOverwriteAndDelete() throws {
    let suiteName = "LicenseKitTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsLicenseStateSnapshotStorage(
      defaults: defaults,
      storageKey: "snapshot"
    )
    let activation = makeActivation()
    let failure = LicenseRefreshFailure(
      reason: .networkFailure,
      message: "offline",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    let state = LicenseState(
      plan: LicensePlan(id: "pro", isLicensed: true, expiresAt: nil),
      activation: activation,
      isRefreshing: false,
      offerings: [],
      lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      status: .gracePeriod,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_086_400),
      lastRefreshFailure: failure
    )
    let snapshot = try XCTUnwrap(LicenseStateSnapshot(state: state))
    let updatedState = LicenseState(
      plan: LicensePlan(id: "team", isLicensed: true, expiresAt: nil),
      activation: activation,
      isRefreshing: false,
      offerings: [],
      lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_200),
      status: .active,
      gracePeriodExpiresAt: nil,
      lastRefreshFailure: nil
    )
    let updatedSnapshot = try XCTUnwrap(LicenseStateSnapshot(state: updatedState))

    XCTAssertNil(try storage.load())

    try storage.save(snapshot)
    let loadedSnapshot = try XCTUnwrap(try storage.load())
    XCTAssertEqual(loadedSnapshot.restoreState(activation: activation, offerings: []), state)

    try storage.save(updatedSnapshot)
    let loadedUpdatedSnapshot = try XCTUnwrap(try storage.load())
    XCTAssertEqual(
      loadedUpdatedSnapshot.restoreState(activation: activation, offerings: []),
      updatedState
    )

    try storage.delete()
    XCTAssertNil(try storage.load())
  }

  func testUserDefaultsStateStorageReportsDecodingFailure() throws {
    let suiteName = "LicenseKitTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let storage = UserDefaultsLicenseStateSnapshotStorage(
      defaults: defaults,
      storageKey: "snapshot"
    )
    defaults.set(Data("not json".utf8), forKey: "snapshot")

    XCTAssertThrowsError(try storage.load()) { error in
      XCTAssertEqual(error as? LicenseError, .storageFailure)
    }
  }
}
