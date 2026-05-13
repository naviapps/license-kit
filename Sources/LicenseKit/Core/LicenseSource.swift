import Foundation

public struct LicenseSource: Codable, Equatable, Hashable, Sendable, RawRepresentable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) {
    let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    self.rawValue = normalizedValue.isEmpty ? Self.defaultRawValue : normalizedValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static let `default` = LicenseSource(rawValue: defaultRawValue)

  private static let defaultRawValue = "default"
}
