import Foundation

public struct LicenseOffering: Equatable, Sendable, Codable, Identifiable {
  public let id: String
  public let name: String
  public let kind: LicenseOfferingKind
  public let billingInterval: LicenseBillingInterval?
  public let priceInMinorUnits: Int?
  public let currencyCode: String?
  public let description: String?
  public let formattedPrice: String?
  public let metadata: [String: String]?

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case kind
    case billingInterval
    case priceInMinorUnits
    case currencyCode
    case description
    case formattedPrice
    case metadata
  }

  public init(
    id: String,
    name: String,
    kind: LicenseOfferingKind = .unknown,
    billingInterval: LicenseBillingInterval? = nil,
    priceInMinorUnits: Int? = nil,
    currencyCode: String? = nil,
    description: String? = nil,
    formattedPrice: String? = nil,
    metadata: [String: String]? = nil
  ) {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(normalizedID.isEmpty == false, "LicenseOffering id must not be empty.")
    precondition(normalizedName.isEmpty == false, "LicenseOffering name must not be empty.")
    if let priceInMinorUnits {
      precondition(
        priceInMinorUnits >= 0,
        "LicenseOffering priceInMinorUnits must not be negative."
      )
    }
    let normalizedCurrencyCode = Self.normalizedCurrencyCode(currencyCode)
    if let priceInMinorUnits, priceInMinorUnits > 0 {
      precondition(
        normalizedCurrencyCode != nil,
        "LicenseOffering currencyCode must be present when priceInMinorUnits is positive."
      )
    }

    self.id = normalizedID
    self.name = normalizedName
    self.kind = kind
    self.billingInterval = billingInterval
    self.priceInMinorUnits = priceInMinorUnits
    self.currencyCode = normalizedCurrencyCode
    self.description = description?.licenseKitTrimmedNonEmpty
    self.formattedPrice = formattedPrice?.licenseKitTrimmedNonEmpty
    self.metadata = metadata?.isEmpty == true ? nil : metadata
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(String.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    guard id.licenseKitTrimmedNonEmpty != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .id,
        in: container,
        debugDescription: "LicenseOffering id must not be empty."
      )
    }
    guard name.licenseKitTrimmedNonEmpty != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .name,
        in: container,
        debugDescription: "LicenseOffering name must not be empty."
      )
    }

    let priceInMinorUnits = try container.decodeIfPresent(Int.self, forKey: .priceInMinorUnits)
    if let priceInMinorUnits, priceInMinorUnits < 0 {
      throw DecodingError.dataCorruptedError(
        forKey: .priceInMinorUnits,
        in: container,
        debugDescription: "LicenseOffering priceInMinorUnits must not be negative."
      )
    }

    let currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
    if let normalizedCurrencyCode = currencyCode?.licenseKitTrimmedNonEmpty,
      Self.isValidCurrencyCode(normalizedCurrencyCode.uppercased()) == false
    {
      throw DecodingError.dataCorruptedError(
        forKey: .currencyCode,
        in: container,
        debugDescription: "LicenseOffering currencyCode must be a three-letter currency code."
      )
    }
    if let priceInMinorUnits, priceInMinorUnits > 0,
      currencyCode?.licenseKitTrimmedNonEmpty == nil
    {
      throw DecodingError.dataCorruptedError(
        forKey: .currencyCode,
        in: container,
        debugDescription: "LicenseOffering positive price requires currencyCode."
      )
    }

    self.init(
      id: id,
      name: name,
      kind: try container.decodeIfPresent(LicenseOfferingKind.self, forKey: .kind) ?? .unknown,
      billingInterval: try container.decodeIfPresent(
        LicenseBillingInterval.self,
        forKey: .billingInterval
      ),
      priceInMinorUnits: priceInMinorUnits,
      currencyCode: currencyCode,
      description: try container.decodeIfPresent(String.self, forKey: .description),
      formattedPrice: try container.decodeIfPresent(String.self, forKey: .formattedPrice),
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata)
    )
  }

  private static func normalizedCurrencyCode(_ currencyCode: String?) -> String? {
    guard let normalizedCurrencyCode = currencyCode?.licenseKitTrimmedNonEmpty else { return nil }
    let uppercasedCurrencyCode = normalizedCurrencyCode.uppercased()
    precondition(
      isValidCurrencyCode(uppercasedCurrencyCode),
      "LicenseOffering currencyCode must be a three-letter currency code."
    )
    return uppercasedCurrencyCode
  }

  private static func isValidCurrencyCode(_ currencyCode: String) -> Bool {
    guard currencyCode.count == 3 else { return false }
    return currencyCode.unicodeScalars.allSatisfy { scalar in
      (65...90).contains(Int(scalar.value))
    }
  }
}
