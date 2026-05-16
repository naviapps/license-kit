import Foundation

/// A provider-neutral contract for activating, validating, and deactivating licenses.
public protocol LicenseProvider: Sendable {
  /// Activates a license from a provider-neutral request and returns the resolved activation.
  func activate(_ request: LicenseActivationRequest) async throws -> LicenseActivation

  /// Deactivates the current activation with the provider.
  func deactivate(_ activation: LicenseActivation) async throws

  /// Validates an activation and returns the provider's completed validation result.
  func validate(_ activation: LicenseActivation, validationIdentifier: String?) async throws
    -> LicenseValidationResult
}

/// Errors thrown by ``LicenseProvider`` implementations for provider failures or rejections.
public enum LicenseProviderError: Error, Equatable, Sendable {
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
}

extension LicenseProviderError: CustomStringConvertible {
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
  public var errorDescription: String? {
    description
  }
}

/// A placeholder provider that fails every operation with a request failure.
public struct UnavailableLicenseProvider: LicenseProvider, Sendable {
  private static let defaultMessage = "License provider is unavailable."

  private let message: String

  /// Creates an unavailable provider with the message used for every failure.
  public init(message: String = "License provider is unavailable.") {
    self.message = message.licenseKitTrimmedNonEmpty ?? Self.defaultMessage
  }

  /// Always throws ``LicenseProviderError/requestFailure(message:)``.
  public func activate(_: LicenseActivationRequest) async throws -> LicenseActivation {
    throw LicenseProviderError.requestFailure(message: message)
  }

  /// Always throws ``LicenseProviderError/requestFailure(message:)``.
  public func deactivate(_: LicenseActivation) async throws {
    throw LicenseProviderError.requestFailure(message: message)
  }

  /// Always throws ``LicenseProviderError/requestFailure(message:)``.
  public func validate(
    _: LicenseActivation,
    validationIdentifier _: String?
  ) async throws -> LicenseValidationResult {
    throw LicenseProviderError.requestFailure(message: message)
  }
}
