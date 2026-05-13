import Foundation

public struct LicenseState: Equatable, Sendable {
  public let plan: LicensePlan
  public let activation: LicenseActivation?
  public let isRefreshing: Bool
  public let offerings: [LicenseOffering]
  public let lastValidatedAt: Date?
  public let status: LicenseStatus
  public let gracePeriodExpiresAt: Date?
  public let lastRefreshFailure: LicenseRefreshFailure?

  public var source: LicenseSource? {
    activation?.source
  }

  public var isLicensed: Bool {
    status.isLicensed
  }

  public init(
    plan: LicensePlan = .unlicensed,
    activation: LicenseActivation? = nil,
    isRefreshing: Bool = false,
    offerings: [LicenseOffering] = [],
    lastValidatedAt: Date? = nil,
    status: LicenseStatus = .unlicensed,
    gracePeriodExpiresAt: Date? = nil,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    self.plan = plan
    self.activation = activation
    self.isRefreshing = isRefreshing
    self.offerings = offerings
    self.lastValidatedAt = lastValidatedAt
    self.status = status
    self.gracePeriodExpiresAt = gracePeriodExpiresAt
    self.lastRefreshFailure = lastRefreshFailure
  }
}
