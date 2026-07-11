// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LicenseKit",
  platforms: [
    .iOS(.v15),
    .macOS(.v14),
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
      name: "LicenseKit"
    ),
    .testTarget(
      name: "LicenseKitTests",
      dependencies: ["LicenseKit"]
    ),
  ]
)
