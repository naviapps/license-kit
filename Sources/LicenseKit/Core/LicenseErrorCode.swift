import Foundation

public enum LicenseErrorCode: String, Codable, Equatable, Sendable {
  case invalidLicenseKey = "invalid_license_key"
  case storageFailure = "storage_failure"
  case invalidLicense = "invalid_license"
  case activationLimitReached = "activation_limit_reached"
  case invalidProviderURL = "invalid_provider_url"
  case activationInProgress = "activation_in_progress"
  case refreshInProgress = "refresh_in_progress"
  case providerServerFailure = "provider_server_failure"
  case unexpectedProviderResponse = "unexpected_provider_response"
  case providerRequestFailure = "provider_request_failure"
}
