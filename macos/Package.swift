// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "AppleIapMacOS",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(
      name: "AppleIapMacOS",
      type: .static,
      targets: ["AppleIapMacOS"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/Brendonovich/swift-rs", from: "1.0.7"),
  ],
  targets: [
    .target(
      name: "AppleIapMacOS",
      dependencies: [
        .product(name: "SwiftRs", package: "swift-rs"),
      ]
    ),
  ]
)
