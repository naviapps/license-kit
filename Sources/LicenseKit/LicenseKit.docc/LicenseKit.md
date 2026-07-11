# ``LicenseKit``

Manage Apple platform app license state through provider-backed activation,
validation, refresh, and persistence flows.

## Overview

LicenseKit is a provider-neutral state layer for Apple platform app licensing.
Host apps implement ``LicenseProvider``, choose persistence, and use
``LicenseManager`` as the app-facing state boundary. Provider validation remains
the source of truth; persisted state is only a local restore aid.

## Responsibility Boundary

LicenseKit owns provider-neutral license state, refresh policy, activation
storage contracts, validation result modeling, and persistence helpers.

LicenseKit does not provide purchase flows, catalog loading, account-management
flows, provider SDKs, UI, provider-specific display logic, or analytics.

## Creating a Manager

Implement ``LicenseProvider`` for your backend or entitlement source, create one
``LicenseManager`` with secure activation storage, then call
``LicenseManager/activate(_:)``, ``LicenseManager/refresh()``, and
``LicenseManager/deactivate()`` from the app layer.

Create a manager with an explicit ``LicenseProvider`` implementation and
secure activation storage. The `provider` and `activationStorage` values
represent your app's backend or entitlement adapter and secure persistence
layer. ``LicenseManager`` is `@MainActor` and exposes plain ``LicenseState``
values, so wrap it in your app's UI observation model instead of making
LicenseKit own UI publication:

```swift
import LicenseKit

let manager = LicenseManager(
  provider: provider,
  activationStorage: activationStorage,
  refreshPolicy: .default
)
```

Mutating operations return the updated ``LicenseState``. ``LicenseState``
normalizes impossible combinations such as licensed statuses without an
activation, expired local values, or grace-period state without an expiration.
Use ``LicenseManager/needsRefresh(now:)`` and ``LicenseManager/refresh()`` from
the app lifecycle, then branch on ``LicenseRefreshResult/outcome`` and
``LicenseRefreshResult/failure``.

## Configuration

Start with ``LicenseRefreshPolicy/default`` and secure
``LicenseActivationStorage``. Add ``LicenseStateMetadataStorage`` only when the
app needs non-authoritative local restore metadata such as the last validation
decision, grace period, last refresh failure, or terminal activation metadata.
Use ``LicenseRefreshPolicy/never`` for entitlement sources that should not run
provider validation through LicenseKit.

## State Lifecycle

``LicenseManager`` keeps one active activation at a time. Successful refreshes
keep it active; temporary provider failures move it into a grace period;
definitive invalid or expired results clear the activation. Deactivation clears
persisted activation state.
Use ``LicenseManager/applyActivation(_:)`` only when a provider package or
runtime entitlement adapter already resolved a ``LicenseActivation`` outside the
normal ``LicenseProvider/activate(_:)`` request path.
Use ``LicenseRefreshResult/outcome`` and ``LicenseRefreshResult/failure`` to
decide whether the app should keep running, show a grace-period notice, or
request a new license.

## Provider Contract

``LicenseProvider`` maps a backend or entitlement source into
``LicenseActivation`` and ``LicenseValidationResult``. Return invalid validation
results only for definitive license rejection; throw ``LicenseProviderError``
when validation could not be completed so ``LicenseManager`` can apply grace
handling. Use ``LicenseState/source`` or ``LicenseManager/source`` only when the
app needs to distinguish which provider supplied the single active activation.

## Persistence

License keys are sensitive application data. Use
``KeychainLicenseActivationStorage`` or another secure
``LicenseActivationStorage`` implementation for production apps, and avoid
logging raw license keys, activation identifiers, provider request bodies, or
whole state values unless activation fields are redacted.

``LicenseStateMetadataStorage`` stores an opaque payload owned by LicenseKit.
It can restore local grace state or remember rejected activations after cleanup
failures, but it never grants entitlement by itself.

## Topics

### Management

- ``LicenseManager``
- ``LicenseManager/source``
- ``LicenseState``
- ``LicenseState/source``
- ``LicenseStatus``
- ``LicenseRefreshPolicy``
- ``LicenseRefreshResult``
- ``LicenseRefreshOutcome``
- ``LicenseRefreshFailure``
- ``LicenseRefreshFailureReason``

### Provider Contracts

- ``LicenseProvider``

### Values

- ``LicenseActivation``
- ``LicenseActivation/source``
- ``LicenseActivationRequest``
- ``LicenseSource``
- ``LicenseSource/identifier``
- ``LicenseSource/unspecified``
- ``LicensePlan``
- ``LicensePlan/identifier``
- ``LicensePlan/unlicensed``
- ``LicenseValidationResult``

### Activation Persistence

- ``LicenseActivationStorage``
- ``KeychainLicenseActivationStorage``

### Advanced Persistence

- ``LicenseStateMetadataStorage``
- ``UserDefaultsLicenseStateMetadataStorage``

### Errors

- ``LicenseError``
- ``LicenseProviderError``
- ``LicenseRefreshPolicyError``
