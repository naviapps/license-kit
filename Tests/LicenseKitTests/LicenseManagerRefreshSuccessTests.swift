import XCTest

import LicenseKit

@MainActor
final class LicenseManagerRefreshSuccessTests: XCTestCase {
  func testRefreshUsesConfiguredValidationIdentifierWhenActivationIdentifierIsMissing()
    async throws
  {
    let activation = makeActivation(activationIdentifier: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      validationIdentifierProvider: { " validation-1 " }
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "validation-1")
  }

  func testRefreshPrefersActivationIdentifierOverConfiguredValidationIdentifier() async throws {
    let activation = makeActivation(activationIdentifier: "activation-1")
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      validationIdentifierProvider: { "validation-1" }
    )

    _ = try await manager.refresh()

    XCTAssertEqual(provider.lastValidationIdentifier, "activation-1")
  }

  func testRefreshPassesNilWhenValidationIdentifierIsUnavailable() async throws {
    let activation = makeActivation(activationIdentifier: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    _ = try await manager.refresh()

    XCTAssertNil(provider.lastValidationIdentifier)
  }

  func testRefreshPassesNilWhenConfiguredValidationIdentifierIsBlank() async throws {
    let activation = makeActivation(activationIdentifier: nil)
    let provider = TestProvider(activation: activation)
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation),
      validationIdentifierProvider: { " \n\t " }
    )

    _ = try await manager.refresh()

    XCTAssertNil(provider.lastValidationIdentifier)
  }

  func testRefreshCanUpdatePlanFromValidationResult() async throws {
    let activation = makeActivation(planIdentifier: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(
      isValid: true,
      planIdentifier: " team "
    )
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertTrue(result.state.isLicensed)
    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.plan.identifier, "team")
    XCTAssertEqual(manager.activation?.planIdentifier, "team")
    XCTAssertEqual(provider.lastValidatedActivation, activation)
    XCTAssertEqual(activationStorage.activation?.planIdentifier, "team")
  }

  func testRefreshActivationSaveFailurePreservesExistingState() async throws {
    let activation = makeActivation(planIdentifier: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(isValid: true, planIdentifier: "team")
    let activationStorage = TestActivationStorage(activation: activation)
    activationStorage.saveError = TestUnexpectedError(message: "keychain unavailable")
    let stateMetadataStorage = TestStateMetadataStorage(state: makeState(activation: activation))
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    do {
      try await manager.refresh()
      XCTFail("Expected storage failure")
    } catch let error as LicenseError {
      XCTAssertEqual(error, .storageFailure(message: "Storage operation failed."))
      XCTAssertEqual(manager.status, .active)
      XCTAssertEqual(manager.activation, activation)
      XCTAssertEqual(manager.plan.identifier, "pro")
      XCTAssertEqual(activationStorage.activation, activation)
      XCTAssertNotNil(stateMetadataStorage.metadata)
    }
  }

  func testRefreshSuccessIgnoresStateMetadataStorageSaveFailure() async throws {
    let activation = makeActivation(planIdentifier: "pro")
    let provider = TestProvider(activation: activation)
    provider.validationResult = makeValidationResult(isValid: true, planIdentifier: "team")
    let activationStorage = TestActivationStorage(activation: activation)
    let stateMetadataStorage = TestStateMetadataStorage()
    stateMetadataStorage.saveError = TestUnexpectedError(message: "defaults unavailable")
    let manager = LicenseManager(
      provider: provider,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    )

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertEqual(manager.status, .active)
    XCTAssertEqual(manager.plan.identifier, "team")
    XCTAssertEqual(activationStorage.activation?.planIdentifier, "team")
    XCTAssertNil(stateMetadataStorage.metadata)
  }

  func testRefreshSuccessRecordsValidationCompletionTime() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    let refreshStartedAt = Date()
    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .refreshed)
    XCTAssertGreaterThanOrEqual(
      manager.lastValidatedAt ?? .distantPast,
      refreshStartedAt.addingTimeInterval(0.03)
    )
  }

}
