import XCTest

@testable import LicenseKit

final class LicenseStateMetadataInternalTests: XCTestCase {
  func testActivationIdentityMatchesEquivalentActivationOnly() throws {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = try XCTUnwrap(
      LicenseStateMetadata.ActivationIdentity(
        source: makeSource("external"),
        planIdentifier: " pro ",
        activatedAt: activatedAt
      ))
    let matchingActivation = try XCTUnwrap(
      LicenseActivation(
        source: makeSource("external"),
        planIdentifier: "pro",
        activatedAt: activatedAt,
        licenseKey: "KEY",
        activationIdentifier: "activation",
        expiresAt: activatedAt.addingTimeInterval(60)
      ))

    XCTAssertTrue(identity.matches(activation: matchingActivation))
    XCTAssertTrue(
      identity.matches(
        activation: try XCTUnwrap(
          LicenseActivation(
            source: makeSource("external"),
            planIdentifier: "pro",
            activatedAt: activatedAt,
            activationIdentifier: "different-provider-id"
          ))
      )
    )
    XCTAssertFalse(
      identity.matches(
        activation: try XCTUnwrap(
          LicenseActivation(
            source: makeSource("other"),
            planIdentifier: "pro",
            activatedAt: activatedAt,
            activationIdentifier: "activation"
          ))
      )
    )
  }

  func testActivationIdentityNormalizesValues() throws {
    let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = try XCTUnwrap(
      LicenseStateMetadata.ActivationIdentity(
        source: makeSource("external"),
        planIdentifier: " pro ",
        activatedAt: activatedAt
      ))

    XCTAssertEqual(identity.source, makeSource("external"))
    XCTAssertEqual(identity.planIdentifier, "pro")
    XCTAssertEqual(identity.activatedAt, activatedAt)
    XCTAssertNil(
      LicenseStateMetadata.ActivationIdentity(
        source: makeSource("external"),
        planIdentifier: " \n\t ",
        activatedAt: activatedAt
      )
    )
    XCTAssertNil(
      LicenseStateMetadata.ActivationIdentity(
        source: makeSource("external"),
        planIdentifier: " unlicensed ",
        activatedAt: activatedAt
      )
    )
  }

  func testActivationIdentityDecodeNormalizesAndRejectsInvalidPlanIdentifier() throws {
    let data = """
      {
        "source": "external",
        "planIdentifier": " pro ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!
    let nonCanonicalSource = """
      {
        "source": " external ",
        "planIdentifier": "pro",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!
    let blankPlanIdentifier = """
      {
        "source": "external",
        "planIdentifier": " ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!
    let reservedPlanIdentifier = """
      {
        "source": "external",
        "planIdentifier": " unlicensed ",
        "activatedAt": 1700000000
      }
      """.data(using: .utf8)!

    let identity = try JSONDecoder().decode(
      LicenseStateMetadata.ActivationIdentity.self,
      from: data
    )

    XCTAssertEqual(identity.source, makeSource("external"))
    XCTAssertEqual(identity.planIdentifier, "pro")
    XCTAssertEqual(identity.activatedAt, Date(timeIntervalSinceReferenceDate: 1_700_000_000))
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        LicenseStateMetadata.ActivationIdentity.self,
        from: nonCanonicalSource
      )
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        LicenseStateMetadata.ActivationIdentity.self,
        from: blankPlanIdentifier
      )
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        LicenseStateMetadata.ActivationIdentity.self,
        from: reservedPlanIdentifier
      )
    )
  }

  func testActivationIdentityDoesNotPersistProviderActivationIdentifier() throws {
    let identity = try XCTUnwrap(
      LicenseStateMetadata.ActivationIdentity(
        source: makeSource("external"),
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSinceReferenceDate: 1_700_000_000)
      )
    )

    let data = try JSONEncoder().encode(identity)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertFalse(json.contains("activationIdentifier"))
  }

  func testStateMetadataRejectsImpossibleRestorableState() throws {
    let identity = try XCTUnwrap(
      LicenseStateMetadata.ActivationIdentity(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ))
    let failure = LicenseRefreshFailure(
      reason: .requestFailure,
      message: "unavailable",
      occurredAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    XCTAssertNil(
      LicenseStateMetadata(
        activationIdentity: identity,
        plan: .unlicensed,
        lastValidatedAt: nil,
        status: .invalid,
        gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_200),
        lastRefreshFailure: failure
      ))
    XCTAssertNil(
      LicenseStateMetadata(
        activationIdentity: identity,
        plan: .unlicensed,
        lastValidatedAt: nil,
        status: .unlicensed,
        gracePeriodExpiresAt: nil
      ))
    XCTAssertNil(
      LicenseStateMetadata(
        activationIdentity: identity,
        plan: makePlan(identifier: "team", isLicensed: true, expiresAt: nil),
        lastValidatedAt: nil,
        status: .gracePeriod,
        gracePeriodExpiresAt: nil,
        lastRefreshFailure: failure
      ))
    XCTAssertNil(
      LicenseStateMetadata(
        activationIdentity: identity,
        plan: makePlan(identifier: "team", isLicensed: true, expiresAt: nil),
        lastValidatedAt: nil,
        status: .active,
        gracePeriodExpiresAt: nil
      ))
    let activeMetadata = LicenseStateMetadata(
      activationIdentity: identity,
      plan: .unlicensed,
      lastValidatedAt: nil,
      status: .active,
      gracePeriodExpiresAt: Date(timeIntervalSince1970: 1_700_000_200),
      lastRefreshFailure: failure
    )

    XCTAssertEqual(activeMetadata?.status, .active)
    XCTAssertEqual(
      activeMetadata?.plan,
      makePlan(identifier: "pro", isLicensed: true, expiresAt: nil)
    )
    XCTAssertNil(activeMetadata?.gracePeriodExpiresAt)
    XCTAssertNil(activeMetadata?.lastRefreshFailure)
  }

  func testStateMetadataRestoresRejectedActivationTombstoneWithoutLicensingIt() throws {
    let activation = makeActivation(planIdentifier: "pro")
    let failure = LicenseRefreshFailure(
      reason: .invalidLicense,
      occurredAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    let metadata = try XCTUnwrap(
      LicenseStateMetadata(
        activationIdentity: .init(activation: activation),
        plan: makePlan(identifier: "team", isLicensed: true, expiresAt: nil),
        lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        status: .invalid,
        gracePeriodExpiresAt: nil,
        lastRefreshFailure: failure
      ))

    let restoredState = metadata.restoreState(activation: activation)

    XCTAssertEqual(metadata.plan, .unlicensed)
    XCTAssertEqual(metadata.status, .invalid)
    XCTAssertEqual(metadata.lastRefreshFailure, failure)
    XCTAssertEqual(restoredState.status, .invalid)
    XCTAssertNil(restoredState.activation)
    XCTAssertEqual(restoredState.plan, .unlicensed)
    XCTAssertEqual(restoredState.lastRefreshFailure, failure)
  }

  func testStateMetadataDecodeRejectsImpossibleRestorableState() {
    let data = """
      {
        "activationIdentity": {
          "source": "unspecified",
          "planIdentifier": "pro",
          "activatedAt": 1700000000
        },
        "plan": {
          "id": "unlicensed",
          "isLicensed": false
        },
        "status": "invalid",
        "gracePeriodExpiresAt": 1700000200,
        "lastRefreshFailure": {
          "reason": "requestFailure",
          "message": "unavailable",
          "occurredAt": 1700000100
        }
      }
      """.data(using: .utf8)!

    XCTAssertThrowsError(try JSONDecoder().decode(LicenseStateMetadata.self, from: data))
  }

  func testStateMetadataDecodeAcceptsRejectedActivationTombstone() throws {
    let data = """
      {
        "activationIdentity": {
          "source": "unspecified",
          "planIdentifier": "pro",
          "activatedAt": 1700000000
        },
        "plan": {
          "id": "pro",
          "isLicensed": true
        },
        "lastValidatedAt": 1700000100,
        "status": "invalid",
        "lastRefreshFailure": {
          "reason": "invalidLicense",
          "occurredAt": 1700000100
        }
      }
      """.data(using: .utf8)!

    let metadata = try JSONDecoder().decode(LicenseStateMetadata.self, from: data)

    XCTAssertEqual(metadata.plan, .unlicensed)
    XCTAssertEqual(metadata.status, .invalid)
    XCTAssertEqual(metadata.lastRefreshFailure?.reason, .invalidLicense)
    XCTAssertEqual(
      metadata.restoreState(activation: makeActivation(planIdentifier: "pro")).status,
      .invalid
    )
  }

  func testStateMetadataRestoreNormalizesExpiredPlan() throws {
    let identity = try XCTUnwrap(
      LicenseStateMetadata.ActivationIdentity(
        source: .unspecified,
        planIdentifier: "pro",
        activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ))
    let expiredPlanMetadata = LicenseStateMetadata(
      activationIdentity: identity,
      plan: makePlan(
        identifier: "pro",
        isLicensed: true,
        expiresAt: Date(timeIntervalSince1970: 1)
      ),
      lastValidatedAt: nil,
      status: .active,
      gracePeriodExpiresAt: nil
    )

    XCTAssertEqual(expiredPlanMetadata?.status, .active)
    XCTAssertEqual(expiredPlanMetadata?.plan.expiresAt, Date(timeIntervalSince1970: 1))
    XCTAssertEqual(
      expiredPlanMetadata?.restoreState(activation: makeActivation(planIdentifier: "pro")).status,
      .expired
    )
  }

  func testStateMetadataDecodePreservesExpiredPlanForRestoreNormalization() throws {
    let data = """
      {
        "activationIdentity": {
          "source": "unspecified",
          "planIdentifier": "pro",
          "activatedAt": 1700000000
        },
        "plan": {
          "id": "pro",
          "isLicensed": true,
          "expiresAt": 1
        },
        "status": "active"
      }
      """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(LicenseStateMetadata.self, from: data)

    XCTAssertEqual(snapshot.plan.expiresAt, Date(timeIntervalSinceReferenceDate: 1))
    XCTAssertEqual(
      snapshot.restoreState(activation: makeActivation(planIdentifier: "pro")).status,
      .expired
    )
  }
}
