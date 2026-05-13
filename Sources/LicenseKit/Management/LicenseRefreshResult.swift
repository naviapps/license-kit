public struct LicenseRefreshResult: Equatable, Sendable {
  public let outcome: LicenseRefreshOutcome
  public let state: LicenseState
  public let validationFailure: LicenseRefreshFailure?
  public let offeringLoadFailure: LicenseRefreshFailure?

  public init(
    outcome: LicenseRefreshOutcome,
    state: LicenseState,
    validationFailure: LicenseRefreshFailure? = nil,
    offeringLoadFailure: LicenseRefreshFailure? = nil
  ) {
    self.outcome = outcome
    self.state = state
    self.validationFailure = validationFailure
    self.offeringLoadFailure = offeringLoadFailure
  }
}
