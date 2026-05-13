// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "GUIForCLIShared",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "GUIForCLICore", targets: ["GUIForCLICore"])
  ],
  targets: [
    .target(
      name: "GUIForCLICore",
      path: "Sources/GUIForCLICore",
      resources: [.copy("Resources")]
    )
  ]
)
