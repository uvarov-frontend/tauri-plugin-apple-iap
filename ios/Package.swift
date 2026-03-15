// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "tauri-plugin-apple-iap",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "tauri-plugin-apple-iap",
      type: .static,
      targets: ["tauri-plugin-apple-iap"]
    )
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(
      name: "tauri-plugin-apple-iap",
      dependencies: [
        .byName(name: "Tauri")
      ],
      path: "Sources"
    )
  ]
)
