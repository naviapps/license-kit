import Foundation

/// The provider result for a completed license validation check.
public struct LicenseValidationResult: Codable, Equatable, Sendable {
  /// Whether the activation is still valid.
  public let isValid: Bool

  /// The normalized current plan identifier for valid activations.
  public let planID: String?

  /// The time the activation stops being locally usable, if it expires.
  public let expiresAt: Date?

  private enum CodingKeys: String, CodingKey {
    case isValid
    case planID
    case expiresAt
  }

  public init(
    isValid: Bool,
    planID: String? = nil,
    expiresAt: Date? = nil
  ) {
    self.isValid = isValid
    self.planID = isValid ? planID?.licenseKitTrimmedNonEmpty : nil
    self.expiresAt = expiresAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      isValid: try container.decode(Bool.self, forKey: .isValid),
      planID: try container.decodeIfPresent(String.self, forKey: .planID),
      expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    )
  }
}

struct LicenseValidationSnapshot: Sendable, Equatable {
  let planID: String?
  let isLicensed: Bool
  let expiresAt: Date?
  let checkedAt: Date

  init(
    planID: String?,
    isLicensed: Bool,
    expiresAt: Date?,
    checkedAt: Date = Date()
  ) {
    self.planID = planID?.licenseKitTrimmedNonEmpty
    self.isLicensed = isLicensed
    self.expiresAt = expiresAt
    self.checkedAt = checkedAt
  }

  init(
    result: LicenseValidationResult,
    activation: LicenseActivation,
    checkedAt: Date = Date()
  ) {
    self.init(
      planID: result.isValid ? result.planID ?? activation.planID : nil,
      isLicensed: result.isValid,
      expiresAt: result.expiresAt,
      checkedAt: checkedAt
    )
  }
}
