import Foundation

/// A normalized activation record used for persistence, validation, and deactivation.
public struct LicenseActivation: Codable, Sendable, Equatable, Hashable {
  /// The provider-neutral source recorded for this activation.
  ///
  /// This is a normalized ``LicenseSource`` value.
  ///
  /// Use ``LicenseSource/unspecified`` only when the activation does not need
  /// source-specific handling.
  public let source: LicenseSource

  /// The normalized plan identifier recorded for this activation.
  ///
  /// This is non-empty after trimming whitespace and newlines.
  public let planIdentifier: String

  /// The time this activation became active.
  ///
  /// This must be finite.
  public let activatedAt: Date

  /// The normalized license key retained for persistence or provider requests.
  ///
  /// Whitespace and ignored format scalars are removed. Blank values normalize
  /// to `nil`.
  public let licenseKey: String?

  /// The provider activation identifier used for validation or deactivation.
  ///
  /// Leading and trailing whitespace and newlines are trimmed. Blank values
  /// normalize to `nil`.
  public let activationIdentifier: String?

  /// The time this activation stops being locally usable, if it expires.
  ///
  /// When present, this must be finite and later than ``activatedAt``.
  public let expiresAt: Date?

  private enum CodingKeys: String, CodingKey {
    case source
    case planIdentifier
    case activatedAt
    case licenseKey
    case activationIdentifier
    case expiresAt
  }

  /// Creates a normalized license activation.
  ///
  /// Returns `nil` when `planIdentifier` is empty after trimming whitespace and
  /// newlines, when it is reserved for ``LicensePlan/unlicensed``, when
  /// `activatedAt` is not finite, or when `expiresAt` is present but is not
  /// finite or not later than `activatedAt`. Optional license keys remove
  /// whitespace and ignored format scalars. Optional activation identifiers are
  /// trimmed to `nil` when blank.
  public init?(
    source: LicenseSource,
    planIdentifier: String,
    activatedAt: Date,
    licenseKey: String? = nil,
    activationIdentifier: String? = nil,
    expiresAt: Date? = nil
  ) {
    guard let normalizedPlanIdentifier = planIdentifier.licenseKitTrimmedNonEmpty else {
      return nil
    }
    guard LicensePlan.isReservedIdentifier(normalizedPlanIdentifier) == false else {
      return nil
    }
    guard Self.isFiniteDate(activatedAt) else {
      return nil
    }
    guard Self.isValidExpiration(expiresAt, activatedAt: activatedAt) else {
      return nil
    }

    self.source = source
    self.planIdentifier = normalizedPlanIdentifier
    self.activatedAt = activatedAt
    self.licenseKey = Self.normalizedLicenseKey(licenseKey)
    self.activationIdentifier = activationIdentifier?.licenseKitTrimmedNonEmpty
    self.expiresAt = expiresAt
  }

  /// Decodes a normalized license activation.
  ///
  /// Persisted records must use only canonical field names, include `source`,
  /// `planIdentifier`, and `activatedAt`, omit absent optional fields instead of
  /// encoding them as `null`, keep `activatedAt` finite, and keep `expiresAt`
  /// finite and later than `activatedAt` when present.
  public init(from decoder: Decoder) throws {
    try Self.rejectUnknownFields(in: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let planIdentifier = try container.decode(String.self, forKey: .planIdentifier)
    guard let normalizedPlanIdentifier = planIdentifier.licenseKitTrimmedNonEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .planIdentifier,
        in: container,
        debugDescription: "LicenseActivation planIdentifier must not be empty."
      )
    }
    guard LicensePlan.isReservedIdentifier(normalizedPlanIdentifier) == false else {
      throw DecodingError.dataCorruptedError(
        forKey: .planIdentifier,
        in: container,
        debugDescription:
          "LicenseActivation planIdentifier must not be reserved for LicensePlan.unlicensed."
      )
    }

    let source = try container.decode(LicenseSource.self, forKey: .source)
    let activatedAt = try container.decode(Date.self, forKey: .activatedAt)
    guard Self.isFiniteDate(activatedAt) else {
      throw DecodingError.dataCorruptedError(
        forKey: .activatedAt,
        in: container,
        debugDescription: "LicenseActivation activatedAt must be finite."
      )
    }
    let expiresAt = try Self.decodeIfPresentRejectingNull(
      Date.self,
      forKey: .expiresAt,
      in: container
    )
    guard Self.isValidExpiration(expiresAt, activatedAt: activatedAt) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt,
        in: container,
        debugDescription: "LicenseActivation expiresAt must be finite and later than activatedAt."
      )
    }

    let licenseKey = Self.normalizedLicenseKey(
      try Self.decodeIfPresentRejectingNull(String.self, forKey: .licenseKey, in: container)
    )
    let activationIdentifier = try Self.decodeIfPresentRejectingNull(
      String.self,
      forKey: .activationIdentifier,
      in: container
    )
    self.source = source
    self.planIdentifier = normalizedPlanIdentifier
    self.activatedAt = activatedAt
    self.licenseKey = licenseKey
    self.activationIdentifier = activationIdentifier?.licenseKitTrimmedNonEmpty
    self.expiresAt = expiresAt
  }

  /// Returns whether the activation is expired at finite `date`.
  public func isExpired(at date: Date) -> Bool {
    guard Self.isFiniteDate(date) else { return false }
    guard let expiresAt else { return false }
    return expiresAt <= date
  }

  private static func normalizedLicenseKey(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalizedValue = LicenseKeyNormalizer.normalize(value)
    return normalizedValue.isEmpty ? nil : normalizedValue
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
        debugDescription: "LicenseActivation contains unknown field '\(key.stringValue)'."
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
          debugDescription: "LicenseActivation \(key.stringValue) must be omitted when absent."
        )
      )
    }
    return try container.decode(type, forKey: key)
  }

  private static func isFiniteDate(_ date: Date) -> Bool {
    date.timeIntervalSinceReferenceDate.isFinite
  }

  private static func isValidExpiration(_ expiresAt: Date?, activatedAt: Date) -> Bool {
    guard let expiresAt else { return true }
    return isFiniteDate(expiresAt) && expiresAt > activatedAt
  }
}
