import Foundation

extension String {
  var licenseKitTrimmedNonEmpty: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

enum LicenseKeyNormalizer {
  static func normalize(_ value: String) -> String {
    var normalized = String.UnicodeScalarView()
    normalized.reserveCapacity(value.unicodeScalars.count)

    for scalar in value.unicodeScalars where shouldKeep(scalar) {
      normalized.append(scalar)
    }

    return String(normalized)
  }

  private static func shouldKeep(_ scalar: Unicode.Scalar) -> Bool {
    guard scalar.properties.isWhitespace == false else {
      return false
    }

    switch scalar.properties.generalCategory {
    case .control, .format:
      return false
    default:
      return true
    }
  }
}
