public enum LicenseProviderError: Error, Equatable, Sendable {
  case invalidProviderURL
  case networkFailure(message: String)
  case responseDecodingFailure
  case invalidLicense
  case activationLimitReached
  case requestFailure(message: String)
  case serverFailure(statusCode: Int)
}
