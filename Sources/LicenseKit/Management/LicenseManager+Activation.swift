import Foundation

extension LicenseManager {
  /// Activates a license through the configured provider and persists the resolved activation.
  @discardableResult
  public func activate(_ request: LicenseActivationRequest) async throws -> LicenseState {
    try throwIfOperationInProgress()

    let normalizedRequest = try normalizeActivationRequest(request)

    let previousStore = store
    store.setActivating()

    do {
      let activation = try await providerGateway.activate(with: normalizedRequest.request)
      let resolvedActivation = try activationByPreservingSubmittedLicenseKey(
        activation,
        normalizedSubmittedLicenseKey: normalizedRequest.normalizedSubmittedLicenseKey
      )
      let now = Date()
      guard resolvedActivation.isExpired(at: now) == false else {
        throw LicenseError.expiredLicense
      }
      try saveActivation(resolvedActivation)
      store.applyActivation(resolvedActivation, now: now)
    } catch {
      rollbackActivationAttempt(to: previousStore)
      throw error
    }
    saveStateMetadata()
    return state
  }

  /// Persists an already resolved activation without calling the provider.
  @discardableResult
  public func applyActivation(_ activation: LicenseActivation) throws -> LicenseState {
    try throwIfOperationInProgress()
    let now = Date()
    guard activation.isExpired(at: now) == false else {
      throw LicenseError.expiredLicense
    }

    try saveActivation(activation)
    store.applyActivation(activation, now: now)
    saveStateMetadata()
    return state
  }

  private func activationByPreservingSubmittedLicenseKey(
    _ activation: LicenseActivation,
    normalizedSubmittedLicenseKey: String?
  ) throws -> LicenseActivation {
    guard let normalizedSubmittedLicenseKey else { return activation }
    guard activation.licenseKey == nil else { return activation }
    guard
      let updatedActivation = LicenseActivation(
        source: activation.source,
        planIdentifier: activation.planIdentifier,
        activatedAt: activation.activatedAt,
        licenseKey: normalizedSubmittedLicenseKey,
        activationIdentifier: activation.activationIdentifier,
        expiresAt: activation.expiresAt
      )
    else {
      throw LicenseError.unexpectedProviderResponse
    }
    return updatedActivation
  }

  private func normalizeActivationRequest(
    _ request: LicenseActivationRequest
  ) throws -> NormalizedActivationRequest {
    switch request {
    case .automatic:
      return NormalizedActivationRequest(
        request: .automatic,
        normalizedSubmittedLicenseKey: nil
      )
    case .licenseKey(let licenseKey):
      let normalizedLicenseKey = LicenseKeyNormalizer.normalize(licenseKey)
      guard normalizedLicenseKey.isEmpty == false else {
        throw LicenseError.invalidLicenseKey
      }
      return NormalizedActivationRequest(
        request: .licenseKey(normalizedLicenseKey),
        normalizedSubmittedLicenseKey: normalizedLicenseKey
      )
    }
  }

  private func rollbackActivationAttempt(to previousStore: LicenseStateStore) {
    store = previousStore
    if previousStore.activation == nil {
      deleteStateMetadata()
    }
  }

  private struct NormalizedActivationRequest {
    let request: LicenseActivationRequest
    let normalizedSubmittedLicenseKey: String?
  }
}
