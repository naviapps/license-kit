import Foundation

/// A provider-neutral plan attached to the current license state.
public struct LicensePlan: Codable, Equatable, Hashable, Sendable {
  /// The normalized plan identifier.
  public let identifier: String

  /// Whether this value represents a licensed plan.
  public let isLicensed: Bool

  /// The time this plan stops being locally usable, if it expires.
  public let expiresAt: Date?

  /// The canonical unlicensed plan.
  public static let unlicensed = LicensePlan(
    canonicalUnlicensedIdentifier: unlicensedIdentifier
  )

  private static let unlicensedIdentifier = "unlicensed"

  private enum CodingKeys: String, CodingKey {
    case identifier = "id"
    case isLicensed
    case expiresAt
  }

  /// Creates a normalized license plan.
  ///
  /// Unlicensed plans must use the canonical ``unlicensed`` identifier and omit
  /// expiration. Returns `nil` when a licensed `identifier` is empty after
  /// trimming whitespace and newlines, when a licensed `identifier` is the
  /// reserved unlicensed identifier, when an unlicensed record is not canonical,
  /// or when `expiresAt` is present but not finite.
  public init?(identifier: String, isLicensed: Bool, expiresAt: Date? = nil) {
    guard isLicensed else {
      guard identifier == Self.unlicensedIdentifier, expiresAt == nil else { return nil }
      self = .unlicensed
      return
    }
    guard let normalizedIdentifier = identifier.licenseKitTrimmedNonEmpty else { return nil }
    guard Self.isReservedIdentifier(normalizedIdentifier) == false else { return nil }
    guard Self.isFiniteDate(expiresAt) else { return nil }
    self.init(licensedIdentifier: normalizedIdentifier, expiresAt: expiresAt)
  }

  private init(licensedIdentifier identifier: String, expiresAt: Date?) {
    self.identifier = identifier
    self.isLicensed = true
    self.expiresAt = expiresAt
  }

  private init(canonicalUnlicensedIdentifier identifier: String) {
    self.identifier = identifier
    self.isLicensed = false
    self.expiresAt = nil
  }

  /// Decodes a normalized license plan.
  public init(from decoder: Decoder) throws {
    try Self.rejectUnknownFields(in: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let isLicensed = try container.decode(Bool.self, forKey: .isLicensed)
    guard isLicensed else {
      try Self.validateUnlicensedFields(in: container)
      self = .unlicensed
      return
    }

    let identifier = try container.decode(String.self, forKey: .identifier)
    guard let normalizedIdentifier = identifier.licenseKitTrimmedNonEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .identifier,
        in: container,
        debugDescription: "LicensePlan identifier must not be empty."
      )
    }
    guard Self.isReservedIdentifier(normalizedIdentifier) == false else {
      throw DecodingError.dataCorruptedError(
        forKey: .identifier,
        in: container,
        debugDescription:
          "Licensed LicensePlan identifier must not be '\(Self.unlicensedIdentifier)'."
      )
    }

    let expiresAt = try Self.decodeIfPresentRejectingNull(
      Date.self,
      forKey: .expiresAt,
      in: container
    )
    guard Self.isFiniteDate(expiresAt) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt,
        in: container,
        debugDescription: "LicensePlan expiresAt must be finite."
      )
    }

    self.init(licensedIdentifier: normalizedIdentifier, expiresAt: expiresAt)
  }

  /// Returns whether the plan is expired at the current time.
  public var isExpired: Bool {
    isExpired(at: Date())
  }

  /// Returns whether the plan is expired at `date`.
  public func isExpired(at date: Date) -> Bool {
    guard Self.isFiniteDate(date) else { return false }
    guard let expiresAt else { return false }
    return expiresAt <= date
  }

  static func resolve(activation: LicenseActivation?) -> LicensePlan {
    guard let activation else { return .unlicensed }
    return LicensePlan(
      licensedIdentifier: activation.planIdentifier,
      expiresAt: activation.expiresAt
    )
  }

  static func isReservedIdentifier(_ identifier: String) -> Bool {
    identifier.licenseKitTrimmedNonEmpty == unlicensedIdentifier
  }

  private struct StoredField: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
      self.stringValue = stringValue
      self.intValue = nil
    }

    init?(intValue: Int) {
      self.stringValue = "\(intValue)"
      self.intValue = intValue
    }
  }

  private static func rejectUnknownFields(in decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: StoredField.self)
    for key in container.allKeys where CodingKeys(stringValue: key.stringValue) == nil {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "LicensePlan contains unknown field '\(key.stringValue)'."
      )
    }
  }

  private static func validateUnlicensedFields(
    in container: KeyedDecodingContainer<CodingKeys>
  ) throws {
    let identifier = try container.decode(String.self, forKey: .identifier)
    guard identifier == unlicensedIdentifier else {
      throw DecodingError.dataCorruptedError(
        forKey: .identifier,
        in: container,
        debugDescription: "Unlicensed LicensePlan identifier must be '\(unlicensedIdentifier)'."
      )
    }
    guard container.contains(.expiresAt) == false else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt,
        in: container,
        debugDescription: "Unlicensed LicensePlan expiresAt must be omitted."
      )
    }
  }

  private static func decodeIfPresentRejectingNull<Value: Decodable>(
    _ type: Value.Type,
    forKey key: CodingKeys,
    in container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Value? {
    guard container.contains(key) else { return nil }
    guard (try container.decodeNil(forKey: key)) == false else {
      throw DecodingError.valueNotFound(
        type,
        DecodingError.Context(
          codingPath: container.codingPath + [key],
          debugDescription: "LicensePlan \(key.stringValue) must be omitted instead of null."
        )
      )
    }
    return try container.decode(type, forKey: key)
  }

  private static func isFiniteDate(_ date: Date?) -> Bool {
    guard let date else { return true }
    return date.timeIntervalSinceReferenceDate.isFinite
  }
}
