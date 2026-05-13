import Foundation

enum LicenseKeyNormalizer {
  static func normalize(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let collapsed = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
    return collapsed.unicodeScalars
      .filter { isIgnoredScalar($0) == false }
      .map(String.init)
      .joined()
  }

  private static func isIgnoredScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF:
      return true
    default:
      return false
    }
  }
}
