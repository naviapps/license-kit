struct LicenseProviderGateway: Sendable {
  private let provider: any LicenseProvider

  init(provider: any LicenseProvider) {
    self.provider = provider
  }

  func activate(
    with request: LicenseActivationRequest
  ) async throws -> LicenseActivation {
    do {
      return try await provider.activate(request)
    } catch let error as LicenseProviderError {
      throw Self.mapProviderError(error)
    } catch let error as LicenseError {
      throw error
    } catch let error as CancellationError {
      throw error
    } catch {
      throw LicenseError.requestFailure(normalizing: nil)
    }
  }

  func deactivate(_ activation: LicenseActivation) async throws {
    do {
      try await provider.deactivate(activation)
    } catch let error as LicenseProviderError {
      throw Self.mapProviderError(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw Self.mapProviderError(.transportFailure(message: ""))
    }
  }

  func validate(
    _ activation: LicenseActivation,
    validationIdentifier: String?
  ) async throws -> LicenseValidationResult {
    do {
      return try await provider.validate(
        activation,
        validationIdentifier: validationIdentifier
      )
    } catch let error as LicenseProviderError {
      throw error
    } catch let error as CancellationError {
      throw error
    } catch {
      throw LicenseProviderError.transportFailure(message: "")
    }
  }

  private static func mapProviderError(_ error: LicenseProviderError) -> LicenseError {
    switch error {
    case .invalidLicense:
      .invalidLicense
    case .activationLimitReached:
      .activationLimitReached
    case .requestFailure, .transportFailure:
      .requestFailure(normalizing: error.normalizedMessage)
    case .serverFailure(let code):
      .serverFailure(statusCode: code)
    case .invalidConfiguration:
      .invalidProviderConfiguration
    case .responseDecodingFailure:
      .unexpectedProviderResponse
    }
  }
}
