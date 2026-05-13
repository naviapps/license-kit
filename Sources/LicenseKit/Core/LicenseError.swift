import Foundation

public enum LicenseError: Error, Equatable, Sendable {
  case invalidLicenseKey
  case storageFailure
  case invalidLicense
  case activationLimitReached
  case invalidProviderURL
  case activationInProgress
  case refreshInProgress
  case providerServerFailure(statusCode: Int)
  case unexpectedProviderResponse
  case providerRequestFailure(message: String)

  public var code: LicenseErrorCode {
    switch self {
    case .invalidLicenseKey: .invalidLicenseKey
    case .storageFailure: .storageFailure
    case .invalidLicense: .invalidLicense
    case .activationLimitReached: .activationLimitReached
    case .invalidProviderURL: .invalidProviderURL
    case .activationInProgress: .activationInProgress
    case .refreshInProgress: .refreshInProgress
    case .providerServerFailure: .providerServerFailure
    case .unexpectedProviderResponse: .unexpectedProviderResponse
    case .providerRequestFailure: .providerRequestFailure
    }
  }

  public var message: String? {
    if case .providerRequestFailure(let message) = self { return message }
    return nil
  }

  public var statusCode: Int? {
    if case .providerServerFailure(let statusCode) = self { return statusCode }
    return nil
  }
}

extension LicenseError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .providerServerFailure(let statusCode):
      "provider_server_failure(\(statusCode))"
    case .providerRequestFailure(let message):
      "provider_request_failure(\(message))"
    default:
      code.rawValue
    }
  }
}

extension LicenseError: LocalizedError {
  public var errorDescription: String? {
    description
  }
}
