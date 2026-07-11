import Foundation
import XCTest

final class LicenseKitSourceBoundaryTests: XCTestCase {
  func testInternalImplementationTypesStayOutOfPublicSurface() throws {
    let internalSourceFiles = [
      "Sources/LicenseKit/Core/LicenseStringNormalization.swift",
      "Sources/LicenseKit/Management/LicenseManager+Persistence.swift",
      "Sources/LicenseKit/Management/LicenseStateStore.swift",
      "Sources/LicenseKit/Management/LicenseValidationSnapshot.swift",
      "Sources/LicenseKit/Persistence/LicenseStateMetadata.swift",
      "Sources/LicenseKit/Persistence/LicenseStateRestoration.swift",
      "Sources/LicenseKit/Providers/LicenseProviderGateway.swift",
    ]

    for relativePath in internalSourceFiles {
      let source = try readRepositoryFile(relativePath)

      XCTAssertFalse(
        containsPublicDeclaration(in: source),
        "\(relativePath) is an implementation detail and should not expose public API."
      )
      XCTAssertFalse(
        source.contains("@usableFromInline"),
        "\(relativePath) should not create a semi-public inlinable contract."
      )
      XCTAssertFalse(
        source.contains("@_spi"),
        "\(relativePath) should not expose SPI as a compatibility seam."
      )
    }
  }

  func testPersistenceSurfaceStaysSplitBetweenActivationAndMetadataStorage() throws {
    let activationStorageSource = try readRepositoryFile(
      "Sources/LicenseKit/Persistence/LicenseActivationStorage.swift"
    )
    let metadataStorageSource = try readRepositoryFile(
      "Sources/LicenseKit/Persistence/LicenseStateMetadataStorage.swift"
    )

    XCTAssertTrue(
      containsPublicProtocolDeclaration(
        named: "LicenseActivationStorage",
        in: activationStorageSource
      ),
      "LicenseActivationStorage is the authoritative activation persistence contract."
    )
    XCTAssertTrue(
      containsPublicProtocolDeclaration(
        named: "LicenseStateMetadataStorage",
        in: metadataStorageSource
      ),
      "LicenseStateMetadataStorage is the optional non-authoritative metadata contract."
    )
    XCTAssertFalse(
      containsPublicProtocolDeclaration(named: "LicenseStorage", in: activationStorageSource)
        || containsPublicProtocolDeclaration(named: "LicenseStorage", in: metadataStorageSource),
      "Do not merge activation and metadata persistence back into a vague storage protocol."
    )
  }

  private func containsPublicDeclaration(in source: String) -> Bool {
    source.split(separator: "\n").contains { line in
      line.range(
        of:
          #"^\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*(?:public|open)\s+(?:actor|class|enum|extension|func|import|init|let|protocol|struct|subscript|typealias|var)\b"#,
        options: .regularExpression
      ) != nil
    }
  }

  private func containsPublicProtocolDeclaration(named name: String, in source: String) -> Bool {
    let pattern =
      #"^\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*public\s+protocol\s+"#
      + NSRegularExpression.escapedPattern(for: name)
      + #"\b"#
    return source.split(separator: "\n").contains { line in
      line.range(of: pattern, options: .regularExpression) != nil
    }
  }

  private func readRepositoryFile(_ relativePath: String) throws -> String {
    try String(
      contentsOf: Self.repositoryRoot().appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  private static func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
