import Foundation

/// Errors thrown by ``LicenseProvider`` implementations for provider failures or rejections.
public enum LicenseProviderError: Error, Equatable, Hashable, Sendable {
  /// The provider cannot run because its local configuration is invalid.
  case invalidConfiguration

  /// The provider request could not reach the provider or transport layer.
  case transportFailure(message: String)

  /// The provider returned a response that could not be decoded or mapped.
  case responseDecodingFailure

  /// The provider definitively rejected the license.
  case invalidLicense

  /// The provider rejected activation because the activation limit was reached.
  case activationLimitReached

  /// The provider completed the request but rejected it for a non-license-specific reason.
  case requestFailure(message: String)

  /// The provider returned a server failure status.
  case serverFailure(statusCode: Int)
}

extension LicenseProviderError {
  static let defaultRequestFailureMessage = "Request failed."
  static let defaultTransportFailureMessage = "Transport failed."

  var normalizedMessage: String? {
    switch self {
    case .requestFailure(let message):
      message.licenseKitTrimmedNonEmpty ?? Self.defaultRequestFailureMessage
    case .transportFailure(let message):
      message.licenseKitTrimmedNonEmpty ?? Self.defaultTransportFailureMessage
    default:
      nil
    }
  }

  /// Returns whether two provider errors represent the same normalized failure.
  public static func == (lhs: LicenseProviderError, rhs: LicenseProviderError) -> Bool {
    lhs.identity == rhs.identity
  }

  /// Hashes the same normalized failure identity used by ``==(_:_:)``.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(identity)
  }

  private var identity: NormalizedIdentity {
    switch self {
    case .invalidConfiguration:
      .invalidConfiguration
    case .transportFailure:
      .transportFailure(message: normalizedMessage ?? Self.defaultTransportFailureMessage)
    case .responseDecodingFailure:
      .responseDecodingFailure
    case .invalidLicense:
      .invalidLicense
    case .activationLimitReached:
      .activationLimitReached
    case .requestFailure:
      .requestFailure(message: normalizedMessage ?? Self.defaultRequestFailureMessage)
    case .serverFailure(let statusCode):
      .serverFailure(statusCode: statusCode)
    }
  }

  private enum NormalizedIdentity: Hashable {
    case invalidConfiguration
    case transportFailure(message: String)
    case responseDecodingFailure
    case invalidLicense
    case activationLimitReached
    case requestFailure(message: String)
    case serverFailure(statusCode: Int)
  }
}

extension LicenseProviderError: CustomStringConvertible {
  /// A canonical textual description of the provider error.
  public var description: String {
    switch self {
    case .invalidConfiguration:
      "invalid_configuration"
    case .transportFailure:
      "transport_failure(\(normalizedMessage ?? Self.defaultTransportFailureMessage))"
    case .responseDecodingFailure:
      "response_decoding_failure"
    case .invalidLicense:
      "invalid_license"
    case .activationLimitReached:
      "activation_limit_reached"
    case .requestFailure:
      "request_failure(\(normalizedMessage ?? Self.defaultRequestFailureMessage))"
    case .serverFailure(let statusCode):
      "server_failure(\(statusCode))"
    }
  }
}

extension LicenseProviderError: LocalizedError {
  /// A localized error description backed by ``description``.
  public var errorDescription: String? {
    description
  }
}
