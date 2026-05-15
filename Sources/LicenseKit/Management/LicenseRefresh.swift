import Foundation

/// The result of a refresh attempt.
public struct LicenseRefreshResult: Equatable, Sendable {
  /// The high-level refresh outcome.
  public let outcome: LicenseRefreshOutcome

  /// The license state after the refresh attempt.
  public let state: LicenseState

  /// The validation failure that caused a grace-period or invalid outcome, when available.
  public let validationFailure: LicenseRefreshFailure?

  public init(
    outcome: LicenseRefreshOutcome,
    state: LicenseState,
    validationFailure: LicenseRefreshFailure? = nil
  ) {
    self.outcome = outcome
    self.state = state
    self.validationFailure =
      outcome == .gracePeriod || outcome == .invalid
      ? validationFailure
      : nil
  }
}

/// The high-level result category for a refresh attempt.
public enum LicenseRefreshOutcome: String, Codable, Equatable, Sendable {
  /// Validation completed and the activation remains active.
  case refreshed

  /// Validation could not be completed and the activation remains usable temporarily.
  case gracePeriod

  /// Validation completed or grace expired and the activation is no longer usable.
  case invalid

  /// The activation or validation result has expired.
  case expired

  /// Refresh was skipped because activation is currently running.
  case skippedActivationInProgress

  /// Refresh was skipped because the refresh policy disables provider refreshes.
  case skippedRefreshDisabled

  /// Refresh was skipped because another refresh is currently running.
  case skippedRefreshInProgress

  /// Refresh was skipped because there is no activation to validate.
  case skippedNoActivation
}

/// Details about a refresh validation failure.
public struct LicenseRefreshFailure: Codable, Equatable, Sendable {
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
    case .transportFailure(let message):
      self.init(reason: .transportFailure, message: message, occurredAt: occurredAt)
    case .serverFailure(let statusCode):
      self.init(reason: .serverFailure, statusCode: statusCode, occurredAt: occurredAt)
    case .requestFailure(let message):
      self.init(reason: .requestFailure, message: message, occurredAt: occurredAt)
    }
  }
}

/// Normalized refresh validation failure reasons.
public enum LicenseRefreshFailureReason: String, Codable, Equatable, Sendable {
  case invalidLicense
  case activationLimitReached
  case invalidProviderConfiguration
  case unexpectedProviderResponse
  case transportFailure
  case serverFailure
  case requestFailure
}
