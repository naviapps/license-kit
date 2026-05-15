import Foundation
import XCTest

@testable import LicenseKit

final class TestActivationStorage: LicenseActivationStorage, @unchecked Sendable {
  var activation: LicenseActivation?
  var saveError: Error?
  var loadError: Error?
  var deleteError: Error?

  init(activation: LicenseActivation? = nil) {
    self.activation = activation
  }

  func save(_ activation: LicenseActivation) throws {
    if let saveError { throw saveError }
    self.activation = activation
  }

  func load() throws -> LicenseActivation? {
    if let loadError { throw loadError }
    return activation
  }

  func delete() throws {
    if let deleteError { throw deleteError }
    activation = nil
  }
}

final class TestStateSnapshotStorage: LicenseStateSnapshotStorage, @unchecked Sendable {
  var snapshot: LicenseStateSnapshot?
  var saveError: Error?
  var loadError: Error?
  var deleteError: Error?

  init(state: LicenseState? = nil) {
    snapshot = state.flatMap(LicenseStateSnapshot.init(state:))
  }

  func save(_ snapshot: LicenseStateSnapshot) throws {
    if let saveError { throw saveError }
    self.snapshot = snapshot
  }

  func load() throws -> LicenseStateSnapshot? {
    if let loadError { throw loadError }
    return snapshot
  }

  func delete() throws {
    if let deleteError { throw deleteError }
    snapshot = nil
  }

  func state(matching activation: LicenseActivation) throws -> LicenseState? {
    guard let snapshot else { return nil }
    guard snapshot.matches(activation: activation) else { return nil }
    return snapshot.restoreState(activation: activation)
  }
}

final class TestProvider: LicenseProvider, @unchecked Sendable {
  let activation: LicenseActivation
  var validationResult = LicenseValidationResult(
    isValid: true,
    expiresAt: nil
  )
  var activationError: Error?
  var validationError: Error?
  var deactivationError: Error?
  var activationDelayNanoseconds: UInt64?
  var validationDelayNanoseconds: UInt64?
  private(set) var deactivationCount = 0
  private(set) var validationCount = 0
  private(set) var lastActivationLicenseKey: String?
  private(set) var lastDeactivatedActivation: LicenseActivation?
  private(set) var lastValidatedActivation: LicenseActivation?
  private(set) var lastValidationIdentifier: String?

  init(activation: LicenseActivation) {
    self.activation = activation
  }

  func activate(licenseKey: String) async throws -> LicenseActivation {
    lastActivationLicenseKey = licenseKey
    if let activationDelayNanoseconds {
      try await Task.sleep(nanoseconds: activationDelayNanoseconds)
    }
    if let activationError { throw activationError }
    return activation
  }

  func deactivate(_ activation: LicenseActivation) async throws {
    deactivationCount += 1
    lastDeactivatedActivation = activation
    if let deactivationError { throw deactivationError }
  }

  func validate(
    _ activation: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    validationCount += 1
    lastValidatedActivation = activation
    lastValidationIdentifier = validationIdentifier
    if let validationDelayNanoseconds {
      try await Task.sleep(nanoseconds: validationDelayNanoseconds)
    }
    if let validationError { throw validationError }
    return validationResult
  }
}

struct TestUnexpectedError: Error, CustomStringConvertible {
  let message: String

  var description: String {
    message
  }
}

func makeActivation(
  source: LicenseSource = .default,
  licenseKey: String? = "KEY",
  planID: String = "pro",
  activationID: String? = "instance",
  activatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
  expiresAt: Date? = nil
) -> LicenseActivation {
  LicenseActivation(
    source: source,
    licenseKey: licenseKey,
    planID: planID,
    activationID: activationID,
    activatedAt: activatedAt,
    expiresAt: expiresAt
  )
}

func makeState(
  activation: LicenseActivation,
  lastValidatedAt: Date? = nil,
  status: LicenseStatus = .active,
  gracePeriodExpiresAt: Date? = nil,
  lastRefreshFailure: LicenseRefreshFailure? = nil
) -> LicenseState {
  LicenseState(
    plan: LicensePlan.resolve(activation: activation),
    activation: activation,
    isRefreshing: false,
    lastValidatedAt: lastValidatedAt,
    status: status,
    gracePeriodExpiresAt: gracePeriodExpiresAt,
    lastRefreshFailure: lastRefreshFailure
  )
}

@MainActor
func waitForManagerState(
  file: StaticString = #filePath,
  line: UInt = #line,
  _ predicate: @MainActor () -> Bool
) async throws {
  for _ in 0..<1_000 {
    if predicate() { return }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  XCTFail("Timed out waiting for manager state.", file: file, line: line)
}
