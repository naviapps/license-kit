import Foundation

/// A provider-resolved license activation that LicenseKit can persist and refresh.
public struct LicenseActivation: Codable, Sendable, Equatable {
  /// The provider-neutral source that supplied this activation.
  public let source: LicenseSource

  /// The normalized license key, when the provider or app wants LicenseKit to persist it.
  public let licenseKey: String?

  /// The normalized active plan identifier.
  public let planID: String

  /// The provider activation identifier used as the preferred validation identifier.
  public let activationID: String?

  /// The time this activation was created or accepted by the provider.
  public let activatedAt: Date

  /// The time this activation stops being locally usable, if it expires.
  public let expiresAt: Date?

  private enum CodingKeys: String, CodingKey {
    case source
    case licenseKey
    case planID
    case activationID
    case activatedAt
    case expiresAt
  }

  public init(
    source: LicenseSource = .default,
    licenseKey: String? = nil,
    planID: String,
    activationID: String? = nil,
    activatedAt: Date = Date(),
    expiresAt: Date? = nil
  ) {
    let normalizedPlanID = planID.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(normalizedPlanID.isEmpty == false, "LicenseActivation planID must not be empty.")

    self.source = source
    self.licenseKey = licenseKey?.licenseKitTrimmedNonEmpty
    self.planID = normalizedPlanID
    self.activationID = activationID?.licenseKitTrimmedNonEmpty
    self.activatedAt = activatedAt
    self.expiresAt = expiresAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let planID = try container.decode(String.self, forKey: .planID)
    guard let normalizedPlanID = planID.licenseKitTrimmedNonEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .planID,
        in: container,
        debugDescription: "LicenseActivation planID must not be empty."
      )
    }

    self.init(
      source: try container.decodeIfPresent(LicenseSource.self, forKey: .source) ?? .default,
      licenseKey: try container.decodeIfPresent(String.self, forKey: .licenseKey),
      planID: normalizedPlanID,
      activationID: try container.decodeIfPresent(String.self, forKey: .activationID),
      activatedAt: try container.decode(Date.self, forKey: .activatedAt),
      expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    )
  }

  /// Returns whether the activation is expired at the current time.
  public var isExpired: Bool {
    isExpired(at: Date())
  }

  /// Returns whether the activation is expired at `date`.
  public func isExpired(at date: Date) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt <= date
  }
}
