import Foundation

/// The provider result for a completed license validation check.
public struct LicenseValidationResult: Codable, Equatable, Hashable, Sendable {
  /// Whether the activation is still valid.
  public let isValid: Bool

  /// The normalized current plan identifier for valid activations.
  ///
  /// Omit this to keep the activation's current plan identifier.
  /// Invalid results must omit this value.
  public let planIdentifier: String?

  /// The time the activation stops being locally usable, if it expires.
  ///
  /// Invalid results must omit this value.
  public let expiresAt: Date?

  private enum CodingKeys: String, CodingKey {
    case isValid
    case planIdentifier
    case expiresAt
  }

  /// Creates a normalized provider validation result.
  ///
  /// Returns `nil` when an invalid result includes a plan or expiration, when a
  /// valid result includes a blank plan identifier or one reserved for
  /// ``LicensePlan/unlicensed``, or when `expiresAt` is present but not finite.
  public init?(
    isValid: Bool,
    planIdentifier: String? = nil,
    expiresAt: Date? = nil
  ) {
    guard Self.isFiniteDate(expiresAt) else { return nil }
    guard isValid else {
      guard planIdentifier == nil, expiresAt == nil else { return nil }
      self.isValid = false
      self.planIdentifier = nil
      self.expiresAt = nil
      return
    }
    let normalizedPlanIdentifier: String?
    if let planIdentifier {
      guard let value = Self.normalizePlanIdentifier(planIdentifier) else { return nil }
      normalizedPlanIdentifier = value
    } else {
      normalizedPlanIdentifier = nil
    }
    self.isValid = true
    self.planIdentifier = normalizedPlanIdentifier
    self.expiresAt = expiresAt
  }

  /// Decodes a normalized provider validation result.
  public init(from decoder: Decoder) throws {
    try Self.rejectUnknownFields(in: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let isValid = try container.decode(Bool.self, forKey: .isValid)
    let planIdentifier = try Self.decodeIfPresentRejectingNull(
      String.self,
      forKey: .planIdentifier,
      in: container
    )
    let expiresAt = try Self.decodeIfPresentRejectingNull(
      Date.self,
      forKey: .expiresAt,
      in: container
    )
    guard Self.isFiniteDate(expiresAt) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt,
        in: container,
        debugDescription: "LicenseValidationResult expiresAt must be finite."
      )
    }
    guard isValid else {
      guard planIdentifier == nil, expiresAt == nil else {
        throw DecodingError.dataCorruptedError(
          forKey: planIdentifier == nil ? .expiresAt : .planIdentifier,
          in: container,
          debugDescription:
            "Invalid LicenseValidationResult values must omit planIdentifier and expiresAt."
        )
      }
      self.isValid = false
      self.planIdentifier = nil
      self.expiresAt = nil
      return
    }
    let normalizedPlanIdentifier: String?
    if let planIdentifier {
      guard let value = Self.normalizePlanIdentifier(planIdentifier) else {
        throw DecodingError.dataCorruptedError(
          forKey: .planIdentifier,
          in: container,
          debugDescription:
            "Valid LicenseValidationResult values must omit blank plan identifiers and must not use reserved plan identifiers."
        )
      }
      normalizedPlanIdentifier = value
    } else {
      normalizedPlanIdentifier = nil
    }
    self.isValid = true
    self.planIdentifier = normalizedPlanIdentifier
    self.expiresAt = expiresAt
  }

  private static func normalizePlanIdentifier(_ identifier: String) -> String? {
    guard let normalizedIdentifier = identifier.licenseKitTrimmedNonEmpty else { return nil }
    guard LicensePlan.isReservedIdentifier(normalizedIdentifier) == false else { return nil }
    return normalizedIdentifier
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
        debugDescription: "LicenseValidationResult contains unknown field '\(key.stringValue)'."
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
          debugDescription:
            "LicenseValidationResult \(key.stringValue) must be omitted instead of null."
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
