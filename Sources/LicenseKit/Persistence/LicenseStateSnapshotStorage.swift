public protocol LicenseStateSnapshotStorage: Sendable {
  func save(_ snapshot: LicenseStateSnapshot) throws
  func load() throws -> LicenseStateSnapshot?
  func delete() throws
}
