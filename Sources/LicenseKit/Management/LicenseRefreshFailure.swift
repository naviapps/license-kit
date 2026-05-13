import Foundation

public struct LicenseRefreshFailure: Codable, Equatable, Sendable {
  public let reason: LicenseRefreshFailureReason
  public let message: String?
  public let statusCode: Int?
  public let occurredAt: Date

  private enum CodingKeys: String, CodingKey {
    case reason
    case message
    case statusCode
    case occurredAt
  }

  public init(
    reason: LicenseRefreshFailureReason,
    message: String? = nil,
    statusCode: Int? = nil,
    occurredAt: Date
  ) {
    self.reason = reason
    self.message = message?.licenseKitTrimmedNonEmpty
    self.statusCode = statusCode
    self.occurredAt = occurredAt
  }

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
    case .invalidProviderURL:
      self.init(reason: .invalidProviderURL, occurredAt: occurredAt)
    case .responseDecodingFailure:
      self.init(reason: .unexpectedProviderResponse, occurredAt: occurredAt)
    case .networkFailure(let message):
      self.init(reason: .networkFailure, message: message, occurredAt: occurredAt)
    case .serverFailure(let statusCode):
      self.init(reason: .providerServerFailure, statusCode: statusCode, occurredAt: occurredAt)
    case .requestFailure(let message):
      self.init(reason: .providerRequestFailure, message: message, occurredAt: occurredAt)
    }
  }
}
