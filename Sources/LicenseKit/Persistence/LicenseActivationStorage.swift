public protocol LicenseActivationStorage: Sendable {
  func save(_ activation: LicenseActivation) throws
  func load() throws -> LicenseActivation?
  func delete() throws
}
