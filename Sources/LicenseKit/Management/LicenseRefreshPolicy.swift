import Foundation

public struct LicenseRefreshPolicy: Equatable, Sendable {
  public let isEnabled: Bool
  public let validationInterval: TimeInterval
  public let recoverableFailureGracePeriod: TimeInterval
  public let serverFailureGracePeriod: TimeInterval

  public init(
    validationInterval: TimeInterval,
    recoverableFailureGracePeriod: TimeInterval,
    serverFailureGracePeriod: TimeInterval
  ) throws {
    guard Self.isValidInterval(validationInterval) else {
      throw LicenseRefreshPolicyError.invalidValidationInterval
    }
    guard Self.isValidInterval(recoverableFailureGracePeriod) else {
      throw LicenseRefreshPolicyError.invalidRecoverableFailureGracePeriod
    }
    guard Self.isValidInterval(serverFailureGracePeriod) else {
      throw LicenseRefreshPolicyError.invalidServerFailureGracePeriod
    }
    self.init(
      isEnabled: true,
      uncheckedValidationInterval: validationInterval,
      recoverableFailureGracePeriod: recoverableFailureGracePeriod,
      serverFailureGracePeriod: serverFailureGracePeriod
    )
  }

  private static func isValidInterval(_ interval: TimeInterval) -> Bool {
    interval.isFinite && interval >= 0
  }

  private init(
    isEnabled: Bool,
    uncheckedValidationInterval validationInterval: TimeInterval,
    recoverableFailureGracePeriod: TimeInterval,
    serverFailureGracePeriod: TimeInterval
  ) {
    self.isEnabled = isEnabled
    self.validationInterval = validationInterval
    self.recoverableFailureGracePeriod = recoverableFailureGracePeriod
    self.serverFailureGracePeriod = serverFailureGracePeriod
  }

  public static let `default` = LicenseRefreshPolicy(
    isEnabled: true,
    uncheckedValidationInterval: 24 * 60 * 60,
    recoverableFailureGracePeriod: 7 * 24 * 60 * 60,
    serverFailureGracePeriod: 24 * 60 * 60
  )

  public static let never = LicenseRefreshPolicy(
    isEnabled: false,
    uncheckedValidationInterval: 0,
    recoverableFailureGracePeriod: 0,
    serverFailureGracePeriod: 0
  )
}
