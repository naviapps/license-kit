import XCTest

import LicenseKit

final class LicenseErrorTests: XCTestCase {
  func testErrorDescriptions() {
    let cases: [(LicenseError, String)] = [
      (.invalidLicenseKey, "invalid_license_key"),
      (.invalidLicense, "invalid_license"),
      (.expiredLicense, "expired_license"),
      (.activationLimitReached, "activation_limit_reached"),
      (
        .invalidProviderConfiguration,
        "invalid_provider_configuration"
      ),
      (.activationInProgress, "activation_in_progress"),
      (.refreshInProgress, "refresh_in_progress"),
      (.deactivationInProgress, "deactivation_in_progress"),
      (.unexpectedProviderResponse, "unexpected_provider_response"),
    ]

    for (error, description) in cases {
      XCTAssertEqual(error.description, description)
      XCTAssertEqual(error.errorDescription, description)
      XCTAssertNil(error.message)
      XCTAssertNil(error.statusCode)
    }
    let uniqueErrors =
      cases.map(\.0) + [
        LicenseError.serverFailure(statusCode: 404),
        LicenseError.requestFailure(message: "timeout"),
        LicenseError.storageFailure(message: "decode failed"),
      ]
    XCTAssertEqual(Set(uniqueErrors).count, uniqueErrors.count)

    XCTAssertEqual(
      LicenseError.serverFailure(statusCode: 404).description,
      "server_failure(404)"
    )
    XCTAssertEqual(
      LicenseError.serverFailure(statusCode: 404).errorDescription,
      "server_failure(404)"
    )
    XCTAssertEqual(LicenseError.serverFailure(statusCode: 404).statusCode, 404)
    XCTAssertEqual(
      LicenseError.requestFailure(message: "timeout").description,
      "request_failure(timeout)"
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: "timeout").errorDescription,
      "request_failure(timeout)"
    )
    XCTAssertEqual(LicenseError.requestFailure(message: "timeout").message, "timeout")
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t ").description,
      "request_failure(Request failed.)"
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t ").message,
      "Request failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").description,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").errorDescription,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "Storage operation failed.").message,
      "Storage operation failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "decode failed").description,
      "storage_failure(decode failed)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: "decode failed").errorDescription,
      "storage_failure(decode failed)"
    )
    XCTAssertEqual(LicenseError.storageFailure(message: "decode failed").message, "decode failed")
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t ").description,
      "storage_failure(Storage operation failed.)"
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t ").message,
      "Storage operation failed."
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: " \n\t "),
      .storageFailure(message: "Storage operation failed.")
    )
    XCTAssertEqual(
      LicenseError.storageFailure(message: " decode failed "),
      .storageFailure(message: "decode failed")
    )
    XCTAssertEqual(
      Set([
        LicenseError.storageFailure(message: " \n\t "),
        LicenseError.storageFailure(message: "Storage operation failed."),
        LicenseError.storageFailure(message: " Storage operation failed. "),
      ]).count,
      1
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: " \n\t "),
      .requestFailure(message: "Request failed.")
    )
    XCTAssertEqual(
      LicenseError.requestFailure(message: " timeout "),
      .requestFailure(message: "timeout")
    )
    XCTAssertEqual(
      Set([
        LicenseError.requestFailure(message: " \n\t "),
        LicenseError.requestFailure(message: "Request failed."),
        LicenseError.requestFailure(message: " Request failed. "),
      ]).count,
      1
    )
    XCTAssertNotEqual(
      LicenseError.storageFailure(message: "Storage operation failed."),
      .requestFailure(message: "Storage operation failed.")
    )
  }

  func testProviderErrorDescriptions() {
    let cases: [(LicenseProviderError, String)] = [
      (.invalidConfiguration, "invalid_configuration"),
      (.transportFailure(message: "offline"), "transport_failure(offline)"),
      (.transportFailure(message: " \n\t "), "transport_failure(Transport failed.)"),
      (.responseDecodingFailure, "response_decoding_failure"),
      (.invalidLicense, "invalid_license"),
      (.activationLimitReached, "activation_limit_reached"),
      (.requestFailure(message: "bad request"), "request_failure(bad request)"),
      (.requestFailure(message: " \n\t "), "request_failure(Request failed.)"),
      (.serverFailure(statusCode: 503), "server_failure(503)"),
    ]

    for (error, description) in cases {
      XCTAssertEqual(error.description, description)
      XCTAssertEqual(error.errorDescription, description)
    }

    XCTAssertEqual(
      LicenseProviderError.transportFailure(message: " offline "),
      .transportFailure(message: "offline")
    )
    XCTAssertEqual(
      LicenseProviderError.requestFailure(message: " \n\t "),
      .requestFailure(message: "Request failed.")
    )
    XCTAssertEqual(
      Set([
        LicenseProviderError.transportFailure(message: " \n\t "),
        LicenseProviderError.transportFailure(message: "Transport failed."),
        LicenseProviderError.transportFailure(message: " Transport failed. "),
      ]).count,
      1
    )
  }

}
