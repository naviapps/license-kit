// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "LicenseKit",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
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
