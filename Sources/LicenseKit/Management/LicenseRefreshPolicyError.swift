public enum LicenseRefreshPolicyError: Error, Equatable, Sendable {
  case invalidValidationInterval
  case invalidRecoverableFailureGracePeriod
  case invalidServerFailureGracePeriod
}

extension LicenseRefreshPolicyError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidValidationInterval:
      "invalid_validation_interval"
    case .invalidRecoverableFailureGracePeriod:
      "invalid_recoverable_failure_grace_period"
    case .invalidServerFailureGracePeriod:
      "invalid_server_failure_grace_period"
    }
  }
}
