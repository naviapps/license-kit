// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "LicenseKit",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "LicenseKit",
      targets: ["LicenseKit"]
    )
  ],
  targets: [
    .target(
      name: "LicenseKit",
      path: "Sources/LicenseKit"
    ),
    .testTarget(
      name: "LicenseKitTests",
      dependencies: ["LicenseKit"],
      path: "Tests/LicenseKitTests"
    ),
  ],
  swiftLanguageVersions: [.v5]
)
