import Foundation

struct LicenseStateStore: Sendable {
  private(set) var plan: LicensePlan
  private(set) var activation: LicenseActivation?
  private(set) var isActivating: Bool
  private(set) var isRefreshing: Bool
  private(set) var isDeactivating: Bool
  private(set) var lastValidatedAt: Date?
  private(set) var status: LicenseStatus
  private(set) var gracePeriodExpiresAt: Date?
  private(set) var lastRefreshFailure: LicenseRefreshFailure?

  init(
    initialActivation: LicenseActivation? = nil,
    isActivating: Bool = false,
    isRefreshing: Bool = false,
    isDeactivating: Bool = false,
    resolvedPlan: LicensePlan? = nil,
    lastValidatedAt: Date? = nil,
    status: LicenseStatus? = nil,
    gracePeriodExpiresAt: Date? = nil,
    lastRefreshFailure: LicenseRefreshFailure? = nil,
    now: Date = Date()
  ) {
    self.isActivating = isActivating
    self.isDeactivating = isDeactivating && isActivating == false && isRefreshing == false
    self.lastValidatedAt = lastValidatedAt
    self.lastRefreshFailure = lastRefreshFailure

    let resolvedStatus = Self.resolveInitialStatus(
      status,
      activation: initialActivation,
      gracePeriodExpiresAt: gracePeriodExpiresAt,
      now: now
    )
    self.isRefreshing =
      isRefreshing && isActivating == false && self.isDeactivating == false
      && resolvedStatus.isLicensed
    if let initialActivation, resolvedStatus.isLicensed {
      activation = initialActivation
      plan = Self.resolveLicensedPlan(
        resolvedPlan,
        activation: initialActivation
      )
      self.status = resolvedStatus
      self.gracePeriodExpiresAt = self.status == .gracePeriod ? gracePeriodExpiresAt : nil
    } else {
      activation = nil
      plan = .unlicensed
      self.status = resolvedStatus
      self.gracePeriodExpiresAt = nil
    }
  }

  var state: LicenseState {
    LicenseState(
      plan: plan,
      activation: activation,
      isActivating: isActivating,
      isRefreshing: isRefreshing,
      isDeactivating: isDeactivating,
      lastValidatedAt: lastValidatedAt,
      status: status,
      gracePeriodExpiresAt: gracePeriodExpiresAt,
      lastRefreshFailure: lastRefreshFailure
    )
  }

  mutating func setRefreshing(_ flag: Bool) {
    isRefreshing = flag && isActivating == false && isDeactivating == false && activation != nil
  }

  mutating func setActivating() {
    isActivating = true
    isRefreshing = false
    isDeactivating = false
  }

  mutating func setDeactivating(_ flag: Bool) {
    isDeactivating = flag && isActivating == false && isRefreshing == false
  }

  @discardableResult
  mutating func applyActivation(_ activation: LicenseActivation, now: Date = Date()) -> Bool {
    guard activation.isExpired(at: now) == false else {
      self.activation = nil
      isActivating = false
      isDeactivating = false
      lastValidatedAt = activation.activatedAt
      status = .expired
      gracePeriodExpiresAt = nil
      lastRefreshFailure = nil
      plan = .unlicensed
      return false
    }

    self.activation = activation
    isActivating = false
    isDeactivating = false
    lastValidatedAt = activation.activatedAt
    status = .active
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
    plan = LicensePlan.resolve(activation: activation)
    return true
  }

  @discardableResult
  mutating func applyValidationSnapshot(
    _ validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseActivation? {
    lastValidatedAt = validationSnapshot.checkedAt
    isActivating = false
    isDeactivating = false
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
    status = resolveLicenseStatus(for: validationSnapshot)

    guard status.isLicensed, let activation else {
      status = status.isLicensed ? .unlicensed : status
      self.activation = nil
      plan = .unlicensed
      return nil
    }

    guard let updatedActivation = updatedActivation(activation, from: validationSnapshot) else {
      status = .invalid
      self.activation = nil
      plan = .unlicensed
      return nil
    }
    self.activation = updatedActivation
    plan = LicensePlan.resolve(activation: updatedActivation)
    return updatedActivation
  }

  mutating func markGrace(until date: Date, failure: LicenseRefreshFailure) {
    guard activation != nil else { return }
    status = .gracePeriod
    gracePeriodExpiresAt = date
    lastRefreshFailure = failure
  }

  mutating func markInvalid(failure: LicenseRefreshFailure) {
    activation = nil
    isActivating = false
    isDeactivating = false
    plan = .unlicensed
    status = .invalid
    gracePeriodExpiresAt = nil
    lastRefreshFailure = failure
  }

  mutating func markDeactivated() {
    activation = nil
    isActivating = false
    isDeactivating = false
    plan = .unlicensed
    lastValidatedAt = nil
    status = .deactivated
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
  }

  private func updatedActivation(
    _ activation: LicenseActivation,
    from validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseActivation? {
    LicenseActivation(
      source: activation.source,
      planIdentifier: validationSnapshot.planIdentifier ?? activation.planIdentifier,
      activatedAt: activation.activatedAt,
      licenseKey: activation.licenseKey,
      activationIdentifier: activation.activationIdentifier,
      expiresAt: validationSnapshot.expiresAt
    )
  }

  private func resolveLicenseStatus(
    for validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseStatus {
    if let expiresAt = validationSnapshot.expiresAt, expiresAt <= validationSnapshot.checkedAt {
      return .expired
    }
    guard validationSnapshot.isLicensed else {
      return .invalid
    }
    return .active
  }

  private static func resolveInitialStatus(
    _ status: LicenseStatus?,
    activation: LicenseActivation?,
    gracePeriodExpiresAt: Date?,
    now: Date
  ) -> LicenseStatus {
    let requestedStatus = status ?? (activation == nil ? .unlicensed : .active)
    guard let activation else {
      return requestedStatus.isLicensed ? .unlicensed : requestedStatus
    }
    if activation.isExpired(at: now) {
      return .expired
    }
    if requestedStatus == .gracePeriod, let gracePeriodExpiresAt, gracePeriodExpiresAt <= now {
      return .invalid
    }
    guard requestedStatus.isLicensed else { return requestedStatus }
    return resolveLicensedStatus(requestedStatus, gracePeriodExpiresAt: gracePeriodExpiresAt)
  }

  private static func resolveLicensedStatus(
    _ status: LicenseStatus,
    gracePeriodExpiresAt: Date?
  ) -> LicenseStatus {
    guard status == .gracePeriod else { return status }
    return gracePeriodExpiresAt == nil ? .active : .gracePeriod
  }

  private static func resolveLicensedPlan(
    _ plan: LicensePlan?,
    activation: LicenseActivation
  ) -> LicensePlan {
    guard let plan, plan.isLicensed else {
      return LicensePlan.resolve(activation: activation)
    }
    return plan
  }
}
