import Foundation

public struct LicenseStateSnapshot: Codable, Sendable, Equatable {
  public let activationIdentity: ActivationIdentity
  public let plan: LicensePlan
  public let lastValidatedAt: Date?
  public let status: LicenseStatus
  public let gracePeriodExpiresAt: Date?
  public let lastRefreshFailure: LicenseRefreshFailure?

  public init(
    activationIdentity: ActivationIdentity,
    plan: LicensePlan,
    lastValidatedAt: Date?,
    status: LicenseStatus,
    gracePeriodExpiresAt: Date?,
    lastRefreshFailure: LicenseRefreshFailure? = nil
  ) {
    self.activationIdentity = activationIdentity
    self.plan = plan
    self.lastValidatedAt = lastValidatedAt
    self.status = status
    self.gracePeriodExpiresAt = gracePeriodExpiresAt
    self.lastRefreshFailure = lastRefreshFailure
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

  func restoreState(
    activation: LicenseActivation,
    offerings: [LicenseOffering]
  ) -> LicenseState {
    LicenseState(
      plan: plan,
      activation: activation,
      isRefreshing: false,
      offerings: offerings,
      lastValidatedAt: lastValidatedAt,
      status: status,
      gracePeriodExpiresAt: gracePeriodExpiresAt,
      lastRefreshFailure: lastRefreshFailure
    )
  }

  public struct ActivationIdentity: Codable, Sendable, Equatable {
    public let source: LicenseSource
    public let planID: String
    public let activationID: String?
    public let activatedAt: Date

    private enum CodingKeys: String, CodingKey {
      case source
      case planID
      case activationID
      case activatedAt
    }

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
      self.activationID = activationID
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
