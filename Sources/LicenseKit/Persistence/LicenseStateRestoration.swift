import Foundation

struct LicenseInitialRestore: Sendable {
  let activation: LicenseActivation?
  let state: LicenseState?
  let error: LicenseError?
}

enum LicenseStateRestorer {
  static func restore(
    activationStorage: any LicenseActivationStorage,
    stateMetadataStorage: (any LicenseStateMetadataStorage)?,
    restorePersistedActivation: Bool
  ) -> LicenseInitialRestore {
    var restoreError: LicenseError?
    let activation: LicenseActivation?
    if restorePersistedActivation {
      do {
        activation = try activationStorage.load()
      } catch {
        activation = nil
        restoreError = .storageFailure(normalizing: error)
      }
    } else {
      activation = nil
    }

    let state: LicenseState?
    if let activation {
      do {
        state = try restoreStateMetadata(
          from: stateMetadataStorage,
          matching: activation
        )
      } catch {
        restoreError = .storageFailure(normalizing: error)
        state = nil
      }
    } else {
      state = nil
    }

    return LicenseInitialRestore(
      activation: activation,
      state: state,
      error: restoreError
    )
  }

  static func cleanupRejectedPersistence(
    restorePersistedActivation: Bool,
    restoredActivation: LicenseActivation?,
    restoredState: LicenseState?,
    normalizedState: LicenseState,
    initialRestoreError: LicenseError?,
    activationStorage: any LicenseActivationStorage,
    stateMetadataStorage: (any LicenseStateMetadataStorage)?
  ) -> LicenseError? {
    guard restorePersistedActivation else { return nil }

    if restoredActivation != nil, normalizedState.activation == nil {
      do {
        try activationStorage.delete()
      } catch {
        return .storageFailure(normalizing: error)
      }
      try? stateMetadataStorage?.delete()
      return nil
    }

    guard initialRestoreError == nil else { return nil }
    if restoredActivation == nil || restoredState == nil {
      try? stateMetadataStorage?.delete()
    }
    return nil
  }

  private static func restoreStateMetadata(
    from stateMetadataStorage: (any LicenseStateMetadataStorage)?,
    matching activation: LicenseActivation
  ) throws -> LicenseState? {
    guard let metadataData = try stateMetadataStorage?.load() else { return nil }
    let metadata: LicenseStateMetadata
    do {
      metadata = try JSONDecoder().decode(LicenseStateMetadata.self, from: metadataData)
    } catch {
      try? stateMetadataStorage?.delete()
      throw LicenseError.storageFailure(normalizing: error)
    }
    guard metadata.matches(activation: activation) else { return nil }
    return metadata.restoreState(activation: activation)
  }
}
