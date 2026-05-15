import Foundation

/// Non-authoritative persisted license state metadata.
///
/// Store snapshots separately from ``LicenseActivation`` to restore local
/// validation metadata such as grace-period state without treating that metadata
/// as proof of entitlement.
public struct LicenseStateSnapshot: Codable, Sendable, Equatable {
  /// The activation identity this snapshot belongs to.
  public let activationIdentity: ActivationIdentity

  /// The restorable licensed plan.
  public let plan: LicensePlan

  /// The last accepted activation or successful provider validation time.
  public let lastValidatedAt: Date?

  /// The restorable status.
  public let status: LicenseStatus

  /// The grace-period deadline when `status` is ``LicenseStatus/gracePeriod``.
  public let gracePeriodExpiresAt: Date?

  /// The refresh failure that caused the restorable grace-period state.
  public let lastRefreshFailure: LicenseRefreshFailure?

  private enum CodingKeys: String, CodingKey {
    case activationIdentity
    case plan
    case lastValidatedAt
    case status
    case gracePeriodExpiresAt
    case lastRefreshFailure
  }

  /// Creates a snapshot for a restorable licensed state.
  ///
  /// Returns `nil` for terminal or impossible states, including invalid,
  /// expired, deactivated, unlicensed, grace-period snapshots without a
  /// deadline, and mismatched plan identities.
  public init?(
    activationIdentity: ActivationIdentity,
    plan: LicensePlan,
    lastValidatedAt: Date?,
    status: LicenseStatus,
    gracePeriodExpiresAt: Date?,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    guard status.isLicensed else { return nil }
    guard status != .gracePeriod || gracePeriodExpiresAt != nil else { return nil }
    guard plan.isLicensed == false || plan.id == activationIdentity.planID else { return nil }

    self.activationIdentity = activationIdentity
    self.plan =
      plan.isLicensed
      ? plan
      : LicensePlan(
        id: activationIdentity.planID,
        isLicensed: true,
        expiresAt: nil
      )
    self.lastValidatedAt = lastValidatedAt
    self.status = status
    self.gracePeriodExpiresAt = status == .gracePeriod ? gracePeriodExpiresAt : nil
    self.lastRefreshFailure = status == .gracePeriod ? lastRefreshFailure : nil
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let snapshot = Self(
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
          "LicenseStateSnapshot status must be active or gracePeriod with gracePeriodExpiresAt."
      )
    }
    self = snapshot
  }

  /// Creates a snapshot from a manager state when it is restorable.
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

  /// The activation fields used to bind a state snapshot to a stored activation.
  public struct ActivationIdentity: Codable, Sendable, Equatable {
    /// The provider-neutral activation source.
    public let source: LicenseSource

    /// The normalized active plan identifier.
    public let planID: String

    /// The provider activation identifier, when available.
    public let activationID: String?

    /// The time the activation was created or accepted by the provider.
    public let activatedAt: Date

    private enum CodingKeys: String, CodingKey {
      case source
      case planID
      case activationID
      case activatedAt
    }

    /// Creates an activation identity.
    public init(
      source: LicenseSource,
      planID: String,
      activationID: String?,
      activatedAt: Date
    ) {
      let normalizedPlanID = planID.trimmingCharacters(in: .whitespacesAndNewlines)
      precondition(
        normalizedPlanID.isEmpty == false,
        "LicenseStateSnapshot.ActivationIdentity planID must not be empty."
      )

      self.source = source
      self.planID = normalizedPlanID
      self.activationID = activationID?.licenseKitTrimmedNonEmpty
      self.activatedAt = activatedAt
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let planID = try container.decode(String.self, forKey: .planID)
      guard let normalizedPlanID = planID.licenseKitTrimmedNonEmpty else {
        throw DecodingError.dataCorruptedError(
          forKey: .planID,
          in: container,
          debugDescription: "LicenseStateSnapshot.ActivationIdentity planID must not be empty."
        )
      }

      self.init(
        source: try container.decode(LicenseSource.self, forKey: .source),
        planID: normalizedPlanID,
        activationID: try container.decodeIfPresent(String.self, forKey: .activationID),
        activatedAt: try container.decode(Date.self, forKey: .activatedAt)
      )
    }

    init(activation: LicenseActivation) {
      source = activation.source
      planID = activation.planID
      activationID = activation.activationID
      activatedAt = activation.activatedAt
    }

    func matches(activation: LicenseActivation) -> Bool {
      self == Self(activation: activation)
    }
  }
}
