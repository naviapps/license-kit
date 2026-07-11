import XCTest

import LicenseKit

@MainActor
final class LicenseManagerRefreshConcurrencyTests: XCTestCase {
  func testRefreshIsGuardedAgainstMultipleConcurrentRuns() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.validationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage(activation: activation)
    )

    async let first = manager.refresh()
    async let second = manager.refresh()
    let results = try await [first, second]

    XCTAssertFalse(manager.isRefreshing)
    XCTAssertEqual(provider.validationCount, 1)
    XCTAssertTrue(results.contains { $0.outcome == .refreshed })
    XCTAssertTrue(results.contains { $0.outcome == .skippedRefreshInProgress })
  }

  func testRefreshSkipsConcurrentActivation() async throws {
    let activation = makeActivation()
    let provider = TestProvider(activation: activation)
    provider.activationDelayNanoseconds = 50_000_000
    let manager = LicenseManager(
      provider: provider,
      activationStorage: TestActivationStorage()
    )

    async let activationState: LicenseState = manager.activate(.licenseKey("KEY"))
    try await waitForManagerState { manager.isActivating }

    let result = try await manager.refresh()

    XCTAssertEqual(result.outcome, .skippedActivationInProgress)
    XCTAssertTrue(manager.isActivating)
    _ = try await activationState
    XCTAssertFalse(manager.isActivating)
  }

}
