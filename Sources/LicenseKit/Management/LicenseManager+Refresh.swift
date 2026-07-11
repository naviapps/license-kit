import Foundation

extension LicenseManager {
  /// Returns whether the current activation should be refreshed at `now`.
  public func needsRefresh(now: Date = Date()) -> Bool {
    guard now.timeIntervalSinceReferenceDate.isFinite else { return false }
    guard let activation = store.activation else { return false }
    if activation.isExpired(at: now) { return true }
    if store.status == .gracePeriod, let gracePeriodExpiresAt = store.gracePeriodExpiresAt {
      return gracePeriodExpiresAt <= now
    }
    guard refreshPolicy.isEnabled else { return false }
    guard let lastValidatedAt = store.lastValidatedAt else { return true }
    return now.timeIntervalSince(lastValidatedAt) >= refreshPolicy.validationInterval
  }

  /// Refreshes the current activation with the provider when refresh is allowed.
  @discardableResult
  public func refresh() async throws -> LicenseRefreshResult {
    if let inProgressResult = refreshResultIfOperationInProgress() {
      return inProgressResult
    }
    let previousStore = store
    store.setRefreshing(true)
    defer {
      if store.isRefreshing {
        store.setRefreshing(false)
      }
    }

    let refreshStartedAt = Date()
    guard let activation = store.activation else {
      return finishRefresh(outcome: .skippedNoActivation)
    }
    if activation.isExpired(at: refreshStartedAt) {
      return try finishExpiredActivationRefresh(
        activation,
        now: refreshStartedAt
      )
    }
    if store.status == .gracePeriod,
      let gracePeriodExpiresAt = store.gracePeriodExpiresAt,
      gracePeriodExpiresAt <= refreshStartedAt
    {
      return try finishExpiredGracePeriodRefresh(
        now: refreshStartedAt
      )
    }
    guard refreshPolicy.isEnabled else {
      return finishRefresh(outcome: .skippedRefreshDisabled)
    }

    let validationIdentifier = activation.activationIdentifier ?? validationIdentifier()
    do {
      let result = try await providerGateway.validate(
        activation,
        validationIdentifier: validationIdentifier
      )
      return try finishValidationSuccess(
        result,
        activation: activation,
        now: Date(),
        previousStore: previousStore
      )
    } catch let error as CancellationError {
      store = previousStore
      throw error
    } catch let error as LicenseProviderError {
      return try finishValidationFailure(
        error,
        now: Date()
      )
    }
  }

  private func finishValidationSuccess(
    _ result: LicenseValidationResult,
    activation: LicenseActivation,
    now: Date,
    previousStore: LicenseStateStore
  ) throws -> LicenseRefreshResult {
    let validationSnapshot = LicenseValidationSnapshot(
      result: result,
      activation: activation,
      checkedAt: now
    )
    let updatedActivation = store.applyValidationSnapshot(validationSnapshot)
    try persistValidationResult(
      activation: activation,
      updatedActivation: updatedActivation,
      previousStore: previousStore
    )
    return finishRefresh(outcome: refreshOutcome(for: store.status))
  }

  private func persistValidationResult(
    activation: LicenseActivation,
    updatedActivation: LicenseActivation?,
    previousStore: LicenseStateStore
  ) throws {
    guard let updatedActivation else {
      try clearRejectedActivationPersistence(
        rejectedActivation: activation
      )
      return
    }

    do {
      try saveActivation(updatedActivation)
    } catch {
      store = previousStore
      throw error
    }
    saveStateMetadata()
  }

  private func validationIdentifier() -> String? {
    guard let identifier = validationIdentifierProvider() else { return nil }
    return identifier.licenseKitTrimmedNonEmpty
  }

  private func applyValidationFailure(
    _ error: LicenseProviderError,
    failure: LicenseRefreshFailure,
    now: Date
  ) -> LicenseRefreshOutcome {
    switch refreshFailureAction(for: error) {
    case .invalidate:
      markInvalid(failure: failure, now: now)
      return .invalid
    case .useGracePeriod(let gracePeriod):
      markGraceOrInvalidate(
        now: now,
        gracePeriod: gracePeriod,
        failure: failure
      )
      return store.status == .invalid ? .invalid : .gracePeriod
    }
  }

  private func refreshFailureAction(for error: LicenseProviderError) -> RefreshFailureAction {
    switch error {
    case .invalidLicense, .activationLimitReached:
      .invalidate
    case .serverFailure:
      .useGracePeriod(refreshPolicy.serverFailureGracePeriod)
    case .transportFailure, .invalidConfiguration, .responseDecodingFailure, .requestFailure:
      .useGracePeriod(refreshPolicy.failureGracePeriod)
    }
  }

  private func finishValidationFailure(
    _ error: LicenseProviderError,
    now: Date
  ) throws -> LicenseRefreshResult {
    let rejectedActivation = store.activation
    let failure = LicenseRefreshFailure(error: error, occurredAt: now)
    let outcome = applyValidationFailure(
      error,
      failure: failure,
      now: now
    )
    if outcome == .invalid {
      try clearRejectedActivationPersistence(
        rejectedActivation: rejectedActivation
      )
    } else {
      saveStateMetadata()
    }
    return finishRefresh(
      outcome: outcome,
      failure: failure
    )
  }

  private func finishExpiredActivationRefresh(
    _ activation: LicenseActivation,
    now: Date
  ) throws -> LicenseRefreshResult {
    let validationSnapshot = LicenseValidationSnapshot(
      planIdentifier: activation.planIdentifier,
      isLicensed: false,
      expiresAt: activation.expiresAt,
      checkedAt: now
    )
    _ = store.applyValidationSnapshot(validationSnapshot)
    try clearRejectedActivationPersistence(
      rejectedActivation: activation
    )
    return finishRefresh(outcome: .expired)
  }

  private func finishExpiredGracePeriodRefresh(
    now: Date
  ) throws -> LicenseRefreshResult {
    let rejectedActivation = store.activation
    let failure = LicenseRefreshFailure(reason: .gracePeriodExpired, occurredAt: now)
    markInvalid(failure: failure, now: now)
    try clearRejectedActivationPersistence(
      rejectedActivation: rejectedActivation
    )
    return finishRefresh(outcome: .invalid, failure: failure)
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
    failure: LicenseRefreshFailure
  ) {
    if let gracePeriodExpiresAt = store.gracePeriodExpiresAt {
      guard gracePeriodExpiresAt > now else {
        markInvalid(failure: failure, now: now)
        return
      }
      store.markGrace(until: gracePeriodExpiresAt, failure: failure)
      return
    }
    guard gracePeriod > 0 else {
      markInvalid(failure: failure, now: now)
      return
    }
    store.markGrace(until: now.addingTimeInterval(gracePeriod), failure: failure)
  }

  private func markInvalid(failure: LicenseRefreshFailure, now: Date) {
    let validationSnapshot = LicenseValidationSnapshot(
      planIdentifier: store.activation?.planIdentifier,
      isLicensed: false,
      expiresAt: store.activation?.expiresAt,
      checkedAt: now
    )
    _ = store.applyValidationSnapshot(validationSnapshot)
    store.markInvalid(failure: failure)
  }

  private func finishRefresh(
    outcome: LicenseRefreshOutcome,
    failure: LicenseRefreshFailure? = nil
  ) -> LicenseRefreshResult {
    store.setRefreshing(false)
    return LicenseRefreshResult(
      outcome: outcome,
      state: store.state,
      failure: failure
    )
  }

  private enum RefreshFailureAction {
    case invalidate
    case useGracePeriod(TimeInterval)
  }
}
