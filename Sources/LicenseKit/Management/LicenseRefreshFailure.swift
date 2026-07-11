import Foundation

/// Details about a refresh failure.
public struct LicenseRefreshFailure: Codable, Equatable, Hashable, Sendable {
  /// The normalized failure reason.
  public let reason: LicenseRefreshFailureReason

  /// A normalized diagnostic message, when available.
  public let message: String?

  /// The server status code for server failures.
  public let statusCode: Int?

  /// The time the failure occurred.
  public let occurredAt: Date

  private enum CodingKeys: String, CodingKey {
    case reason
    case message
    case statusCode
    case occurredAt
  }

  /// Creates a normalized refresh failure.
  public init(
    reason: LicenseRefreshFailureReason,
    message: String? = nil,
    statusCode: Int? = nil,
    occurredAt: Date
  ) {
    self.reason = reason
    self.message = message?.licenseKitTrimmedNonEmpty
    self.statusCode = reason == .serverFailure ? statusCode : nil
    self.occurredAt = occurredAt
  }

  /// Decodes a normalized refresh failure.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      reason: try container.decode(LicenseRefreshFailureReason.self, forKey: .reason),
      message: try container.decodeIfPresent(String.self, forKey: .message),
      statusCode: try container.decodeIfPresent(Int.self, forKey: .statusCode),
      occurredAt: try container.decode(Date.self, forKey: .occurredAt)
    )
  }

  init(error: LicenseProviderError, occurredAt: Date) {
    switch error {
    case .invalidLicense:
      self.init(reason: .invalidLicense, occurredAt: occurredAt)
    case .activationLimitReached:
      self.init(reason: .activationLimitReached, occurredAt: occurredAt)
    case .invalidConfiguration:
      self.init(reason: .invalidProviderConfiguration, occurredAt: occurredAt)
    case .responseDecodingFailure:
      self.init(reason: .unexpectedProviderResponse, occurredAt: occurredAt)
    case .transportFailure:
      self.init(reason: .transportFailure, message: error.normalizedMessage, occurredAt: occurredAt)
    case .serverFailure(let statusCode):
      self.init(reason: .serverFailure, statusCode: statusCode, occurredAt: occurredAt)
    case .requestFailure:
      self.init(reason: .requestFailure, message: error.normalizedMessage, occurredAt: occurredAt)
    }
  }
}

/// Normalized refresh failure reasons.
public enum LicenseRefreshFailureReason: String, Codable, Equatable, Hashable, CaseIterable,
  Sendable
{
  /// The provider definitively rejected the license.
  case invalidLicense

  /// The provider rejected the activation because an activation limit was reached.
  case activationLimitReached

  /// The provider could not validate because its local configuration is invalid.
  case invalidProviderConfiguration

  /// The provider returned a response that could not be decoded or mapped.
  case unexpectedProviderResponse

  /// The validation request could not reach the provider or transport layer.
  case transportFailure

  /// The provider returned a server failure status.
  case serverFailure

  /// The provider completed the request but rejected it for a non-license-specific reason.
  case requestFailure

  /// The local grace period expired before validation recovered.
  case gracePeriodExpired
}
