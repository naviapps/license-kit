import Foundation

@MainActor
public final class LicenseManager: ObservableObject {
  @Published public private(set) var state: LicenseState

  public let configuration: LicenseConfiguration
  public let refreshPolicy: LicenseRefreshPolicy
  public let initialRestoreError: LicenseError?

  private var store: LicenseStateStore {
    didSet {
      state = store.state
    }
  }

  private let provider: LicenseProvider
  private let offeringProvider: LicenseOfferingProvider?
  private let customerPortalProvider: LicenseCustomerPortalProvider?
  private let activationStorage: LicenseActivationStorage
  private let stateSnapshotStorage: LicenseStateSnapshotStorage?
  private let deviceIdentifierProvider: LicenseDeviceIdentifierProvider?
  private let deviceNameProvider: @Sendable () -> String

  public var plan: LicensePlan { state.plan }
  public var activation: LicenseActivation? { state.activation }
  public var source: LicenseSource? { state.source }
  public var isRefreshing: Bool { state.isRefreshing }
  public var offerings: [LicenseOffering] { state.offerings }
  public var lastValidatedAt: Date? { state.lastValidatedAt }
  public var status: LicenseStatus { state.status }
  public var isLicensed: Bool { state.isLicensed }
  public var gracePeriodExpiresAt: Date? { state.gracePeriodExpiresAt }
  public var lastRefreshFailure: LicenseRefreshFailure? { state.lastRefreshFailure }

  public init(
    provider: LicenseProvider,
    activationStorage: LicenseActivationStorage,
    configuration: LicenseConfiguration = .empty,
    refreshPolicy: LicenseRefreshPolicy = .default,
    offeringProvider: LicenseOfferingProvider? = nil,
    customerPortalProvider: LicenseCustomerPortalProvider? = nil,
    stateSnapshotStorage: LicenseStateSnapshotStorage? = nil,
    deviceIdentifierProvider: LicenseDeviceIdentifierProvider? = nil,
    deviceNameProvider: @escaping @Sendable () -> String = { "Mac" },
    restorePersistedActivation: Bool = true
  ) {
    self.configuration = configuration
    self.provider = provider
    self.offeringProvider = offeringProvider
    self.customerPortalProvider = customerPortalProvider
    self.activationStorage = activationStorage
    self.stateSnapshotStorage = stateSnapshotStorage
    self.refreshPolicy = refreshPolicy
    self.deviceIdentifierProvider = deviceIdentifierProvider
    self.deviceNameProvider = deviceNameProvider

    var initialRestoreError: LicenseError?
    var resolvedActivation: LicenseActivation?
    if restorePersistedActivation {
      do {
        resolvedActivation = try activationStorage.load()
      } catch {
        initialRestoreError = .storageFailure
      }
    }

    let restoredState: LicenseState?
    if let resolvedActivation {
      do {
        restoredState = try Self.loadStateSnapshot(
          from: stateSnapshotStorage,
          matching: resolvedActivation,
          offerings: configuration.offerings
        )
      } catch {
        initialRestoreError = .storageFailure
        restoredState = nil
      }
    } else {
      restoredState = nil
    }

    self.initialRestoreError = initialRestoreError
    let store = LicenseStateStore(
      offerings: configuration.offerings,
      initialActivation: resolvedActivation,
      resolvedPlan: restoredState?.plan,
      lastValidatedAt: restoredState?.lastValidatedAt,
      status: restoredState?.status,
      gracePeriodExpiresAt: restoredState?.gracePeriodExpiresAt,
      lastRefreshFailure: restoredState?.lastRefreshFailure
    )
    self.store = store
    self.state = store.state
  }

  @discardableResult
  public func activate(licenseKey: String) async throws -> LicenseState {
    guard store.status != .activating else {
      throw LicenseError.activationInProgress
    }
    guard store.isRefreshing == false else {
      throw LicenseError.refreshInProgress
    }

    let normalizedKey = LicenseKeyNormalizer.normalize(licenseKey)
    guard normalizedKey.isEmpty == false else {
      throw LicenseError.invalidLicenseKey
    }

    let previousStore = store
    store.setActivating()

    let activation: LicenseActivation
    do {
      activation = try await provider.activate(
        licenseKey: normalizedKey,
        deviceName: deviceName()
      )
    } catch let error as LicenseProviderError {
      restoreAfterActivationFailure(previousStore)
      throw mapProviderError(error)
    } catch let error as LicenseError {
      restoreAfterActivationFailure(previousStore)
      throw error
    } catch {
      restoreAfterActivationFailure(previousStore)
      throw LicenseError.providerRequestFailure(message: String(describing: error))
    }

    let resolvedActivation = activationFillingMissingLicenseKey(
      activation,
      licenseKey: normalizedKey
    )
    do {
      try activationStorage.save(resolvedActivation)
    } catch {
      store = previousStore
      throw LicenseError.storageFailure
    }
    store.applyActivation(resolvedActivation)
    try saveStateSnapshot()
    return state
  }

  @discardableResult
  public func applyActivation(_ activation: LicenseActivation) throws -> LicenseState {
    guard store.status != .activating else {
      throw LicenseError.activationInProgress
    }
    guard store.isRefreshing == false else {
      throw LicenseError.refreshInProgress
    }

    do {
      try activationStorage.save(activation)
    } catch {
      throw LicenseError.storageFailure
    }
    store.applyActivation(activation)
    try saveStateSnapshot()
    return state
  }

  @discardableResult
  public func deactivate() async throws -> LicenseState {
    guard store.status != .activating else {
      throw LicenseError.activationInProgress
    }
    guard store.isRefreshing == false else {
      throw LicenseError.refreshInProgress
    }

    var providerError: LicenseProviderError?
    if let activation = store.activation {
      do {
        try await provider.deactivate(activation)
      } catch let error as LicenseProviderError {
        providerError = error
      } catch {
        providerError = .networkFailure(message: String(describing: error))
      }
    }
    do {
      try activationStorage.delete()
    } catch {
      throw LicenseError.storageFailure
    }

    do {
      try deleteStateSnapshot()
    } catch {
      store.markDeactivated()
      throw LicenseError.storageFailure
    }
    store.markDeactivated()

    if let providerError {
      throw mapProviderError(providerError)
    }
    return state
  }

  public func needsRefresh(
    now: Date = Date(),
    validationInterval: TimeInterval? = nil
  ) -> Bool {
    if let validationInterval {
      precondition(
        validationInterval.isFinite && validationInterval >= 0,
        "LicenseManager needsRefresh validationInterval must be finite and non-negative."
      )
    }

    guard refreshPolicy.isEnabled else { return false }
    guard store.activation != nil else { return false }
    guard let lastValidatedAt = store.lastValidatedAt else { return true }
    let allowedAge = validationInterval ?? refreshPolicy.validationInterval
    return now.timeIntervalSince(lastValidatedAt) >= allowedAge
  }

  @discardableResult
  public func refresh() async throws -> LicenseRefreshResult {
    guard store.status != .activating else {
      return LicenseRefreshResult(outcome: .skippedActivationInProgress, state: state)
    }
    guard refreshPolicy.isEnabled else {
      return LicenseRefreshResult(outcome: .skippedRefreshDisabled, state: state)
    }
    guard store.isRefreshing == false else {
      return LicenseRefreshResult(outcome: .skippedRefreshInProgress, state: state)
    }
    let previousStore = store
    store.setRefreshing(true)
    defer {
      if store.isRefreshing {
        store.setRefreshing(false)
      }
    }

    let now = Date()
    var offeringLoadFailure: LicenseRefreshFailure?
    if let offeringProvider,
      configuration.usesDynamicOfferings,
      let catalogID = configuration.dynamicOfferingsCatalogID
    {
      do {
        let offerings = try await offeringProvider.offerings(forCatalogID: catalogID)
        store.setOfferings(offerings)
      } catch {
        offeringLoadFailure = LicenseRefreshFailure(
          reason: .offeringLoadFailure,
          message: String(describing: error),
          occurredAt: now
        )
      }
    }

    guard let activation = store.activation else {
      if let offeringLoadFailure {
        store.recordRefreshFailure(offeringLoadFailure)
      }
      return finishRefresh(outcome: .skippedNoActivation, offeringLoadFailure: offeringLoadFailure)
    }

    let result: LicenseValidationResult
    let validationIdentifier = activation.activationID ?? deviceIdentifier()
    do {
      result = try await provider.validate(
        activation,
        validationIdentifier: validationIdentifier
      )
    } catch let error as LicenseProviderError {
      return try finishValidationFailure(
        error,
        now: now,
        previousStore: previousStore,
        offeringLoadFailure: offeringLoadFailure
      )
    } catch {
      let providerError = LicenseProviderError.networkFailure(message: String(describing: error))
      return try finishValidationFailure(
        providerError,
        now: now,
        previousStore: previousStore,
        offeringLoadFailure: offeringLoadFailure
      )
    }

    let validationSnapshot = LicenseValidationSnapshot(
      result: result,
      activation: activation,
      checkedAt: now
    )
    do {
      if let updatedActivation = store.applyValidationSnapshot(validationSnapshot) {
        try activationStorage.save(updatedActivation)
      } else {
        try deletePersistedActivation(restoring: previousStore)
      }
    } catch {
      store = previousStore
      throw LicenseError.storageFailure
    }
    if let offeringLoadFailure {
      store.recordRefreshFailure(offeringLoadFailure)
    }
    try saveStateSnapshot()
    return finishRefresh(
      outcome: refreshOutcome(for: store.status),
      offeringLoadFailure: offeringLoadFailure
    )
  }

  public func customerPortalURL() async throws -> URL? {
    guard let customerPortalProvider else { return nil }
    guard let customerID = store.activation?.customerID, customerID.isEmpty == false else {
      return nil
    }
    do {
      return try await customerPortalProvider.customerPortalURL(forCustomerID: customerID)
    } catch let error as LicenseProviderError {
      throw mapProviderError(error)
    } catch {
      throw LicenseError.providerRequestFailure(message: String(describing: error))
    }
  }

  @discardableResult
  public func setOfferings(_ offerings: [LicenseOffering]) -> LicenseState {
    store.setOfferings(offerings)
    return state
  }

  private func deviceName() -> String {
    let name = deviceNameProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "Mac" : name
  }

  private func deviceIdentifier() -> String? {
    guard let identifier = deviceIdentifierProvider?.deviceIdentifier() else { return nil }
    let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedIdentifier.isEmpty ? nil : trimmedIdentifier
  }

  private func activationFillingMissingLicenseKey(
    _ activation: LicenseActivation,
    licenseKey: String
  ) -> LicenseActivation {
    guard activation.licenseKey == nil else { return activation }
    return LicenseActivation(
      source: activation.source,
      licenseKey: licenseKey,
      planID: activation.planID,
      customerID: activation.customerID,
      deviceName: activation.deviceName,
      activationID: activation.activationID,
      activatedAt: activation.activatedAt,
      expiresAt: activation.expiresAt,
      remainingActivations: activation.remainingActivations
    )
  }

  private func restoreAfterActivationFailure(_ previousStore: LicenseStateStore) {
    store = previousStore
    if previousStore.activation == nil {
      try? deleteStateSnapshot()
    }
  }

  private func mapProviderError(_ error: LicenseProviderError) -> LicenseError {
    switch error {
    case .invalidLicense:
      .invalidLicense
    case .activationLimitReached:
      .activationLimitReached
    case .requestFailure(let message), .networkFailure(let message):
      .providerRequestFailure(message: message)
    case .serverFailure(let code):
      .providerServerFailure(statusCode: code)
    case .invalidProviderURL:
      .invalidProviderURL
    case .responseDecodingFailure:
      .unexpectedProviderResponse
    }
  }

  private func applyValidationFailure(
    _ error: LicenseProviderError,
    now: Date
  ) -> LicenseRefreshOutcome {
    switch error {
    case .invalidLicense, .activationLimitReached:
      markInvalid(error, now: now)
      return .invalid
    case .serverFailure:
      markGraceOrInvalidate(
        now: now,
        gracePeriod: refreshPolicy.serverFailureGracePeriod,
        error: error
      )
      return store.status == .invalid ? .invalid : .gracePeriod
    case .networkFailure, .invalidProviderURL, .responseDecodingFailure, .requestFailure:
      markGraceOrInvalidate(
        now: now,
        gracePeriod: refreshPolicy.recoverableFailureGracePeriod,
        error: error
      )
      return store.status == .invalid ? .invalid : .gracePeriod
    }
  }

  private func finishValidationFailure(
    _ error: LicenseProviderError,
    now: Date,
    previousStore: LicenseStateStore,
    offeringLoadFailure: LicenseRefreshFailure?
  ) throws -> LicenseRefreshResult {
    let failure = LicenseRefreshFailure(error: error, occurredAt: now)
    let outcome = applyValidationFailure(error, now: now)
    if outcome == .invalid {
      try deletePersistedActivation(restoring: previousStore)
    }
    try saveStateSnapshot()
    return finishRefresh(
      outcome: outcome,
      validationFailure: failure,
      offeringLoadFailure: offeringLoadFailure
    )
  }

  private func refreshOutcome(for status: LicenseStatus) -> LicenseRefreshOutcome {
    switch status {
    case .expired:
      .expired
    case .invalid:
      .invalid
    default:
      .refreshed
    }
  }

  private func markGraceOrInvalidate(
    now: Date,
    gracePeriod: TimeInterval,
    error: LicenseProviderError
  ) {
    let failure = LicenseRefreshFailure(error: error, occurredAt: now)
    if let gracePeriodExpiresAt = store.gracePeriodExpiresAt {
      guard gracePeriodExpiresAt > now else {
        markInvalid(error, now: now)
        return
      }
      store.markGrace(until: gracePeriodExpiresAt, failure: failure)
      return
    }
    store.markGrace(until: now.addingTimeInterval(gracePeriod), failure: failure)
  }

  private func markInvalid(_ error: LicenseProviderError, now: Date) {
    let validationSnapshot = LicenseValidationSnapshot(
      planID: store.activation?.planID,
      isLicensed: false,
      expiresAt: store.activation?.expiresAt,
      remainingActivations: store.activation?.remainingActivations,
      customerID: store.activation?.customerID,
      checkedAt: now
    )
    _ = store.applyValidationSnapshot(validationSnapshot)
    store.markInvalid(failure: LicenseRefreshFailure(error: error, occurredAt: now))
  }

  private func saveStateSnapshot() throws {
    guard let snapshot = LicenseStateSnapshot(state: store.state) else {
      try deleteStateSnapshot()
      return
    }

    do {
      try stateSnapshotStorage?.save(snapshot)
    } catch {
      throw LicenseError.storageFailure
    }
  }

  private func deleteStateSnapshot() throws {
    do {
      try stateSnapshotStorage?.delete()
    } catch {
      throw LicenseError.storageFailure
    }
  }

  private func deletePersistedActivation(restoring previousStore: LicenseStateStore) throws {
    do {
      try activationStorage.delete()
    } catch {
      store = previousStore
      throw LicenseError.storageFailure
    }
  }

  private static func loadStateSnapshot(
    from stateSnapshotStorage: LicenseStateSnapshotStorage?,
    matching activation: LicenseActivation,
    offerings: [LicenseOffering]
  ) throws -> LicenseState? {
    guard let snapshot = try stateSnapshotStorage?.load() else { return nil }
    guard snapshot.matches(activation: activation) else { return nil }
    return snapshot.restoreState(activation: activation, offerings: offerings)
  }

  private func finishRefresh(
    outcome: LicenseRefreshOutcome,
    validationFailure: LicenseRefreshFailure? = nil,
    offeringLoadFailure: LicenseRefreshFailure? = nil
  ) -> LicenseRefreshResult {
    store.setRefreshing(false)
    return LicenseRefreshResult(
      outcome: outcome,
      state: store.state,
      validationFailure: validationFailure,
      offeringLoadFailure: offeringLoadFailure
    )
  }
}
