# ``LicenseKit``

Manage Apple platform app license state through provider-backed activation,
validation, refresh, and persistence flows.

## Overview

LicenseKit is a provider-neutral state layer for Apple platform app licensing.
Host apps implement ``LicenseProvider``, choose persistence, and use
``LicenseManager`` as the app-facing state boundary. Provider validation remains
the source of truth; persisted state is only a local restore aid.

LicenseKit does not provide purchase flows, catalog loading, account-management
flows, provider SDKs, UI, or provider-specific display logic.

## Creating a Manager

Implement ``LicenseProvider`` for your backend or entitlement source, create one
``LicenseManager`` with secure activation storage, then call
``LicenseManager/activate(_:)``, ``LicenseManager/refresh()``, and
``LicenseManager/deactivate()`` from the app layer.

Create a manager with an explicit provider and secure activation storage. The
`MyLicenseProvider` and `licenseAPI` values represent your app's provider and
backend client. ``LicenseManager`` is `@MainActor` and publishes
``LicenseState``, so keep it at the app or UI boundary:

```swift
let manager = LicenseManager(
  provider: MyLicenseProvider(licenseAPI: licenseAPI),
  activationStorage: KeychainLicenseActivationStorage(
    service: "com.example.app",
    account: "license"
  ),
  refreshPolicy: .default
)
```

Mutating operations return the updated ``LicenseState``. ``LicenseState``
normalizes impossible combinations such as licensed statuses without an
activation, expired local values, or grace-period state without an expiration.

```swift
try await manager.activate(.licenseKey(enteredLicenseKey))

if manager.needsRefresh() {
  let result = try await manager.refresh()
  switch result.outcome {
  case .refreshed:
    break
  case .gracePeriod:
    if let gracePeriodExpiresAt = result.state.gracePeriodExpiresAt {
      showOfflineGracePeriodNotice(until: gracePeriodExpiresAt)
    }
  case .expired, .invalid:
    showLicenseRequiredScreen()
  case .skippedActivationInProgress, .skippedRefreshDisabled,
    .skippedRefreshInProgress, .skippedNoActivation:
    break
  }
}
```

## Optional Configuration

Start with the minimal manager setup, then add optional configuration only when
the app needs it:

- Pass `stateSnapshotStorage` to restore local validation metadata such as the
  last validation time, grace period, and last refresh failure.
- Pass `validationIdentifierProvider` when your provider needs a stable
  local identifier and the activation does not include an
  ``LicenseActivation/activationID``.
- Use ``LicenseRefreshPolicy/never`` for entitlement sources that should not run
  provider validation through LicenseKit.
- Pass a custom Keychain accessibility value or implement
  ``LicenseActivationStorage`` / ``LicenseStateSnapshotStorage`` when the
  default persistence does not fit your app.

## State Lifecycle

``LicenseManager`` keeps one active activation at a time. Activation moves the
state from unlicensed to active. Successful refreshes keep it active; temporary
provider failures move it into a grace period; definitive invalid or expired
results clear the activation. Deactivation clears persisted activation state.

## Provider Contract

``LicenseProvider/activate(_:)`` receives a ``LicenseActivationRequest`` and
returns a non-expired ``LicenseActivation`` or throws ``LicenseProviderError``.
Use ``LicenseActivationRequest/licenseKey(_:)`` for user-entered keys and
``LicenseActivationRequest/automatic`` for local or runtime entitlements that do
not have a license key. Validation returns ``LicenseValidationResult`` for
completed checks and throws provider errors only when validation could not be
completed, allowing ``LicenseManager`` to apply grace-period handling. Expired
activations become expired without entering the grace period.

During validation, the provider receives the full ``LicenseActivation``.
``LicenseManager`` also supplies a validation identifier using
``LicenseActivation/activationID`` when available, then the configured validation
identifier provider as a fallback.

Use ``LicenseState/source`` or ``LicenseManager/source`` only when the app needs
to distinguish which provider supplied the single active activation.

## Persistence

License keys are sensitive application data. Use
``KeychainLicenseActivationStorage`` or another secure
``LicenseActivationStorage`` implementation in production apps. Avoid logging
raw license keys, activation identifiers, or provider request bodies.

The built-in storage types are defaults, not a required persistence layer.
Implement ``LicenseActivationStorage`` or ``LicenseStateSnapshotStorage`` for
app group, file, database, synchronizable Keychain, access-group Keychain, or
other host-specific persistence. Storage failures surface as
``LicenseError/storageFailure(message:)``.

``KeychainLicenseActivationStorage`` defaults to
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and accepts a custom Keychain
accessibility value when the app needs a stricter policy.

``LicenseStateSnapshot`` stores restorable licensed state only. Terminal,
incomplete, expired, or mismatched persisted state is treated as no longer
licensed and removed from persistence when possible.

## Topics

### Management

- ``LicenseManager``
- ``LicenseState``
- ``LicenseStatus``
- ``LicenseRefreshPolicy``
- ``LicenseRefreshResult``
- ``LicenseRefreshOutcome``
- ``LicenseRefreshFailure``
- ``LicenseRefreshFailureReason``

### Provider Contracts

- ``LicenseProvider``
- ``UnavailableLicenseProvider``

### Values

- ``LicenseActivation``
- ``LicenseActivationRequest``
- ``LicenseSource``
- ``LicensePlan``
- ``LicenseValidationResult``

### Persistence

- ``LicenseActivationStorage``
- ``KeychainLicenseActivationStorage``

### Advanced Persistence

- ``LicenseStateSnapshot``
- ``LicenseStateSnapshot/ActivationIdentity``
- ``LicenseStateSnapshotStorage``
- ``UserDefaultsLicenseStateSnapshotStorage``

### Errors

- ``LicenseError``
- ``LicenseProviderError``
- ``LicenseRefreshPolicyError``
