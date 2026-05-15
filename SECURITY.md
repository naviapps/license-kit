# Security Policy

## Supported Versions

Security updates are provided for the latest released version of LicenseKit.

## Reporting a Vulnerability

Please report security issues through GitHub's private vulnerability reporting for this repository.

Do not open a public GitHub issue or pull request for vulnerabilities, suspected
credential exposure, license-key exposure, or privacy-sensitive behavior.

If private vulnerability reporting is not enabled, open a public issue asking
for a private security contact channel, but do not include vulnerability
details, exploit steps, logs, secrets, tokens, license keys, private account
data, activation identifiers, or personal data.

When reporting an issue, include:

- Affected package version or commit
- A clear description of the behavior
- Reproduction steps or a minimal proof of concept
- Expected impact and affected license-management APIs, if known

We will acknowledge valid reports as soon as practical and coordinate fixes
before public disclosure.

## Scope

Security-sensitive areas include:

- Activation persistence and persisted state
- License validation and refresh grace handling
- Provider-facing APIs that pass license keys or activation identifiers

LicenseKit does not send license data over the network or collect analytics by
itself. Host applications choose the storage implementation and are responsible
for their own provider requests, logging, telemetry, and privacy policies.
