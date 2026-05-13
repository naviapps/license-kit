public enum LicenseRefreshOutcome: String, Codable, Equatable, Sendable {
  case refreshed
  case gracePeriod
  case invalid
  case expired
  case skippedActivationInProgress
  case skippedRefreshDisabled
  case skippedRefreshInProgress
  case skippedNoActivation
}
