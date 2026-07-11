/// The high-level result category for a refresh attempt.
public enum LicenseRefreshOutcome: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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

  /// Refresh was skipped because deactivation is currently running.
  case skippedDeactivationInProgress

  /// Refresh was skipped because there is no activation to validate.
  case skippedNoActivation
}

/// The result of a refresh attempt.
public struct LicenseRefreshResult: Equatable, Hashable, Sendable {
  /// The high-level refresh outcome.
  public let outcome: LicenseRefreshOutcome

  /// The license state after the refresh attempt.
  public let state: LicenseState

  /// The refresh failure that caused a grace-period or invalid outcome, when available.
  public let failure: LicenseRefreshFailure?

  /// Creates a refresh result.
  public init(
    outcome: LicenseRefreshOutcome,
    state: LicenseState,
    failure: LicenseRefreshFailure? = nil
  ) {
    self.outcome = outcome
    self.state = state
    self.failure =
      outcome == .gracePeriod || outcome == .invalid
      ? failure
      : nil
  }
}
