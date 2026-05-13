import Foundation

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
    return snapshot.restoreState(activation: activation, offerings: [])
  }
}

final class TestProvider: LicenseProvider, @unchecked Sendable {
  var activation: LicenseActivation
  var validationResult = LicenseValidationResult(
    isValid: true,
    expiresAt: nil,
    remainingActivations: nil
  )
  var activationError: Error?
  var validationError: Error?
  var deactivationError: Error?
  var activationDelayNanoseconds: UInt64?
  var validationDelayNanoseconds: UInt64?
  private(set) var deactivationCount = 0
  private(set) var lastActivationLicenseKey: String?
  private(set) var lastActivationDeviceName: String?
  private(set) var lastValidationIdentifier: String?

  init(activation: LicenseActivation) {
    self.activation = activation
  }

  func activate(licenseKey: String, deviceName: String) async throws -> LicenseActivation {
    lastActivationLicenseKey = licenseKey
    lastActivationDeviceName = deviceName
    if let activationDelayNanoseconds {
      try await Task.sleep(nanoseconds: activationDelayNanoseconds)
    }
    if let activationError { throw activationError }
    return LicenseActivation(
      source: activation.source,
      licenseKey: activation.licenseKey,
      planID: activation.planID,
      customerID: activation.customerID,
      deviceName: deviceName,
      activationID: activation.activationID,
      activatedAt: activation.activatedAt,
      expiresAt: activation.expiresAt,
      remainingActivations: activation.remainingActivations
    )
  }

  func deactivate(_: LicenseActivation) async throws {
    deactivationCount += 1
    if let deactivationError { throw deactivationError }
  }

  func validate(
    _: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    lastValidationIdentifier = validationIdentifier
    if let validationDelayNanoseconds {
      try await Task.sleep(nanoseconds: validationDelayNanoseconds)
    }
    if let validationError { throw validationError }
    return validationResult
  }
}

final class TestOfferingProvider: LicenseOfferingProvider, @unchecked Sendable {
  var offerings: [LicenseOffering]
  var error: Error?

  init(offerings: [LicenseOffering]) {
    self.offerings = offerings
  }

  func offerings(forCatalogID _: String) async throws -> [LicenseOffering] {
    if let error { throw error }
    return offerings
  }
}

final class TestCustomerPortalProvider: LicenseCustomerPortalProvider, @unchecked Sendable {
  let url: URL?
  var error: Error?

  init(url: URL?) {
    self.url = url
  }

  func customerPortalURL(forCustomerID _: String) async throws -> URL? {
    if let error { throw error }
    return url
  }
}

struct TestDeviceIdentifierProvider: LicenseDeviceIdentifierProvider {
  let identifier: String?

  func deviceIdentifier() -> String? {
    identifier
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
  customerID: String? = "customer",
  activationID: String? = "instance",
  activatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
  expiresAt: Date? = nil,
  remainingActivations: Int? = 1
) -> LicenseActivation {
  LicenseActivation(
    source: source,
    licenseKey: licenseKey,
    planID: planID,
    customerID: customerID,
    deviceName: "Mac",
    activationID: activationID,
    activatedAt: activatedAt,
    expiresAt: expiresAt,
    remainingActivations: remainingActivations
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
    offerings: [],
    lastValidatedAt: lastValidatedAt,
    status: status,
    gracePeriodExpiresAt: gracePeriodExpiresAt,
    lastRefreshFailure: lastRefreshFailure
  )
}
