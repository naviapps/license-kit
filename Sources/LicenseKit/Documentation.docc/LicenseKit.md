# ``LicenseKit``

Manage app license state through provider-backed activation, validation, and
refresh flows.

## Overview

LicenseKit defines a small provider-neutral core for macOS app licensing. It
does not call a billing or licensing service directly. Host apps implement the
provider protocols, choose secure persistence, and use ``LicenseManager`` as the
app-facing state boundary.

Import `LicenseKit` when you want to:

- Activate and deactivate license keys with ``LicenseManager``.
- Validate persisted activations through ``LicenseProvider``.
- Preserve local activation with ``LicenseActivationStorage``.
- Configure validation intervals and grace periods with
  ``LicenseRefreshPolicy``.
- Expose offerings and customer portal links through injectable providers.

Provider validation remains the source of truth. Persisted state is only a local
snapshot used to restore the last known app-facing state.

The package keeps one Swift module and groups source files by API
responsibility: core values, management, provider contracts, and persistence.

## Creating a Manager

The minimal integration path is:

1. Implement ``LicenseProvider`` for your backend.
2. Create one ``LicenseManager`` with secure activation storage.
3. Call ``LicenseManager/activate(licenseKey:)`` when the user enters a key.
4. Call ``LicenseManager/refresh()`` when the app starts or resumes.
5. Call ``LicenseManager/deactivate()`` when the user removes the license.

LicenseKit owns local state, persistence boundaries, refresh policy, and public
value types. Your app owns the backend client, UI, billing screens, and any
logging. The `api` object in the examples represents your own backend client.

Create a manager with an explicit provider and secure activation storage:

```swift
let manager = LicenseManager(
  provider: MyLicenseProvider(),
  activationStorage: KeychainLicenseActivationStorage(
    service: "com.example.app",
    account: "license"
  ),
  refreshPolicy: .default
)
```

Use ``LicenseManager/activate(licenseKey:)``,
``LicenseManager/refresh()``, and ``LicenseManager/deactivate()`` from the app
layer. Mutating operations return the updated ``LicenseState``.

```swift
let state = try await manager.activate(licenseKey: enteredLicenseKey)

if manager.needsRefresh() {
  let result = try await manager.refresh()
  switch result.outcome {
  case .refreshed:
    break
  case .gracePeriod:
    showOfflineGracePeriodNotice(until: result.state.gracePeriodExpiresAt)
  case .expired, .invalid:
    showLicenseRequiredScreen()
  case .skippedActivationInProgress, .skippedRefreshDisabled,
    .skippedRefreshInProgress, .skippedNoActivation:
    break
  }
}
```

Dynamic offerings and customer portal links are optional. Add
``LicenseOfferingProvider`` or ``LicenseCustomerPortalProvider`` only when your
app needs those flows.

Use ``LicenseRefreshPolicy/never`` for license sources whose entitlement state
is supplied externally and should not be refreshed by LicenseKit.

## Provider Contract

Implement ``LicenseProvider`` for your licensing backend:

```swift
struct MyLicenseProvider: LicenseProvider {
  func activate(licenseKey: String, deviceName: String) async throws -> LicenseActivation {
    let response = try await api.activate(licenseKey: licenseKey, deviceName: deviceName)
    return LicenseActivation(
      licenseKey: licenseKey,
      planID: response.planID,
      customerID: response.customerID,
      deviceName: deviceName,
      activationID: response.activationID
    )
  }

  func deactivate(_ activation: LicenseActivation) async throws {
    // Call your deactivation API.
  }

  func validate(
    _ activation: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    let response = try await api.validate(
      licenseKey: activation.licenseKey,
      validationIdentifier: validationIdentifier
    )
    return LicenseValidationResult(
      isValid: response.isValid,
      planID: response.planID,
      expiresAt: response.expiresAt,
      customerID: response.customerID
    )
  }
}
```

Return ``LicenseValidationResult/isValid`` as `false` only when the backend
definitively considers the activation invalid. Throw ``LicenseProviderError``
when validation could not be completed, so ``LicenseManager`` can apply the
configured grace period.
Set ``LicenseValidationResult/planID`` only when validation should update the
active plan.
Use ``LicenseProviderError/invalidProviderURL`` for provider configuration
errors, ``LicenseProviderError/networkFailure(message:)`` for transport
failures, ``LicenseProviderError/serverFailure(statusCode:)`` for backend
server responses, and ``LicenseProviderError/requestFailure(message:)`` for
other provider request failures.

Use ``LicenseActivation/source`` only when the app needs to distinguish which
provider supplied the active activation. LicenseKit tracks one active activation
at a time.

Read ``LicenseState/source`` or ``LicenseManager/source`` when the app only
needs the current activation source.

## Persistence

License keys are sensitive application data. Use
``KeychainLicenseActivationStorage`` or another secure
``LicenseActivationStorage`` implementation in production apps. Avoid logging
raw license keys, customer identifiers, activation identifiers, or provider
request bodies.

The built-in storage types are defaults, not a required persistence layer.
Implement ``LicenseActivationStorage`` or ``LicenseStateSnapshotStorage``
directly for app group storage, encrypted files, database-backed storage, or
another host-specific strategy.
State snapshot storage is optional; omit it when restoring the persisted
activation and refreshing with your provider is sufficient.

## Topics

### Management

- ``LicenseManager``
- ``LicenseConfiguration``
- ``LicenseState``
- ``LicenseStatus``
- ``LicenseRefreshPolicy``
- ``LicenseRefreshResult``
- ``LicenseRefreshOutcome``
- ``LicenseRefreshFailure``
- ``LicenseRefreshFailureReason``

### Provider Contracts

- ``LicenseProvider``
- ``LicenseOfferingProvider``
- ``LicenseCustomerPortalProvider``
- ``LicenseDeviceIdentifierProvider``
- ``UnavailableLicenseProvider``

### Values

- ``LicenseActivation``
- ``LicenseSource``
- ``LicensePlan``
- ``LicenseOffering``
- ``LicenseOfferingKind``
- ``LicenseBillingInterval``
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
- ``LicenseErrorCode``
- ``LicenseProviderError``
- ``LicenseConfigurationError``
- ``LicenseRefreshPolicyError``
