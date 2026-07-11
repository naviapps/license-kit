import Foundation

struct LicenseValidationSnapshot: Sendable, Equatable {
  let planIdentifier: String?
  let isLicensed: Bool
  let expiresAt: Date?
  let checkedAt: Date

  init(
    planIdentifier: String?,
    isLicensed: Bool,
    expiresAt: Date?,
    checkedAt: Date = Date()
  ) {
    self.planIdentifier = planIdentifier
    self.isLicensed = isLicensed
    self.expiresAt = expiresAt
    self.checkedAt = checkedAt
  }

  init(
    result: LicenseValidationResult,
    activation: LicenseActivation,
    checkedAt: Date = Date()
  ) {
    guard result.isValid else {
      self.init(
        planIdentifier: nil,
        isLicensed: false,
        expiresAt: nil,
        checkedAt: checkedAt
      )
      return
    }

    self.init(
      planIdentifier: result.planIdentifier ?? activation.planIdentifier,
      isLicensed: true,
      expiresAt: result.expiresAt,
      checkedAt: checkedAt
    )
  }
}
