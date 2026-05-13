import Foundation

public struct LicenseActivation: Codable, Sendable, Equatable {
  public let source: LicenseSource
  public let licenseKey: String?
  public let planID: String
  public let customerID: String?
  public let deviceName: String?
  public let activationID: String?
  public let activatedAt: Date
  public let expiresAt: Date?
  public let remainingActivations: Int?

  private enum CodingKeys: String, CodingKey {
    case source
    case licenseKey
    case planID
    case customerID
    case deviceName
    case activationID
    case activatedAt
    case expiresAt
    case remainingActivations
  }

  public init(
    source: LicenseSource = .default,
    licenseKey: String? = nil,
    planID: String,
    customerID: String? = nil,
    deviceName: String? = nil,
    activationID: String? = nil,
    activatedAt: Date = Date(),
    expiresAt: Date? = nil,
    remainingActivations: Int? = nil
  ) {
    let normalizedPlanID = planID.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(normalizedPlanID.isEmpty == false, "LicenseActivation planID must not be empty.")
    if let remainingActivations {
      precondition(
        remainingActivations >= 0,
        "LicenseActivation remainingActivations must not be negative."
      )
    }

    self.source = source
    self.licenseKey = licenseKey?.licenseKitTrimmedNonEmpty
    self.planID = normalizedPlanID
    self.customerID = customerID?.licenseKitTrimmedNonEmpty
    self.deviceName = deviceName?.licenseKitTrimmedNonEmpty
    self.activationID = activationID?.licenseKitTrimmedNonEmpty
    self.activatedAt = activatedAt
    self.expiresAt = expiresAt
    self.remainingActivations = remainingActivations
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

    let remainingActivations = try container.decodeIfPresent(
      Int.self,
      forKey: .remainingActivations
    )
    if let remainingActivations, remainingActivations < 0 {
      throw DecodingError.dataCorruptedError(
        forKey: .remainingActivations,
        in: container,
        debugDescription: "LicenseActivation remainingActivations must not be negative."
      )
    }

    self.init(
      source: try container.decodeIfPresent(LicenseSource.self, forKey: .source) ?? .default,
      licenseKey: try container.decodeIfPresent(String.self, forKey: .licenseKey),
      planID: normalizedPlanID,
      customerID: try container.decodeIfPresent(String.self, forKey: .customerID),
      deviceName: try container.decodeIfPresent(String.self, forKey: .deviceName),
      activationID: try container.decodeIfPresent(String.self, forKey: .activationID),
      activatedAt: try container.decode(Date.self, forKey: .activatedAt),
      expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt),
      remainingActivations: remainingActivations
    )
  }
}
