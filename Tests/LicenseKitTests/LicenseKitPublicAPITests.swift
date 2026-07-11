import Foundation
import Security
import XCTest

import LicenseKit

@MainActor
final class LicenseKitPublicAPITests: XCTestCase {
  func testManagerProviderAndStorageAPIsAreUsableFromPublicImport() async throws {
    let providerActivation = try XCTUnwrap(
      LicenseActivation(
        source: makePublicSource("backend"),
        planIdentifier: " pro ",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        licenseKey: nil,
        activationIdentifier: " activation-1 "
      )
    )
    let provider = PublicProvider(activation: providerActivation)
    let activationStorage = PublicActivationStorage()
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      refreshPolicy: try LicenseRefreshPolicy(
        validationInterval: 60,
        failureGracePeriod: 30,
        serverFailureGracePeriod: 15
      )
    )

    let activatedState = try await manager.activate(
      LicenseActivationRequest.licenseKey(" USER-KEY ")
    )

    XCTAssertEqual(provider.activationRequest, LicenseActivationRequest.licenseKey("USER-KEY"))
    XCTAssertEqual(activatedState.status, LicenseStatus.active)
    XCTAssertEqual(manager.state.status, LicenseStatus.active)
    XCTAssertEqual(manager.plan.identifier, "pro")
    XCTAssertEqual(manager.activation?.licenseKey, "USER-KEY")
    XCTAssertEqual(manager.source, providerActivation.source)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertTrue(manager.refreshPolicy.isEnabled)
    XCTAssertNil(manager.initialRestoreError)
    XCTAssertEqual(try activationStorage.load()?.licenseKey, "USER-KEY")
  }

  func testReadmeProviderExampleIsUsableFromPublicImport() async throws {
    let provider = MyLicenseProvider(licenseAPI: TestLicenseAPI())
    let activation = try await provider.activate(.licenseKey(" USER-KEY "))
    let validation = try await provider.validate(activation, validationIdentifier: nil)

    XCTAssertEqual(activation.source, makePublicSource("backend"))
    XCTAssertEqual(activation.licenseKey, "USER-KEY")
    XCTAssertEqual(activation.planIdentifier, "pro")
    XCTAssertEqual(activation.activationIdentifier, "activation-1")
    XCTAssertEqual(validation.planIdentifier, "pro")
  }

  func testValueStorageAndErrorAPIsAreUsableFromPublicImport() throws {
    let source = try XCTUnwrap(LicenseSource(identifier: " backend "))
    let activatedAt = Date()
    let expiresAt = activatedAt.addingTimeInterval(60)
    let activation = try XCTUnwrap(
      LicenseActivation(
        source: source,
        planIdentifier: " pro ",
        activatedAt: activatedAt,
        licenseKey: " KEY ",
        activationIdentifier: " instance ",
        expiresAt: expiresAt
      ))
    let plan = makePublicPlan(
      identifier: activation.planIdentifier,
      isLicensed: true,
      expiresAt: activation.expiresAt
    )
    let failure = LicenseRefreshFailure(
      reason: .serverFailure,
      message: " temporary ",
      statusCode: 503,
      occurredAt: activation.activatedAt
    )
    let state = LicenseState(
      plan: plan,
      activation: activation,
      isActivating: true,
      isRefreshing: true,
      lastValidatedAt: activation.activatedAt,
      status: .gracePeriod,
      gracePeriodExpiresAt: activation.expiresAt,
      lastRefreshFailure: failure
    )
    let refreshResult = LicenseRefreshResult(outcome: .invalid, state: state, failure: failure)
    let refreshPolicy = try LicenseRefreshPolicy(
      validationInterval: 60,
      failureGracePeriod: 30,
      serverFailureGracePeriod: 15
    )
    let activationRequest = LicenseActivationRequest.licenseKey("KEY")
    let providerError = LicenseProviderError.serverFailure(statusCode: 503)
    let policyError = LicenseRefreshPolicyError.invalidFailureGracePeriod
    let refreshOutcome = LicenseRefreshOutcome.refreshed
    let failureReason = LicenseRefreshFailureReason.serverFailure
    let status = LicenseStatus.active
    let licenseError = LicenseError.requestFailure(message: " timeout ")

    let encodedSource = try JSONEncoder().encode(source)
    XCTAssertEqual(
      try JSONDecoder().decode(LicenseSource.self, from: encodedSource),
      source
    )
    XCTAssertEqual(activation.licenseKey, "KEY")
    XCTAssertEqual(LicensePlan.unlicensed.identifier, "unlicensed")
    XCTAssertEqual(LicenseSource.unspecified.identifier, "unspecified")
    XCTAssertFalse(activation.isExpired(at: activatedAt))
    XCTAssertFalse(plan.isExpired)
    XCTAssertFalse(plan.isExpired(at: activatedAt))
    XCTAssertTrue(state.isLicensed)
    XCTAssertEqual(refreshResult.failure, failure)
    XCTAssertEqual(licenseError.message, "timeout")
    XCTAssertEqual(policyError, .invalidFailureGracePeriod)

    assertHashable(activation)
    assertHashable(plan)
    assertHashable(makePublicValidationResult(isValid: true, planIdentifier: "team"))
    assertHashable(failure)
    assertHashable(state)
    assertHashable(refreshResult)
    assertHashable(refreshPolicy)
    assertHashable(failureReason)
    assertHashable(refreshOutcome)
    assertHashable(status)
    assertHashable(licenseError)
    assertHashable(providerError)
    assertHashable(policyError)

    assertSendable(activation)
    assertSendable(plan)
    assertSendable(source)
    assertSendable(makePublicValidationResult(isValid: true, planIdentifier: "team"))
    assertSendable(failure)
    assertSendable(state)
    assertSendable(refreshResult)
    assertSendable(refreshPolicy)
    assertSendable(failureReason)
    assertSendable(refreshOutcome)
    assertSendable(status)
    assertSendable(activationRequest)
    assertSendable(licenseError)
    assertSendable(providerError)
    assertSendable(policyError)
  }

  func testConcretePersistenceImplementationsAreUsableFromPublicImport() {
    let activationStorage: any LicenseActivationStorage = KeychainLicenseActivationStorage(
      service: "LicenseKitPublicAPITests",
      account: "license",
      accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    )
    let metadataStorage: any LicenseStateMetadataStorage = UserDefaultsLicenseStateMetadataStorage(
      defaults: UserDefaults(suiteName: "LicenseKitPublicAPITests") ?? .standard,
      storageKey: "metadata"
    )

    withExtendedLifetime(activationStorage) {}
    withExtendedLifetime(metadataStorage) {}
  }

}

private func assertHashable<Value: Hashable>(_: Value) {}

private func assertSendable<Value: Sendable>(_: Value) {}

private func makePublicSource(_ identifier: String) -> LicenseSource {
  LicenseSource(identifier: identifier)!
}

private func makePublicPlan(
  identifier: String = "pro",
  isLicensed: Bool = true,
  expiresAt: Date? = nil
) -> LicensePlan {
  LicensePlan(identifier: identifier, isLicensed: isLicensed, expiresAt: expiresAt)!
}

private func makePublicValidationResult(
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

private struct MyActivationResponse: Sendable {
  let planIdentifier: String
  let activationIdentifier: String?
  let activatedAt: Date
  let expiresAt: Date?
}

private struct MyValidationResponse: Sendable {
  let isValid: Bool
  let planIdentifier: String?
  let expiresAt: Date?
}

private protocol MyLicenseAPI: Sendable {
  func activateLicenseKey(_ licenseKey: String) async throws -> MyActivationResponse
  func deactivate(activation: LicenseActivation) async throws
  func validate(
    activation: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> MyValidationResponse
}

private struct MyLicenseProvider<LicenseAPI: MyLicenseAPI>: LicenseProvider {
  let licenseAPI: LicenseAPI

  func activate(_ request: LicenseActivationRequest) async throws -> LicenseActivation {
    guard case .licenseKey(let licenseKey) = request else {
      throw LicenseProviderError.requestFailure(message: "License key is required.")
    }

    let response = try await licenseAPI.activateLicenseKey(licenseKey)
    guard
      let activation = LicenseActivation(
        source: makePublicSource("backend"),
        planIdentifier: response.planIdentifier,
        activatedAt: response.activatedAt,
        licenseKey: licenseKey,
        activationIdentifier: response.activationIdentifier,
        expiresAt: response.expiresAt
      )
    else {
      throw LicenseProviderError.requestFailure(
        message: "Activation response did not include a plan."
      )
    }
    return activation
  }

  func deactivate(_ activation: LicenseActivation) async throws {
    try await licenseAPI.deactivate(activation: activation)
  }

  func validate(
    _ activation: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    let response = try await licenseAPI.validate(
      activation: activation,
      validationIdentifier: validationIdentifier
    )
    guard
      let result = LicenseValidationResult(
        isValid: response.isValid,
        planIdentifier: response.planIdentifier,
        expiresAt: response.expiresAt
      )
    else {
      throw LicenseProviderError.requestFailure(
        message: "Validation response was not canonical."
      )
    }
    return result
  }
}

private struct TestLicenseAPI: MyLicenseAPI {
  func activateLicenseKey(_: String) async throws -> MyActivationResponse {
    MyActivationResponse(
      planIdentifier: "pro",
      activationIdentifier: "activation-1",
      activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: nil
    )
  }

  func deactivate(activation _: LicenseActivation) async throws {}

  func validate(
    activation _: LicenseActivation,
    validationIdentifier _: String?
  ) async throws -> MyValidationResponse {
    MyValidationResponse(isValid: true, planIdentifier: "pro", expiresAt: nil)
  }
}

private final class PublicActivationStorage: LicenseActivationStorage, @unchecked Sendable {
  private var activation: LicenseActivation?

  init(activation: LicenseActivation? = nil) {
    self.activation = activation
  }

  func save(_ activation: LicenseActivation) throws {
    self.activation = activation
  }

  func load() throws -> LicenseActivation? {
    activation
  }

  func delete() throws {
    activation = nil
  }
}

private final class PublicProvider: LicenseProvider, @unchecked Sendable {
  private let activation: LicenseActivation
  private(set) var activationRequest: LicenseActivationRequest?

  init(activation: LicenseActivation) {
    self.activation = activation
  }

  func activate(_ request: LicenseActivationRequest) async throws -> LicenseActivation {
    activationRequest = request
    return activation
  }

  func deactivate(_: LicenseActivation) async throws {}

  func validate(
    _: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    makePublicValidationResult(isValid: true)
  }
}
