import Foundation

/// A provider-neutral plan attached to the current license state.
public struct LicensePlan: Codable, Equatable, Sendable {
  /// The normalized plan identifier.
  public let id: String

  /// Whether this value represents a licensed plan.
  public let isLicensed: Bool

  /// The time this plan stops being locally usable, if it expires.
  public let expiresAt: Date?

  /// The canonical unlicensed plan.
  public static let unlicensed = LicensePlan(
    id: unlicensedID,
    isLicensed: false
  )

  private static let unlicensedID = "unlicensed"

  private enum CodingKeys: String, CodingKey {
    case id
    case isLicensed
    case expiresAt
  }

  public init(id: String, isLicensed: Bool, expiresAt: Date? = nil) {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(normalizedID.isEmpty == false, "LicensePlan id must not be empty.")

    if isLicensed {
      self.id = normalizedID
      self.isLicensed = true
      self.expiresAt = expiresAt
    } else {
      self.id = Self.unlicensedID
      self.isLicensed = false
      self.expiresAt = nil
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    guard let normalizedID = id.licenseKitTrimmedNonEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .id,
        in: container,
        debugDescription: "LicensePlan id must not be empty."
      )
    }

    self.init(
      id: normalizedID,
      isLicensed: try container.decode(Bool.self, forKey: .isLicensed),
      expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    )
  }

  /// Returns whether the plan is expired at the current time.
  public var isExpired: Bool {
    isExpired(at: Date())
  }

  /// Returns whether the plan is expired at `date`.
  public func isExpired(at date: Date) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt <= date
  }

  static func resolve(activation: LicenseActivation?) -> LicensePlan {
    guard let activation else { return .unlicensed }
    return LicensePlan(
      id: activation.planID,
      isLicensed: true,
      expiresAt: activation.expiresAt
    )
  }

  static func resolve(validationSnapshot: LicenseValidationSnapshot) -> LicensePlan {
    guard validationSnapshot.isLicensed, let planID = validationSnapshot.planID else {
      return .unlicensed
    }
    return LicensePlan(
      id: planID,
      isLicensed: true,
      expiresAt: validationSnapshot.expiresAt
    )
  }
}
