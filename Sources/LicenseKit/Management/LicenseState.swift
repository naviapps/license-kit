import Foundation

/// The current high-level license state.
public enum LicenseStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
  /// No activation is currently available.
  case unlicensed

  /// A locally usable activation is available.
  case active

  /// A locally usable activation is available during a refresh failure grace period.
  case gracePeriod

  /// The activation or resolved plan has expired.
  case expired

  /// The provider rejected or invalidated the activation.
  case invalid

  /// The activation was explicitly deactivated.
  case deactivated

  /// Whether this status should unlock licensed functionality.
  public var isLicensed: Bool {
    self == .active || self == .gracePeriod
  }
}

/// The app-facing snapshot of license state managed by ``LicenseManager``.
public struct LicenseState: Equatable, Hashable, Sendable {
  /// The resolved plan for the current state.
  public let plan: LicensePlan

  /// The current activation when the state is locally licensed.
  public let activation: LicenseActivation?

  /// Whether an activation operation is currently running.
  public let isActivating: Bool

  /// Whether a refresh operation is currently running.
  public let isRefreshing: Bool

  /// Whether a deactivation operation is currently running.
  public let isDeactivating: Bool

  /// The last activation or validation decision time.
  public let lastValidatedAt: Date?

  /// The current high-level license status.
  public let status: LicenseStatus

  /// The time the current grace period stops being locally usable.
  public let gracePeriodExpiresAt: Date?

  /// The last refresh failure retained for grace, invalid, or expired states.
  public let lastRefreshFailure: LicenseRefreshFailure?

  /// The source that supplied the current activation.
  public var source: LicenseSource? {
    activation?.source
  }

  /// Whether the current state should unlock licensed functionality.
  public var isLicensed: Bool {
    status.isLicensed
  }

  /// Creates a normalized license state.
  public init(
    plan: LicensePlan = .unlicensed,
    activation: LicenseActivation? = nil,
    isActivating: Bool = false,
    isRefreshing: Bool = false,
    isDeactivating: Bool = false,
    lastValidatedAt: Date? = nil,
    status: LicenseStatus = .unlicensed,
    gracePeriodExpiresAt: Date? = nil,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    let resolvedStatus: LicenseStatus
    if activation == nil {
      resolvedStatus = status.isLicensed ? .unlicensed : status
    } else if activation?.isExpired(at: Date()) == true || plan.isExpired {
      resolvedStatus = .expired
    } else if status == .gracePeriod && gracePeriodExpiresAt == nil {
      resolvedStatus = .active
    } else {
      resolvedStatus = status
    }

    let resolvedActivation = resolvedStatus.isLicensed ? activation : nil
    let resolvedPlan =
      resolvedStatus.isLicensed
      ? (plan.isLicensed ? plan : LicensePlan.resolve(activation: resolvedActivation))
      : .unlicensed

    self.plan = resolvedPlan
    self.activation = resolvedActivation
    self.isActivating = isActivating
    self.isRefreshing =
      isRefreshing && isActivating == false && isDeactivating == false && resolvedActivation != nil
    self.isDeactivating = isDeactivating && isActivating == false && isRefreshing == false
    self.lastValidatedAt = lastValidatedAt
    self.status = resolvedStatus
    self.gracePeriodExpiresAt = resolvedStatus == .gracePeriod ? gracePeriodExpiresAt : nil
    self.lastRefreshFailure =
      resolvedStatus == .gracePeriod || resolvedStatus == .invalid || resolvedStatus == .expired
      ? lastRefreshFailure
      : nil
  }
}
