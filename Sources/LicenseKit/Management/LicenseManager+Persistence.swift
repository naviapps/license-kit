import Foundation

extension LicenseManager {
  func saveActivation(_ activation: LicenseActivation) throws {
    do {
      try activationStorage.save(activation)
    } catch {
      throw LicenseError.storageFailure(normalizing: error)
    }
  }

  func saveStateMetadata() {
    guard let metadata = LicenseStateMetadata(state: store.state) else {
      deleteStateMetadata()
      return
    }

    guard let metadataData = try? JSONEncoder().encode(metadata) else {
      deleteStateMetadata()
      return
    }
    try? stateMetadataStorage?.save(metadataData)
  }

  func deleteStateMetadata() {
    try? stateMetadataStorage?.delete()
  }

  func clearRejectedActivationPersistence(
    rejectedActivation: LicenseActivation?
  ) throws {
    do {
      try deletePersistedActivation()
      deleteStateMetadata()
    } catch {
      saveRejectedActivationMetadata(rejectedActivation)
      throw error
    }
  }

  func deletePersistedActivation() throws {
    do {
      try activationStorage.delete()
    } catch {
      throw LicenseError.storageFailure(normalizing: error)
    }
  }

  private func saveRejectedActivationMetadata(_ rejectedActivation: LicenseActivation?) {
    guard let rejectedActivation else {
      deleteStateMetadata()
      return
    }
    let activationIdentity = LicenseStateMetadata.ActivationIdentity(
      activation: rejectedActivation
    )
    guard
      let metadata = LicenseStateMetadata(
        activationIdentity: activationIdentity,
        plan: .unlicensed,
        lastValidatedAt: store.lastValidatedAt,
        status: store.status,
        gracePeriodExpiresAt: nil,
        lastRefreshFailure: store.lastRefreshFailure
      ),
      let metadataData = try? JSONEncoder().encode(metadata)
    else {
      deleteStateMetadata()
      return
    }

    try? stateMetadataStorage?.save(metadataData)
  }
}
