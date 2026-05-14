import Foundation

public enum LicenseBillingPeriodUnit: String, Codable, Equatable, Sendable {
  case day
  case week
  case month
  case year

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let unit = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "LicenseBillingPeriodUnit is invalid."
      )
    }
    self = unit
  }
}

public struct LicenseBillingPeriod: Codable, Equatable, Sendable {
  public let unit: LicenseBillingPeriodUnit
  public let count: Int

  private enum CodingKeys: String, CodingKey {
    case unit
    case count
  }

  public init(unit: LicenseBillingPeriodUnit, count: Int = 1) {
    precondition(count > 0, "LicenseBillingPeriod count must be positive.")

    self.unit = unit
    self.count = count
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
    guard count > 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .count,
        in: container,
        debugDescription: "LicenseBillingPeriod count must be positive."
      )
    }

    self.init(
      unit: try container.decode(LicenseBillingPeriodUnit.self, forKey: .unit),
      count: count
    )
  }

  public static let day = LicenseBillingPeriod(unit: .day)
  public static let week = LicenseBillingPeriod(unit: .week)
  public static let month = LicenseBillingPeriod(unit: .month)
  public static let year = LicenseBillingPeriod(unit: .year)
}
