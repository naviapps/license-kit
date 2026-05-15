import Foundation

/// The main license state coordinator for application code.
@MainActor
public final class LicenseManager: ObservableObject {
  /// The current normalized license state.
  @Published public private(set) var state: LicenseState

  /// The policy used to decide when refreshes are needed and how failures are handled.
  public let refreshPolicy: LicenseRefreshPolicy

  /// A storage error captured while restoring persisted state during initialization.
  public let initialRestoreError: LicenseError?

  private var store: LicenseStateStore {
    didSet {
      state = store.state
    }
  }

  private let provider: LicenseProvider
  private let activationStorage: LicenseActivationStorage
  private let stateSnapshotStorage: LicenseStateSnapshotStorage?
  private let validationIdentifierProvider: @Sendable () -> String?

  public var plan: LicensePlan { state.plan }
  public var activation: LicenseActivation? { state.activation }
  public var source: LicenseSource? { state.source }
  public var isActivating: Bool { state.isActivating }
  public var isRefreshing: Bool { state.isRefreshing }
  public var lastValidatedAt: Date? { state.lastValidatedAt }
  public var status: LicenseStatus { state.status }
  public var isLicensed: Bool { state.isLicensed }
  public var gracePeriodExpiresAt: Date? { state.gracePeriodExpiresAt }
  public var lastRefreshFailure: LicenseRefreshFailure? { state.lastRefreshFailure }

  /// Creates a manager from a provider, activation storage, and optional state snapshot storage.
  public init(
    provider: LicenseProvider,
    activationStorage: LicenseActivationStorage,
    refreshPolicy: LicenseRefreshPolicy = .default,
    stateSnapshotStorage: LicenseStateSnapshotStorage? = nil,
    validationIdentifierProvider: @escaping @Sendable () -> String? = { nil },
    restorePersistedActivation: Bool = true
  ) {
    self.provider = provider
    self.activationStorage = activationStorage
    self.stateSnapshotStorage = stateSnapshotStorage
    self.refreshPolicy = refreshPolicy
    self.validationIdentifierProvider = validationIdentifierProvider

    var initialRestoreError: LicenseError?
    var resolvedActivation: LicenseActivation?
    if restorePersistedActivation {
      do {
        resolvedActivation = try activationStorage.load()
      } catch {
        initialRestoreError = .storageFailure(error)
      }
    }

    let restoredState: LicenseState?
    if let resolvedActivation {
      do {
        restoredState = try Self.loadStateSnapshot(
          from: stateSnapshotStorage,
          matching: resolvedActivation
        )
      } catch {
        initialRestoreError = .storageFailure(error)
        restoredState = nil
      }
    } else {
      restoredState = nil
    }

    let store = LicenseStateStore(
      initialActivation: resolvedActivation,
      resolvedPlan: restoredState?.plan,
      lastValidatedAt: restoredState?.lastValidatedAt,
      status: restoredState?.status,
      gracePeriodExpiresAt: restoredState?.gracePeriodExpiresAt,
      lastRefreshFailure: restoredState?.lastRefreshFailure
    )
    if restorePersistedActivation, resolvedActivation != nil, store.activation == nil {
      do {
        try activationStorage.delete()
        try stateSnapshotStorage?.delete()
      } catch {
        initialRestoreError = .storageFailure(error)
      }
    }

    self.initialRestoreError = initialRestoreError
    self.store = store
    self.state = store.state
  }

  /// Activates a license key through the configured provider and persists the resolved activation.
  @discardableResult
  public func activate(licenseKey: String) async throws -> LicenseState {
    guard store.isActivating == false else {
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
      activation = try await provider.activate(licenseKey: normalizedKey)
    } catch let error as LicenseProviderError {
      restoreAfterActivationFailure(previousStore)
      throw mapProviderError(error)
    } catch let error as LicenseError {
      restoreAfterActivationFailure(previousStore)
      throw error
    } catch {
      restoreAfterActivationFailure(previousStore)
      throw LicenseError.requestFailure(message: String(describing: error))
    }

    let resolvedActivation = activationFillingMissingLicenseKey(
      activation,
      licenseKey: normalizedKey
    )
    guard resolvedActivation.isExpired == false else {
      restoreAfterActivationFailure(previousStore)
      throw LicenseError.expiredLicense
    }
    do {
      try activationStorage.save(resolvedActivation)
    } catch {
      store = previousStore
      throw LicenseError.storageFailure(error)
    }
    store.applyActivation(resolvedActivation)
    try saveStateSnapshot()
    return state
  }

  /// Persists an already resolved activation without calling the provider.
  @discardableResult
  public func applyActivation(_ activation: LicenseActivation) throws -> LicenseState {
    guard store.isActivating == false else {
      throw LicenseError.activationInProgress
    }
    guard store.isRefreshing == false else {
      throw LicenseError.refreshInProgress
    }
    guard activation.isExpired == false else {
      throw LicenseError.expiredLicense
    }

    do {
      try activationStorage.save(activation)
    } catch {
      throw LicenseError.storageFailure(error)
    }
    store.applyActivation(activation)
    try saveStateSnapshot()
    return state
  }

  /// Deactivates the current activation with the provider and clears persisted local state.
  @discardableResult
  public func deactivate() async throws -> LicenseState {
    guard store.isActivating == false else {
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
        providerError = .transportFailure(message: String(describing: error))
      }
    }
    do {
      try activationStorage.delete()
    } catch {
      throw LicenseError.storageFailure(error)
    }

    do {
      try deleteStateSnapshot()
    } catch {
      store.markDeactivated()
      throw LicenseError.storageFailure(error)
    }
    store.markDeactivated()

    if let providerError {
      throw mapProviderError(providerError)
    }
    return state
  }

  /// Returns whether the current activation should be refreshed at `now`.
  public func needsRefresh(now: Date = Date()) -> Bool {
    guard let activation = store.activation else { return false }
    if activation.isExpired(at: now) { return true }
    guard refreshPolicy.isEnabled else { return false }
    guard let lastValidatedAt = store.lastValidatedAt else { return true }
    return now.timeIntervalSince(lastValidatedAt) >= refreshPolicy.validationInterval
  }

  /// Refreshes the current activation with the provider when refresh is allowed.
  @discardableResult
  public func refresh() async throws -> LicenseRefreshResult {
    guard store.isActivating == false else {
      return LicenseRefreshResult(outcome: .skippedActivationInProgress, state: state)
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
    guard let activation = store.activation else {
      return finishRefresh(outcome: .skippedNoActivation)
    }
    if activation.isExpired(at: now) {
      return try finishExpiredActivationRefresh(
        activation,
        now: now,
        previousStore: previousStore
      )
    }
    guard refreshPolicy.isEnabled else {
      return finishRefresh(outcome: .skippedRefreshDisabled)
    }

    let result: LicenseValidationResult
    let validationIdentifier = activation.activationID ?? validationIdentifier()
    do {
      result = try await provider.validate(
        activation,
        validationIdentifier: validationIdentifier
      )
    } catch let error as LicenseProviderError {
      return try finishValidationFailure(
        error,
        now: now,
        previousStore: previousStore
      )
    } catch {
      let providerError = LicenseProviderError.transportFailure(message: String(describing: error))
      return try finishValidationFailure(
        providerError,
        now: now,
        previousStore: previousStore
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
      throw LicenseError.storageFailure(error)
    }
    try saveStateSnapshot()
    return finishRefresh(outcome: refreshOutcome(for: store.status))
  }

  private func validationIdentifier() -> String? {
    guard let identifier = validationIdentifierProvider() else { return nil }
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
      activationID: activation.activationID,
      activatedAt: activation.activatedAt,
      expiresAt: activation.expiresAt
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
    case .requestFailure, .transportFailure:
      .requestFailure(message: error.normalizedMessage ?? LicenseError.defaultRequestFailureMessage)
    case .serverFailure(let code):
      .serverFailure(statusCode: code)
    case .invalidConfiguration:
      .invalidProviderConfiguration
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
    case .transportFailure, .invalidConfiguration, .responseDecodingFailure, .requestFailure:
      markGraceOrInvalidate(
        now: now,
        gracePeriod: refreshPolicy.failureGracePeriod,
        error: error
      )
      return store.status == .invalid ? .invalid : .gracePeriod
    }
  }

  private func finishValidationFailure(
    _ error: LicenseProviderError,
    now: Date,
    previousStore: LicenseStateStore
  ) throws -> LicenseRefreshResult {
    let failure = LicenseRefreshFailure(error: error, occurredAt: now)
    let outcome = applyValidationFailure(error, now: now)
    if outcome == .invalid {
      try deletePersistedActivation(restoring: previousStore)
    }
    try saveStateSnapshot()
    return finishRefresh(
      outcome: outcome,
      validationFailure: failure
    )
  }

  private func finishExpiredActivationRefresh(
    _ activation: LicenseActivation,
    now: Date,
    previousStore: LicenseStateStore
  ) throws -> LicenseRefreshResult {
    let validationSnapshot = LicenseValidationSnapshot(
      planID: activation.planID,
      isLicensed: false,
      expiresAt: activation.expiresAt,
      checkedAt: now
    )
    _ = store.applyValidationSnapshot(validationSnapshot)
    try deletePersistedActivation(restoring: previousStore)
    try saveStateSnapshot()
    return finishRefresh(outcome: .expired)
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
      throw LicenseError.storageFailure(error)
    }
  }

  private func deleteStateSnapshot() throws {
    do {
      try stateSnapshotStorage?.delete()
    } catch {
      throw LicenseError.storageFailure(error)
    }
  }

  private func deletePersistedActivation(restoring previousStore: LicenseStateStore) throws {
    do {
      try activationStorage.delete()
    } catch {
      store = previousStore
      throw LicenseError.storageFailure(error)
    }
  }

  private static func loadStateSnapshot(
    from stateSnapshotStorage: LicenseStateSnapshotStorage?,
    matching activation: LicenseActivation
  ) throws -> LicenseState? {
    guard let snapshot = try stateSnapshotStorage?.load() else { return nil }
    guard snapshot.matches(activation: activation) else { return nil }
    return snapshot.restoreState(activation: activation)
  }

  private func finishRefresh(
    outcome: LicenseRefreshOutcome,
    validationFailure: LicenseRefreshFailure? = nil
  ) -> LicenseRefreshResult {
    store.setRefreshing(false)
    return LicenseRefreshResult(
      outcome: outcome,
      state: store.state,
      validationFailure: validationFailure
    )
  }
}
