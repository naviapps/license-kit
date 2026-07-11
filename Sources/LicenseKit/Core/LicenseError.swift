import Foundation

/// Errors thrown by LicenseKit state and provider coordination.
public enum LicenseError: Error, Equatable, Hashable, Sendable {
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

  /// A deactivation operation is already running.
  case deactivationInProgress

  /// The provider reported a server-side failure.
  case serverFailure(statusCode: Int)

  /// The provider returned an unexpected response shape.
  case unexpectedProviderResponse

  /// A provider or network request failed without a definitive license result.
  case requestFailure(message: String)

  /// The normalized diagnostic message attached to message-bearing errors.
  public var message: String? {
    switch self {
    case .storageFailure(let message):
      Self.normalizedStorageFailureMessage(message)
    case .requestFailure(let message):
      Self.normalizedRequestFailureMessage(message)
    default:
      nil
    }
  }

  /// The server status code attached to server failures.
  public var statusCode: Int? {
    if case .serverFailure(let statusCode) = self { return statusCode }
    return nil
  }
}

extension LicenseError {
  /// Returns whether two license errors represent the same normalized failure.
  public static func == (lhs: LicenseError, rhs: LicenseError) -> Bool {
    lhs.identity == rhs.identity
  }

  /// Hashes the same normalized failure identity used by ``==(_:_:)``.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(identity)
  }

  private var identity: NormalizedIdentity {
    switch self {
    case .invalidLicenseKey:
      .invalidLicenseKey
    case .storageFailure(let message):
      .storageFailure(message: Self.normalizedStorageFailureMessage(message))
    case .invalidLicense:
      .invalidLicense
    case .expiredLicense:
      .expiredLicense
    case .activationLimitReached:
      .activationLimitReached
    case .invalidProviderConfiguration:
      .invalidProviderConfiguration
    case .activationInProgress:
      .activationInProgress
    case .refreshInProgress:
      .refreshInProgress
    case .deactivationInProgress:
      .deactivationInProgress
    case .serverFailure(let statusCode):
      .serverFailure(statusCode: statusCode)
    case .unexpectedProviderResponse:
      .unexpectedProviderResponse
    case .requestFailure(let message):
      .requestFailure(message: Self.normalizedRequestFailureMessage(message))
    }
  }

  private enum NormalizedIdentity: Hashable {
    case invalidLicenseKey
    case storageFailure(message: String)
    case invalidLicense
    case expiredLicense
    case activationLimitReached
    case invalidProviderConfiguration
    case activationInProgress
    case refreshInProgress
    case deactivationInProgress
    case serverFailure(statusCode: Int)
    case unexpectedProviderResponse
    case requestFailure(message: String)
  }
}

extension LicenseError: CustomStringConvertible {
  /// A canonical textual description of the error.
  public var description: String {
    switch self {
    case .serverFailure(let statusCode):
      "server_failure(\(statusCode))"
    case .requestFailure(let message):
      "request_failure(\(Self.normalizedRequestFailureMessage(message)))"
    case .invalidLicenseKey:
      "invalid_license_key"
    case .storageFailure(let message):
      "storage_failure(\(Self.normalizedStorageFailureMessage(message)))"
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
    case .deactivationInProgress:
      "deactivation_in_progress"
    case .unexpectedProviderResponse:
      "unexpected_provider_response"
    }
  }
}

extension LicenseError: LocalizedError {
  /// A diagnostic error description backed by ``description``.
  public var errorDescription: String? {
    description
  }
}

extension LicenseError {
  private static let defaultStorageFailureMessage = "Storage operation failed."
  private static let defaultRequestFailureMessage = "Request failed."

  private static func normalizedStorageFailureMessage(_ message: String) -> String {
    message.licenseKitTrimmedNonEmpty ?? defaultStorageFailureMessage
  }

  private static func normalizedRequestFailureMessage(_ message: String) -> String {
    message.licenseKitTrimmedNonEmpty ?? defaultRequestFailureMessage
  }

  static func storageFailure(normalizing error: Error) -> LicenseError {
    if let licenseError = error as? LicenseError, case .storageFailure = licenseError {
      return licenseError
    }
    return .storageFailure(message: defaultStorageFailureMessage)
  }

  static func requestFailure(normalizing message: String?) -> LicenseError {
    .requestFailure(
      message: message.map(normalizedRequestFailureMessage) ?? defaultRequestFailureMessage
    )
  }
}
