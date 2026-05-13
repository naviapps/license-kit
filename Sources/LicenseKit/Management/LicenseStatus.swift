public enum LicenseStatus: String, Codable, Equatable, CaseIterable, Sendable {
  case unlicensed
  case activating
  case active
  case gracePeriod
  case expired
  case invalid
  case deactivated

  public var isLicensed: Bool {
    self == .active || self == .gracePeriod
  }
}
