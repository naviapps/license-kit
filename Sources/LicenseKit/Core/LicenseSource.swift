/// A provider-neutral activation source identifier.
public struct LicenseSource: Codable, Equatable, Hashable, Sendable {
  /// The normalized source identifier.
  public let identifier: String

  /// Creates a normalized license source.
  ///
  /// Returns `nil` when `identifier` is empty after trimming whitespace and
  /// newlines, or when it is reserved for ``unspecified``. Use ``unspecified``
  /// when an activation intentionally has no source-specific behavior.
  public init?(identifier: String) {
    guard let normalizedIdentifier = identifier.licenseKitTrimmedNonEmpty else {
      return nil
    }
    guard normalizedIdentifier != Self.unspecifiedIdentifier else { return nil }
    self.init(normalizedIdentifier: normalizedIdentifier)
  }

  /// Decodes a canonical license source.
  ///
  /// Persisted identifiers must already be encoded without leading or trailing
  /// whitespace.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let identifier = try container.decode(String.self)
    guard let normalizedIdentifier = identifier.licenseKitTrimmedNonEmpty else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "LicenseSource identifier must not be empty."
      )
    }
    guard identifier == normalizedIdentifier else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription:
          "LicenseSource identifier must be encoded without leading or trailing whitespace."
      )
    }
    self.init(normalizedIdentifier: normalizedIdentifier)
  }

  /// Encodes the source as its normalized identifier.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(identifier)
  }

  /// The source used when an activation does not need source-specific handling.
  public static let unspecified = LicenseSource(
    normalizedIdentifier: unspecifiedIdentifier
  )

  private static let unspecifiedIdentifier = "unspecified"

  private init(normalizedIdentifier identifier: String) {
    self.identifier = identifier
  }
}
