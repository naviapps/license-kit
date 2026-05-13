public enum LicenseRefreshFailureReason: String, Codable, Equatable, Sendable {
  case invalidLicense
  case activationLimitReached
  case invalidProviderURL
  case unexpectedProviderResponse
  case networkFailure
  case offeringLoadFailure
  case providerServerFailure
  case providerRequestFailure
}
