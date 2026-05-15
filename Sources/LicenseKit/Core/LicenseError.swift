import Foundation

public enum LicenseError: Error, Equatable, Sendable {
  /// The provided license key is empty after normalization.
  case invalidLicenseKey

  /// Activation or state persistence failed.
  case storageFailure(message: String)

  /// The provider definitively rejected the license.
  case invalidLicense

  /// The activation or entitlement is expired.
  case expiredLicense

  /// The provider rejected activation because the activation limit was reached.
  case activationLimitReached

  /// The provider is configured incorrectly.
  case invalidProviderConfiguration

  /// An activation operation is already running.
  case activationInProgress

  /// A refresh operation is already running.
  case refreshInProgress

  /// The provider reported a server-side failure.
  case serverFailure(statusCode: Int)

  /// The provider returned an unexpected response shape.
  case unexpectedProviderResponse

  /// A non-storage request failed.
  case requestFailure(message: String)

  public var message: String? {
    if case .storageFailure(let message) = self {
      return message.licenseKitTrimmedNonEmpty ?? Self.defaultStorageFailureMessage
    }
    if case .requestFailure(let message) = self {
      return message.licenseKitTrimmedNonEmpty ?? Self.defaultRequestFailureMessage
    }
    return nil
  }

  public var statusCode: Int? {
    if case .serverFailure(let statusCode) = self { return statusCode }
    return nil
  }
}

extension LicenseError {
  public static func == (lhs: LicenseError, rhs: LicenseError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidLicenseKey, .invalidLicenseKey),
      (.invalidLicense, .invalidLicense),
      (.expiredLicense, .expiredLicense),
      (.activationLimitReached, .activationLimitReached),
      (.invalidProviderConfiguration, .invalidProviderConfiguration),
      (.activationInProgress, .activationInProgress),
      (.refreshInProgress, .refreshInProgress),
      (.unexpectedProviderResponse, .unexpectedProviderResponse):
      true
    case (.storageFailure, .storageFailure),
      (.requestFailure, .requestFailure):
      lhs.message == rhs.message
    case (.serverFailure, .serverFailure):
      lhs.statusCode == rhs.statusCode
    default:
      false
    }
  }
}

extension LicenseError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .serverFailure(let statusCode):
      "server_failure(\(statusCode))"
    case .requestFailure:
      "request_failure(\(message ?? Self.defaultRequestFailureMessage))"
    case .invalidLicenseKey:
      "invalid_license_key"
    case .storageFailure:
      "storage_failure(\(message ?? Self.defaultStorageFailureMessage))"
    case .invalidLicense:
      "invalid_license"
    case .expiredLicense:
      "expired_license"
    case .activationLimitReached:
      "activation_limit_reached"
    case .invalidProviderConfiguration:
      "invalid_provider_configuration"
    case .activationInProgress:
      "activation_in_progress"
    case .refreshInProgress:
      "refresh_in_progress"
    case .unexpectedProviderResponse:
      "unexpected_provider_response"
    }
  }
}

extension LicenseError: LocalizedError {
  public var errorDescription: String? {
    description
  }
}

extension LicenseError {
  static let defaultStorageFailureMessage = "Storage operation failed."
  static let defaultRequestFailureMessage = "Request failed."

  static func storageFailure(_ error: Error) -> LicenseError {
    if let licenseError = error as? LicenseError, case .storageFailure = licenseError {
      return licenseError
    }
    return .storageFailure(
      message: String(describing: error).licenseKitTrimmedNonEmpty ?? defaultStorageFailureMessage
    )
  }
}
