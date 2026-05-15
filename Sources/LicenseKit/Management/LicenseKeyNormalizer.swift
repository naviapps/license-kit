import Foundation

enum LicenseKeyNormalizer {
  static func normalize(_ value: String) -> String {
    value.unicodeScalars
      .filter { shouldKeep($0) }
      .map(String.init)
      .joined()
  }

  private static func shouldKeep(_ scalar: Unicode.Scalar) -> Bool {
    CharacterSet.whitespacesAndNewlines.contains(scalar) == false
      && isIgnoredFormatScalar(scalar) == false
  }

  // Ignore invisible format characters commonly introduced by copy and paste.
  private static func isIgnoredFormatScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF:
      return true
    default:
      return false
    }
  }
}
