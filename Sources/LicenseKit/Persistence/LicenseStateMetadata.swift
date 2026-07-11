import Foundation

/// Internal non-authoritative persisted license state metadata.
///
/// Store metadata separately from ``LicenseActivation`` to restore local
/// validation metadata such as grace-period or terminal activation state without
/// treating that metadata as proof of entitlement.
struct LicenseStateMetadata: Codable, Sendable, Equatable, Hashable {
  let activationIdentity: ActivationIdentity

  let plan: LicensePlan

  let lastValidatedAt: Date?

  let status: LicenseStatus

  let gracePeriodExpiresAt: Date?

  let lastRefreshFailure: LicenseRefreshFailure?

  private enum CodingKeys: String, CodingKey {
    case activationIdentity
    case plan
    case lastValidatedAt
    case status
    case gracePeriodExpiresAt
    case lastRefreshFailure
  }

  init?(
    activationIdentity: ActivationIdentity,
    plan: LicensePlan,
    lastValidatedAt: Date?,
    status: LicenseStatus,
    gracePeriodExpiresAt: Date?,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    guard status != .unlicensed else { return nil }
    guard status != .gracePeriod || gracePeriodExpiresAt != nil else {
      return nil
    }
    guard status.isLicensed || gracePeriodExpiresAt == nil else {
      return nil
    }
    guard
      status.isLicensed == false || plan.isLicensed == false
        || plan.identifier == activationIdentity.planIdentifier
    else {
      return nil
    }

    let resolvedPlan: LicensePlan
    if status.isLicensed == false {
      resolvedPlan = .unlicensed
    } else if plan.isLicensed {
      resolvedPlan = plan
    } else if let activationPlan = LicensePlan(
      identifier: activationIdentity.planIdentifier,
      isLicensed: true,
      expiresAt: nil
    ) {
      resolvedPlan = activationPlan
    } else {
      return nil
    }

    self.activationIdentity = activationIdentity
    self.plan = resolvedPlan
    self.lastValidatedAt = lastValidatedAt
    self.status = status
    self.gracePeriodExpiresAt = status == .gracePeriod ? gracePeriodExpiresAt : nil
    self.lastRefreshFailure =
      status == .gracePeriod || status == .invalid || status == .expired
      ? lastRefreshFailure
      : nil
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let metadata = Self(
        activationIdentity: try container.decode(
          ActivationIdentity.self,
          forKey: .activationIdentity
        ),
        plan: try container.decode(LicensePlan.self, forKey: .plan),
        lastValidatedAt: try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt),
        status: try container.decode(LicenseStatus.self, forKey: .status),
        gracePeriodExpiresAt: try container.decodeIfPresent(
          Date.self,
          forKey: .gracePeriodExpiresAt
        ),
        lastRefreshFailure: try container.decodeIfPresent(
          LicenseRefreshFailure.self,
          forKey: .lastRefreshFailure
        )
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .status,
        in: container,
        debugDescription:
          "LicenseStateMetadata status must be active, gracePeriod with gracePeriodExpiresAt, invalid, expired, or deactivated."
      )
    }
    self = metadata
  }

  init?(state: LicenseState) {
    guard let activation = state.activation else { return nil }
    self.init(
      activationIdentity: ActivationIdentity(activation: activation),
      plan: state.plan,
      lastValidatedAt: state.lastValidatedAt,
      status: state.status,
      gracePeriodExpiresAt: state.gracePeriodExpiresAt,
      lastRefreshFailure: state.lastRefreshFailure
    )
  }

  func matches(activation: LicenseActivation) -> Bool {
    activationIdentity.matches(activation: activation)
  }

  func restoreState(activation: LicenseActivation) -> LicenseState {
    LicenseState(
      plan: plan,
      activation: activation,
      isActivating: false,
      isRefreshing: false,
      lastValidatedAt: lastValidatedAt,
      status: status,
      gracePeriodExpiresAt: gracePeriodExpiresAt,
      lastRefreshFailure: lastRefreshFailure
    )
  }

  struct ActivationIdentity: Codable, Sendable, Equatable, Hashable {
    let source: LicenseSource
    let planIdentifier: String
    let activatedAt: Date

    private enum CodingKeys: String, CodingKey {
      case source
      case planIdentifier
      case activatedAt
    }

    init?(
      source: LicenseSource,
      planIdentifier: String,
      activatedAt: Date
    ) {
      guard let normalizedPlanIdentifier = planIdentifier.licenseKitTrimmedNonEmpty else {
        return nil
      }
      guard LicensePlan.isReservedIdentifier(normalizedPlanIdentifier) == false else {
        return nil
      }

      self.source = source
      self.planIdentifier = normalizedPlanIdentifier
      self.activatedAt = activatedAt
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let planIdentifier = try container.decode(String.self, forKey: .planIdentifier)
      guard let normalizedPlanIdentifier = planIdentifier.licenseKitTrimmedNonEmpty else {
        throw DecodingError.dataCorruptedError(
          forKey: .planIdentifier,
          in: container,
          debugDescription:
            "LicenseStateMetadata.ActivationIdentity planIdentifier must not be empty."
        )
      }
      guard LicensePlan.isReservedIdentifier(normalizedPlanIdentifier) == false else {
        throw DecodingError.dataCorruptedError(
          forKey: .planIdentifier,
          in: container,
          debugDescription:
            "LicenseStateMetadata.ActivationIdentity planIdentifier must not be reserved for LicensePlan.unlicensed."
        )
      }

      guard
        let identity = Self(
          source: try container.decode(LicenseSource.self, forKey: .source),
          planIdentifier: normalizedPlanIdentifier,
          activatedAt: try container.decode(Date.self, forKey: .activatedAt)
        )
      else {
        throw DecodingError.dataCorruptedError(
          forKey: .planIdentifier,
          in: container,
          debugDescription:
            "LicenseStateMetadata.ActivationIdentity planIdentifier must not be empty."
        )
      }

      self = identity
    }

    init(activation: LicenseActivation) {
      source = activation.source
      planIdentifier = activation.planIdentifier
      activatedAt = activation.activatedAt
    }

    func matches(activation: LicenseActivation) -> Bool {
      self == Self(activation: activation)
    }
  }
}
