// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "gui-for-cli",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "GUIForCLICore", targets: ["GUIForCLICore"]),
    .executable(name: "gui-for-cli", targets: ["GUIForCLICLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0")
  ],
  targets: [
    .target(
      name: "GUIForCLICore",
      path: "shared/Sources/GUIForCLICore",
      resources: [.copy("Resources")]
    ),
    .executableTarget(
      name: "GUIForCLICLI",
      dependencies: [
        "GUIForCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "shared/Sources/GUIForCLICLI"
    ),
    .testTarget(
      name: "GUIForCLICoreTests",
      dependencies: ["GUIForCLICore"],
      path: "shared/Tests/GUIForCLICoreTests"
    ),
    .testTarget(
      name: "GUIForCLICLITests",
      dependencies: ["GUIForCLICLI"],
      path: "shared/Tests/GUIForCLICLITests"
    ),
  ]
)
