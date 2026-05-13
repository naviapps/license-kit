import Foundation

public enum LicenseOfferingKind: String, Codable, Equatable, Sendable {
  case recurring
  case perpetual
  case unknown

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = Self(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .unknown
  }
}
