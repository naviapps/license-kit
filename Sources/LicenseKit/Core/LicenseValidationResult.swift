import Foundation

public struct LicenseValidationResult: Codable, Equatable, Sendable {
  public let isValid: Bool
  public let planID: String?
  public let expiresAt: Date?
  public let remainingActivations: Int?
  public let customerID: String?

  private enum CodingKeys: String, CodingKey {
    case isValid
    case planID
    case expiresAt
    case remainingActivations
    case customerID
  }

  public init(
    isValid: Bool,
    planID: String? = nil,
    expiresAt: Date? = nil,
    remainingActivations: Int? = nil,
    customerID: String? = nil
  ) {
    if let remainingActivations {
      precondition(
        remainingActivations >= 0,
        "LicenseValidationResult remainingActivations must not be negative."
      )
    }

    self.isValid = isValid
    self.planID = planID?.licenseKitTrimmedNonEmpty
    self.expiresAt = expiresAt
    self.remainingActivations = remainingActivations
    self.customerID = customerID?.licenseKitTrimmedNonEmpty
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let remainingActivations = try container.decodeIfPresent(
      Int.self,
      forKey: .remainingActivations
    )
    if let remainingActivations, remainingActivations < 0 {
      throw DecodingError.dataCorruptedError(
        forKey: .remainingActivations,
        in: container,
        debugDescription: "LicenseValidationResult remainingActivations must not be negative."
      )
    }

    self.init(
      isValid: try container.decode(Bool.self, forKey: .isValid),
      planID: try container.decodeIfPresent(String.self, forKey: .planID),
      expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt),
      remainingActivations: remainingActivations,
      customerID: try container.decodeIfPresent(String.self, forKey: .customerID)
    )
  }
}
