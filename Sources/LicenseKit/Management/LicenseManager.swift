import Foundation

/// The main license state coordinator for application code.
@MainActor
public final class LicenseManager {
  /// The current normalized license state.
  public private(set) var state: LicenseState

  /// The policy used to decide when refreshes are needed and how failures are handled.
  public let refreshPolicy: LicenseRefreshPolicy

  /// A storage error captured while restoring persisted state during initialization.
  public let initialRestoreError: LicenseError?

  var store: LicenseStateStore {
    didSet {
      state = store.state
    }
  }

  let providerGateway: LicenseProviderGateway
  let activationStorage: any LicenseActivationStorage
  let stateMetadataStorage: (any LicenseStateMetadataStorage)?
  let validationIdentifierProvider: @Sendable () -> String?

  /// The current license plan.
  public var plan: LicensePlan { state.plan }
  /// The current activation, when the manager has one.
  public var activation: LicenseActivation? { state.activation }
  /// The source of the current activation, when available.
  public var source: LicenseSource? { state.source }
  /// Whether an activation request is running.
  public var isActivating: Bool { state.isActivating }
  /// Whether a refresh request is running.
  public var isRefreshing: Bool { state.isRefreshing }
  /// Whether a deactivation request is running.
  public var isDeactivating: Bool { state.isDeactivating }
  /// The last activation or validation decision time.
  public var lastValidatedAt: Date? { state.lastValidatedAt }
  /// The current license status.
  public var status: LicenseStatus { state.status }
  /// Whether the current state grants licensed access.
  public var isLicensed: Bool { state.isLicensed }
  /// The current grace-period deadline, when in grace period.
  public var gracePeriodExpiresAt: Date? { state.gracePeriodExpiresAt }
  /// The refresh failure that caused the current grace-period state.
  public var lastRefreshFailure: LicenseRefreshFailure? { state.lastRefreshFailure }

  /// Creates a manager from a provider, activation storage, and optional state metadata storage.
  public init(
    provider: any LicenseProvider,
    activationStorage: any LicenseActivationStorage,
    refreshPolicy: LicenseRefreshPolicy = .default,
    stateMetadataStorage: (any LicenseStateMetadataStorage)? = nil,
    validationIdentifierProvider: @escaping @Sendable () -> String? = { nil },
    restorePersistedActivation: Bool = true
  ) {
    self.providerGateway = LicenseProviderGateway(provider: provider)
    self.activationStorage = activationStorage
    self.stateMetadataStorage = stateMetadataStorage
    self.refreshPolicy = refreshPolicy
    self.validationIdentifierProvider = validationIdentifierProvider

    let initialRestore = LicenseStateRestorer.restore(
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage,
      restorePersistedActivation: restorePersistedActivation
    )

    let store = LicenseStateStore(
      initialActivation: initialRestore.activation,
      resolvedPlan: initialRestore.state?.plan,
      lastValidatedAt: initialRestore.state?.lastValidatedAt,
      status: initialRestore.state?.status,
      gracePeriodExpiresAt: initialRestore.state?.gracePeriodExpiresAt,
      lastRefreshFailure: initialRestore.state?.lastRefreshFailure
    )
    var initialRestoreError = initialRestore.error
    if let cleanupError = LicenseStateRestorer.cleanupRejectedPersistence(
      restorePersistedActivation: restorePersistedActivation,
      restoredActivation: initialRestore.activation,
      restoredState: initialRestore.state,
      normalizedState: store.state,
      initialRestoreError: initialRestoreError,
      activationStorage: activationStorage,
      stateMetadataStorage: stateMetadataStorage
    ) {
      initialRestoreError = cleanupError
    }

    self.initialRestoreError = initialRestoreError
    self.store = store
    self.state = store.state
  }

  func throwIfOperationInProgress() throws {
    if let operation = currentOperation {
      throw operation.licenseError
    }
  }

  func refreshResultIfOperationInProgress() -> LicenseRefreshResult? {
    guard let operation = currentOperation else { return nil }
    return LicenseRefreshResult(
      outcome: operation.skippedRefreshOutcome,
      state: state
    )
  }

  private var currentOperation: ActiveOperation? {
    if store.isActivating {
      return .activation
    }
    if store.isRefreshing {
      return .refresh
    }
    if store.isDeactivating {
      return .deactivation
    }
    return nil
  }

  private enum ActiveOperation {
    case activation
    case refresh
    case deactivation

    var licenseError: LicenseError {
      switch self {
      case .activation:
        .activationInProgress
      case .refresh:
        .refreshInProgress
      case .deactivation:
        .deactivationInProgress
      }
    }

    var skippedRefreshOutcome: LicenseRefreshOutcome {
      switch self {
      case .activation:
        .skippedActivationInProgress
      case .refresh:
        .skippedRefreshInProgress
      case .deactivation:
        .skippedDeactivationInProgress
      }
    }
  }
}
