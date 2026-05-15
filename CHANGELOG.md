# Changelog

All notable changes to LicenseKit will be documented in this file.

This project follows semantic versioning.

## Unreleased

### Changed

- Simplified the core package around license state, activation, validation,
  refresh, and persistence.
- Clarified that commerce, offering, customer portal, configuration, and billing
  account identity belong in provider packages or application code.

## [1.0.0] - 2026-05-14

### Changed

- Declared the first stable public API release.
- Replaced `LicenseBillingInterval` with `LicenseBillingPeriod` and
  `LicenseBillingPeriodUnit` so offerings can represent multi-unit billing
  periods such as every 3 months.

## [0.1.0] - 2026-05-14

### Added

- Initial public release of LicenseKit.
- Provider-neutral license activation, validation, deactivation, and refresh
  management through `LicenseManager`.
- Core license value types for activations, plans, offerings, sources,
  validation results, refresh results, refresh failures, and errors.
- Provider protocols for license backends, dynamic offerings, customer portal
  URLs, and device identifiers.
- Throwing persistence protocols for activation storage and state snapshot
  storage.
- Built-in Keychain activation storage and UserDefaults state snapshot storage.
- Configurable refresh intervals, network grace periods, provider error grace
  periods, and disabled refresh mode.
- Normalized provider source, plan, offering, activation, and storage
  identifiers.
- Observable storage, validation, dynamic offering, and provider failures
  through typed errors and refresh result metadata.
- Public package documentation, security policy, SwiftPM CI, Swift Package
  Index DocC configuration, contributor templates, and local development
  commands.
