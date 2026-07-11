# Changelog

All notable user-facing changes to LicenseKit will be documented in this file.

Released versions follow semantic versioning.

## [Unreleased]

No changes yet.

## [2.0.0] - 2026-07-12

### Added

- Added `Hashable` conformance to `LicenseActivation`, `LicensePlan`, `LicenseValidationResult`,
  `LicenseRefreshFailure`, `LicenseRefreshPolicy`, `LicenseRefreshResult`, and `LicenseState`.
- Added `CaseIterable` conformance to `LicenseRefreshOutcome` and
  `LicenseRefreshFailureReason`.

### Changed

- Raised the package manifest to Swift tools version 6.0 and macOS 14.
- Replaced local `just` development commands with `make` checks used by CI.
- Renamed `LicenseSource.default` to `LicenseSource.unspecified`.
- Added `LicenseRefreshFailureReason.gracePeriodExpired` and invalidated expired grace periods
  locally before provider refresh policy checks.
- Treated zero-length provider failure grace periods as immediate invalidation.
- Made `LicenseActivation.activatedAt` explicit for public construction and persisted decoding.
- Renamed `LicenseActivation.planID`, `LicenseActivation.activationID`, and
  `LicenseValidationResult.planID` to `planIdentifier`, `activationIdentifier`, and
  `planIdentifier`.
- Made `LicensePlan` and `LicenseActivation` initializers return `nil` for invalid public input
  instead of trapping.
- Replaced public state metadata storage with opaque `LicenseStateMetadataStorage` payloads.
- Stored rejected-activation metadata after definitive cleanup delete failures so a leftover
  activation cannot become licensed again on the next restore.
- Treated state metadata save and delete failures as best-effort instead of failing activation,
  refresh, or deactivation operations.
- Added README links to release notes.
- Clarified that security updates target the latest released version.
- Renamed the activation storage setup sample error to avoid the removed `LicenseStorage` name.
- Updated installation guidance to use the 2.0.0 release line instead of the `main` branch.

### Removed

- Removed the redundant `LicenseRefreshResult.validationFailure` case name; use
  `LicenseRefreshResult.failure`.
- Removed `LicenseStateSnapshot`, `LicenseStateSnapshotStorage`, and
  `UserDefaultsLicenseStateSnapshotStorage`. The restore schema is now internal, and public
  persistence extensions use opaque `LicenseStateMetadataStorage` payloads.
- Removed `UnavailableLicenseProvider`; tests and host apps should use focused provider doubles
  instead of carrying a non-functional production provider type.

## [1.2.0] - 2026-05-17

### Added

- Added `LicenseActivationRequest` so providers can support both license-key activation and
  keyless local or runtime entitlement activation.
- Documented official provider packages for Lemon Squeezy and Setapp.

### Changed

- Replaced `activate(licenseKey:)` with `activate(_:)` on `LicenseManager` and
  `LicenseProvider`.
- Clarified README and DocC guidance for provider-neutral entitlement sources.

## [1.1.0] - 2026-05-16

### Changed

- Simplified the core package around license state, activation, validation, refresh, and
  persistence.
- Clarified that provider-specific purchase flows, account management, catalog loading, UI, logging,
  and analytics belong in provider packages or application code.

## [1.0.0] - 2026-05-14

### Changed

- Declared the first public API release.

## [0.1.0] - 2026-05-14

### Added

- Initial public release of LicenseKit.
- Provider-neutral license activation, validation, deactivation, and refresh management through
  `LicenseManager`.
- Core license value types for activations, plans, sources, validation results, refresh results,
  refresh failures, and errors.
- Provider protocol for license activation, validation, and deactivation backends.
- Throwing persistence protocols for activation storage and state metadata storage.
- Built-in Keychain activation storage and UserDefaults state metadata storage.
- Configurable refresh intervals, provider failure grace periods, server failure grace periods, and
  disabled refresh mode.
- Normalized provider source, plan, activation, and storage identifiers.
- Observable storage, validation, and provider failures through typed errors and refresh result
  metadata.
- Public package documentation, security policy, SwiftPM CI, and local development commands.
