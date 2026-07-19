// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Topher",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(name: "TopherCore", targets: ["TopherCore"]),
    .executable(name: "Topher", targets: ["TopherApp"]),
    .executable(name: "TopherChromeBridgeHost", targets: ["TopherChromeBridgeHost"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/sindresorhus/KeyboardShortcuts",
      from: "3.0.1"
    )
  ],
  targets: [
    .target(name: "TopherCore"),
    .executableTarget(
      name: "TopherApp",
      dependencies: [
        "TopherCore",
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
      ],
      exclude: ["Topher.entitlements"]
    ),
    .executableTarget(
      name: "TopherChromeBridgeHost",
      dependencies: ["TopherCore"]
    ),
    .testTarget(
      name: "TopherCoreTests",
      dependencies: ["TopherCore"]
    ),
    .testTarget(
      name: "TopherAppTests",
      dependencies: ["TopherApp", "TopherCore"]
    ),
  ]
)
