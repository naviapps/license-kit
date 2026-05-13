import Foundation

struct LicenseValidationSnapshot: Sendable, Equatable {
  let planID: String?
  let isLicensed: Bool
  let expiresAt: Date?
  let remainingActivations: Int?
  let customerID: String?
  let checkedAt: Date

  init(
    planID: String?,
    isLicensed: Bool,
    expiresAt: Date?,
    remainingActivations: Int?,
    customerID: String? = nil,
    checkedAt: Date = Date()
  ) {
    if let remainingActivations {
      precondition(
        remainingActivations >= 0,
        "LicenseValidationSnapshot remainingActivations must not be negative."
      )
    }

    self.planID = planID?.licenseKitTrimmedNonEmpty
    self.isLicensed = isLicensed
    self.expiresAt = expiresAt
    self.remainingActivations = remainingActivations
    self.customerID = customerID?.licenseKitTrimmedNonEmpty
    self.checkedAt = checkedAt
  }

  init(
    result: LicenseValidationResult,
    activation: LicenseActivation,
    checkedAt: Date = Date()
  ) {
    self.init(
      planID: result.planID ?? activation.planID,
      isLicensed: result.isValid,
      expiresAt: result.expiresAt,
      remainingActivations: result.remainingActivations,
      customerID: result.customerID,
      checkedAt: checkedAt
    )
  }
}
