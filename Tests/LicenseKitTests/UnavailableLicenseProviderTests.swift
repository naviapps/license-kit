import XCTest

@testable import LicenseKit

final class UnavailableLicenseProviderTests: XCTestCase {
  func testUnavailableProviderThrowsRequestFailureForEveryOperation() async {
    let provider = UnavailableLicenseProvider(message: "missing")

    await assertRequestFailure(message: "missing") {
      _ = try await provider.activate(.licenseKey("KEY"))
    }
    await assertRequestFailure(message: "missing") {
      _ = try await provider.activate(.automatic)
    }
    await assertRequestFailure(message: "missing") {
      try await provider.deactivate(makeActivation())
    }
    await assertRequestFailure(message: "missing") {
      _ = try await provider.validate(makeActivation(), validationIdentifier: nil)
    }
  }

  func testUnavailableProviderUsesDefaultMessage() async {
    let provider = UnavailableLicenseProvider()

    await assertRequestFailure(message: "License provider is unavailable.") {
      _ = try await provider.activate(.licenseKey("KEY"))
    }
  }

  func testUnavailableProviderNormalizesBlankMessage() async {
    let provider = UnavailableLicenseProvider(message: " \n ")

    await assertRequestFailure(message: "License provider is unavailable.") {
      _ = try await provider.activate(.licenseKey("KEY"))
    }
  }

  func testUnavailableProviderTrimsMessage() async {
    let provider = UnavailableLicenseProvider(message: "  missing  ")

    await assertRequestFailure(message: "missing") {
      _ = try await provider.activate(.licenseKey("KEY"))
    }
  }

  private func assertRequestFailure(
    message expectedMessage: String,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      XCTFail("Expected requestFailure")
    } catch LicenseProviderError.requestFailure(let message) {
      XCTAssertEqual(message, expectedMessage)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
