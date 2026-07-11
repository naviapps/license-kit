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

final class TestStateMetadataStorage: LicenseStateMetadataStorage, @unchecked Sendable {
  var metadataData: Data?
  var saveError: Error?
  var loadError: Error?
  var deleteError: Error?

  var metadata: LicenseStateMetadata? {
    guard let metadataData else { return nil }
    return try? JSONDecoder().decode(LicenseStateMetadata.self, from: metadataData)
  }

  init(state: LicenseState? = nil) {
    if let metadata = state.flatMap(LicenseStateMetadata.init(state:)) {
      metadataData = try? JSONEncoder().encode(metadata)
    }
  }

  func save(_ metadataData: Data) throws {
    if let saveError { throw saveError }
    self.metadataData = metadataData
  }

  func load() throws -> Data? {
    if let loadError { throw loadError }
    return metadataData
  }

  func delete() throws {
    if let deleteError { throw deleteError }
    metadataData = nil
  }

  func state(matching activation: LicenseActivation) throws -> LicenseState? {
    guard let metadata else { return nil }
    guard metadata.matches(activation: activation) else { return nil }
    return metadata.restoreState(activation: activation)
  }
}

final class TestProvider: LicenseProvider, @unchecked Sendable {
  let activation: LicenseActivation
  var validationResult = makeValidationResult(
    isValid: true,
    expiresAt: nil
  )
  var activationError: Error?
  var validationError: Error?
  var deactivationError: Error?
  var activationDelayNanoseconds: UInt64?
  var validationDelayNanoseconds: UInt64?
  var deactivationDelayNanoseconds: UInt64?
  private(set) var activationCount = 0
  private(set) var deactivationCount = 0
  private(set) var validationCount = 0
  private(set) var lastActivationRequest: LicenseActivationRequest?
  private(set) var lastActivationLicenseKey: String?
  private(set) var lastDeactivatedActivation: LicenseActivation?
  private(set) var lastValidatedActivation: LicenseActivation?
  private(set) var lastValidationIdentifier: String?

  init(activation: LicenseActivation) {
    self.activation = activation
  }

  func activate(_ request: LicenseActivationRequest) async throws -> LicenseActivation {
    activationCount += 1
    lastActivationRequest = request
    if case .licenseKey(let licenseKey) = request {
      lastActivationLicenseKey = licenseKey
    } else {
      lastActivationLicenseKey = nil
    }
    if let activationDelayNanoseconds {
      try await Task.sleep(nanoseconds: activationDelayNanoseconds)
    }
    if let activationError { throw activationError }
    return activation
  }

  func deactivate(_ activation: LicenseActivation) async throws {
    deactivationCount += 1
    lastDeactivatedActivation = activation
    if let deactivationDelayNanoseconds {
      try await Task.sleep(nanoseconds: deactivationDelayNanoseconds)
    }
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

func makeSource(_ identifier: String) -> LicenseSource {
  LicenseSource(identifier: identifier)!
}

func makeActivation(
  source: LicenseSource = .unspecified,
  licenseKey: String? = "KEY",
  planIdentifier: String = "pro",
  activationIdentifier: String? = "instance",
  activatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
  expiresAt: Date? = nil
) -> LicenseActivation {
  LicenseActivation(
    source: source,
    planIdentifier: planIdentifier,
    activatedAt: activatedAt,
    licenseKey: licenseKey,
    activationIdentifier: activationIdentifier,
    expiresAt: expiresAt
  )!
}

func makePlan(
  identifier: String = "pro",
  isLicensed: Bool = true,
  expiresAt: Date? = nil
) -> LicensePlan {
  LicensePlan(identifier: identifier, isLicensed: isLicensed, expiresAt: expiresAt)!
}

func makeValidationResult(
  isValid: Bool = true,
  planIdentifier: String? = nil,
  expiresAt: Date? = nil
) -> LicenseValidationResult {
  LicenseValidationResult(
    isValid: isValid,
    planIdentifier: planIdentifier,
    expiresAt: expiresAt
  )!
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
