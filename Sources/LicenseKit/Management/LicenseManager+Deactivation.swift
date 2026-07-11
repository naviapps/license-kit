extension LicenseManager {
  /// Deactivates the current activation with the provider and clears persisted local state.
  @discardableResult
  public func deactivate() async throws -> LicenseState {
    try throwIfOperationInProgress()
    store.setDeactivating(true)

    let activation = store.activation
    do {
      try deletePersistedActivation()
    } catch {
      store.setDeactivating(false)
      throw error
    }

    deleteStateMetadata()
    store.markDeactivated()
    guard let activation else { return state }

    store.setDeactivating(true)
    do {
      defer {
        if store.isDeactivating {
          store.setDeactivating(false)
        }
      }
      try await providerGateway.deactivate(activation)
    }
    return state
  }
}
