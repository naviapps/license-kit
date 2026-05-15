import Foundation

/// A provider-neutral identifier for the source that supplied a license activation.
public struct LicenseSource: Codable, Equatable, Hashable, Sendable, RawRepresentable,
  ExpressibleByStringLiteral
{
  /// The normalized source identifier.
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

  /// The default source used when an activation does not need source-specific handling.
  public static let `default` = LicenseSource(rawValue: defaultRawValue)

  private static let defaultRawValue = "default"
}
