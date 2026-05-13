import Foundation

struct LicenseStateStore: Sendable {
  private(set) var plan: LicensePlan
  private(set) var activation: LicenseActivation?
  private(set) var isRefreshing: Bool
  private(set) var offerings: [LicenseOffering]
  private(set) var lastValidatedAt: Date?
  private(set) var status: LicenseStatus
  private(set) var gracePeriodExpiresAt: Date?
  private(set) var lastRefreshFailure: LicenseRefreshFailure?

  init(
    offerings: [LicenseOffering] = [],
    initialActivation: LicenseActivation? = nil,
    isRefreshing: Bool = false,
    resolvedPlan: LicensePlan? = nil,
    lastValidatedAt: Date? = nil,
    status: LicenseStatus? = nil,
    gracePeriodExpiresAt: Date? = nil,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    self.offerings = offerings
    self.isRefreshing = isRefreshing
    self.lastValidatedAt = lastValidatedAt
    self.lastRefreshFailure = lastRefreshFailure

    let initialStatus = status ?? (initialActivation == nil ? .unlicensed : .active)
    if let initialActivation, initialStatus.isLicensed {
      activation = initialActivation
      plan = Self.resolveLicensedPlan(
        resolvedPlan,
        activation: initialActivation
      )
      self.status = Self.resolveLicensedStatus(
        initialStatus,
        gracePeriodExpiresAt: gracePeriodExpiresAt
      )
      self.gracePeriodExpiresAt = self.status == .gracePeriod ? gracePeriodExpiresAt : nil
    } else {
      activation = nil
      plan = .unlicensed
      self.status = Self.resolveStatusWithoutActivation(initialStatus)
      self.gracePeriodExpiresAt = nil
    }
  }

  var state: LicenseState {
    LicenseState(
      plan: plan,
      activation: activation,
      isRefreshing: isRefreshing,
      offerings: offerings,
      lastValidatedAt: lastValidatedAt,
      status: status,
      gracePeriodExpiresAt: gracePeriodExpiresAt,
      lastRefreshFailure: lastRefreshFailure
    )
  }

  mutating func setOfferings(_ offerings: [LicenseOffering]) {
    self.offerings = offerings
  }

  mutating func setRefreshing(_ flag: Bool) {
    isRefreshing = flag
  }

  mutating func setActivating() {
    status = .activating
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
  }

  mutating func applyActivation(_ activation: LicenseActivation) {
    self.activation = activation
    lastValidatedAt = activation.activatedAt
    status = .active
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
    plan = LicensePlan.resolve(activation: activation)
  }

  @discardableResult
  mutating func applyValidationSnapshot(
    _ validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseActivation? {
    lastValidatedAt = validationSnapshot.checkedAt
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
    plan = LicensePlan.resolve(validationSnapshot: validationSnapshot)
    status = resolveLicenseStatus(for: validationSnapshot)

    guard validationSnapshot.isLicensed else {
      activation = nil
      return nil
    }

    let updatedActivation = updateActivation(from: validationSnapshot)
    return updatedActivation
  }

  mutating func recordRefreshFailure(_ failure: LicenseRefreshFailure) {
    lastRefreshFailure = failure
  }

  mutating func markGrace(until date: Date, failure: LicenseRefreshFailure) {
    guard activation != nil else { return }
    status = .gracePeriod
    gracePeriodExpiresAt = date
    lastRefreshFailure = failure
  }

  mutating func markInvalid(failure: LicenseRefreshFailure) {
    activation = nil
    plan = .unlicensed
    status = .invalid
    gracePeriodExpiresAt = nil
    lastRefreshFailure = failure
  }

  mutating func markDeactivated() {
    activation = nil
    plan = .unlicensed
    lastValidatedAt = nil
    status = .deactivated
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
  }

  mutating func resetToUnlicensed() {
    activation = nil
    plan = .unlicensed
    lastValidatedAt = nil
    status = .unlicensed
    gracePeriodExpiresAt = nil
    lastRefreshFailure = nil
  }

  private mutating func updateActivation(
    from validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseActivation? {
    guard let activation else { return nil }
    let updatedActivation = LicenseActivation(
      source: activation.source,
      licenseKey: activation.licenseKey,
      planID: validationSnapshot.planID ?? activation.planID,
      customerID: validationSnapshot.customerID ?? activation.customerID,
      deviceName: activation.deviceName,
      activationID: activation.activationID,
      activatedAt: activation.activatedAt,
      expiresAt: validationSnapshot.expiresAt,
      remainingActivations: validationSnapshot.remainingActivations
    )
    self.activation = updatedActivation
    return updatedActivation
  }

  private func resolveLicenseStatus(
    for validationSnapshot: LicenseValidationSnapshot
  ) -> LicenseStatus {
    guard validationSnapshot.isLicensed else {
      if let expiresAt = validationSnapshot.expiresAt, expiresAt < validationSnapshot.checkedAt {
        return .expired
      }
      return .invalid
    }
    return .active
  }

  private static func resolveStatusWithoutActivation(_ status: LicenseStatus?) -> LicenseStatus {
    guard let status else { return .unlicensed }
    guard status.isLicensed == false else { return .unlicensed }
    return status
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
