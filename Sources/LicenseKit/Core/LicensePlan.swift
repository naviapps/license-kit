import Foundation

public struct LicensePlan: Codable, Equatable, Sendable {
  public let id: String
  public let isLicensed: Bool
  public let expiresAt: Date?

  public static let unlicensed = LicensePlan(id: "unlicensed", isLicensed: false, expiresAt: nil)

  private enum CodingKeys: String, CodingKey {
    case id
    case isLicensed
    case expiresAt
  }

  public init(id: String, isLicensed: Bool, expiresAt: Date?) {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(normalizedID.isEmpty == false, "LicensePlan id must not be empty.")

    self.id = normalizedID
    self.isLicensed = isLicensed
    self.expiresAt = expiresAt
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

  public var isExpired: Bool {
    isExpired(at: Date())
  }

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
