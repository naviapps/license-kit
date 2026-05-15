# Contributing

Thank you for your interest in improving LicenseKit.

## Scope

LicenseKit focuses on Apple platform app license state, activation persistence,
refresh policy, provider contracts, and storage boundaries.

Please keep changes focused. Avoid bundling unrelated refactors,
formatting-only rewrites, and behavior changes in the same pull request.

Provider-specific network clients and SDKs should live outside this core package
unless the package scope is intentionally expanded.

## Development

Run the test suite before opening a pull request:

```sh
swift test
```

Check formatting before opening a pull request:

```sh
swift format lint --recursive --strict Sources Tests Package.swift
```

If you have `just` installed, you can run formatting lint and tests with:

```sh
just check
```

To inspect local code coverage, run:

```sh
just coverage
```

## Pull Requests

Before submitting a pull request:

- Keep the public API surface minimal and documented.
- Add or update tests for behavior changes.
- Update `README.md` or `CHANGELOG.md` when user-facing behavior changes.
- Do not commit generated build output such as `.build/` or `.swiftpm/`.
- Do not include secrets, tokens, license keys, private keys, account
  identifiers, activation identifiers, local paths, or app-specific internal
  references.

## Security

Do not report vulnerabilities in public issues or pull requests. Follow
[SECURITY.md](SECURITY.md) instead.
