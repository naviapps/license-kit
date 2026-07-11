# Security Policy

## Supported Versions

Security updates are provided for the latest released version.

## Reporting a Vulnerability

Report security issues through GitHub private vulnerability reporting for this repository.

Do not open a public issue, pull request, or discussion for vulnerabilities, suspected credential
exposure, privacy-sensitive behavior, or issues that could expose private user data.

If private vulnerability reporting is unavailable, open a public issue asking for a private
security contact channel. Do not include vulnerability details, exploit steps, logs, secrets,
tokens, license keys, activation identifiers, provider request bodies, private keys, personal data,
local paths, private app metadata, or app-specific internal references.

For private reports, include:

- Affected package version or commit
- Affected dependency versions if relevant
- A clear description of the behavior
- Reproduction steps or a minimal proof of concept
- Expected impact
- Affected public API, target, or subsystem

Use placeholders instead of secrets, tokens, license keys, activation identifiers, provider request
bodies, private keys, personal data, local paths, private app metadata, or app-specific internal
references.

We will acknowledge valid reports as soon as practical and coordinate fixes before public
disclosure.

## Scope

Security-sensitive areas include:

- Activation persistence and persisted license state
- License validation, refresh, restore, and grace handling
- Provider-facing APIs that pass license keys or activation identifiers
- Storage implementations and error surfaces that could expose private license data

LicenseKit does not send license data over the network or collect analytics by itself. Host
applications choose the storage implementation and are responsible for provider requests, logging,
telemetry, and privacy policies.
