import Foundation

/// Controls when provider validation runs and how refresh failures are handled.
public struct LicenseRefreshPolicy: Equatable, Hashable, Sendable {
  /// Whether provider refreshes are enabled.
  public let isEnabled: Bool

  /// The minimum interval between successful validations.
  public let validationInterval: TimeInterval

  /// The grace period used for recoverable provider failures.
  ///
  /// A zero value disables temporary grace for recoverable provider failures.
  public let failureGracePeriod: TimeInterval

  /// The grace period used for provider server failures.
  ///
  /// A zero value disables temporary grace for server failures.
  public let serverFailureGracePeriod: TimeInterval

  /// Creates an enabled refresh policy with validated intervals.
  public init(
    validationInterval: TimeInterval,
    failureGracePeriod: TimeInterval,
    serverFailureGracePeriod: TimeInterval
  ) throws {
    guard Self.isValidInterval(validationInterval) else {
      throw LicenseRefreshPolicyError.invalidValidationInterval
    }
    guard Self.isValidInterval(failureGracePeriod) else {
      throw LicenseRefreshPolicyError.invalidFailureGracePeriod
    }
    guard Self.isValidInterval(serverFailureGracePeriod) else {
      throw LicenseRefreshPolicyError.invalidServerFailureGracePeriod
    }
    self.init(
      isEnabled: true,
      validationInterval: validationInterval,
      failureGracePeriod: failureGracePeriod,
      serverFailureGracePeriod: serverFailureGracePeriod
    )
  }

  private static func isValidInterval(_ interval: TimeInterval) -> Bool {
    interval.isFinite && interval >= 0
  }

  private init(
    isEnabled: Bool,
    validationInterval: TimeInterval,
    failureGracePeriod: TimeInterval,
    serverFailureGracePeriod: TimeInterval
  ) {
    self.isEnabled = isEnabled
    self.validationInterval = validationInterval
    self.failureGracePeriod = failureGracePeriod
    self.serverFailureGracePeriod = serverFailureGracePeriod
  }

  /// A conservative refresh policy suitable for most direct-license apps.
  public static let `default` = LicenseRefreshPolicy(
    isEnabled: true,
    validationInterval: 24 * 60 * 60,
    failureGracePeriod: 7 * 24 * 60 * 60,
    serverFailureGracePeriod: 24 * 60 * 60
  )

  /// A policy that disables provider refresh while still allowing local expiration checks.
  public static let never = LicenseRefreshPolicy(
    isEnabled: false,
    validationInterval: 0,
    failureGracePeriod: 0,
    serverFailureGracePeriod: 0
  )
}

/// Validation errors thrown while creating a refresh policy.
public enum LicenseRefreshPolicyError: Error, Equatable, Hashable, Sendable {
  /// The validation interval was negative, infinite, or NaN.
  case invalidValidationInterval

  /// The failure grace period was negative, infinite, or NaN.
  case invalidFailureGracePeriod

  /// The server failure grace period was negative, infinite, or NaN.
  case invalidServerFailureGracePeriod
}

extension LicenseRefreshPolicyError: CustomStringConvertible {
  /// A canonical textual description of the refresh policy error.
  public var description: String {
    switch self {
    case .invalidValidationInterval:
      "invalid_validation_interval"
    case .invalidFailureGracePeriod:
      "invalid_failure_grace_period"
    case .invalidServerFailureGracePeriod:
      "invalid_server_failure_grace_period"
    }
  }
}

extension LicenseRefreshPolicyError: LocalizedError {
  /// A localized error description backed by ``description``.
  public var errorDescription: String? {
    description
  }
}
