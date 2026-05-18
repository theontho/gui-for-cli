import Foundation
import ProjectDescription

let organizationName = "GUI for CLI"
let bundlePrefix = "dev.guiforcli"
let marketingVersion = "0.1.0"
let buildVersion = "1"
let defaultAppName = "GUI for CLI"

private let appleRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private let repoRootURL =
  appleRootURL
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .standardizedFileURL
private let repoRootPath = repoRootURL.path

private struct AppIdentity {
  var displayName: String
  var productName: String
  var macBundleId: String
  var marketingVersion: String

  static func load(defaultName: String) -> AppIdentity {
    let configURL = repoRootURL.appendingPathComponent("tmp/app-identity.json")
    guard
      let data = try? Data(contentsOf: configURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return AppIdentity(
        displayName: defaultName,
        productName: defaultName,
        macBundleId: "\(bundlePrefix).generic",
        marketingVersion: marketingVersion
      )
    }

    let embeddedBundlePath = json["embeddedBundlePath"] as? String
    let embeddedBundleName = embeddedBundlePath.flatMap { path in
      nonEmpty(URL(fileURLWithPath: path).lastPathComponent)
    }
    let manifestDisplayName = embeddedBundlePath.flatMap { path in
      bundleDisplayName(inBundleAt: path)
    }
    let resolvedDisplayName =
      nonEmpty(json["displayName"] as? String) ?? manifestDisplayName ?? defaultName
    let resolvedProductName = nonEmpty(json["productName"] as? String) ?? resolvedDisplayName
    let bundleIdentifierName =
      nonEmpty(json["productName"] as? String)
      ?? nonEmpty(json["displayName"] as? String)
      ?? embeddedBundleName
      ?? resolvedProductName
    let macBundleId =
      embeddedBundlePath == nil
      ? "\(bundlePrefix).generic"
      : "\(bundlePrefix).embed.\(bundleIdentifierComponent(bundleIdentifierName))"
    return AppIdentity(
      displayName: resolvedDisplayName,
      productName: resolvedProductName,
      macBundleId: macBundleId,
      marketingVersion: nonEmpty(json["marketingVersion"] as? String) ?? marketingVersion
    )
  }
}

private func bundleDisplayName(inBundleAt path: String) -> String? {
  let bundlePath = path.hasPrefix("/") ? path : "\(repoRootPath)/\(path)"
  let manifestURL = URL(fileURLWithPath: "\(bundlePath)/manifest.json")
  guard
    let data = try? Data(contentsOf: manifestURL),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return nil
  }
  return nonEmpty(object["displayName"] as? String)
}

private func nonEmpty(_ value: String?) -> String? {
  guard let value else { return nil }
  return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
}

private func bundleIdentifierComponent(_ value: String) -> String {
  let normalized = value.lowercased().unicodeScalars.filter { scalar in
    ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar))
  }
  let component = String(String.UnicodeScalarView(normalized))
  return component.isEmpty ? "app" : component
}

private func unquotedTOMLString(_ value: String) -> String {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.count >= 2,
    let first = trimmed.first,
    let last = trimmed.last,
    (first == "\"" && last == "\"") || (first == "'" && last == "'")
  {
    return String(trimmed.dropFirst().dropLast())
  }
  return trimmed
}

private func devConfigSigningValue(_ key: String) -> String? {
  let configURL = repoRootURL.appendingPathComponent(".devconfig.toml")
  guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
    return nil
  }

  var inSigningSection = false
  for rawLine in text.components(separatedBy: .newlines) {
    let line =
      String(rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty {
      continue
    }
    if line.hasPrefix("[") && line.hasSuffix("]") {
      inSigningSection = line == "[apple.signing]"
      continue
    }
    guard inSigningSection else {
      continue
    }
    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
      String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines) == key
    else {
      continue
    }
    return nonEmpty(unquotedTOMLString(String(parts[1])))
  }

  return nil
}

private func configuredDevelopmentTeam() -> String {
  let environment = ProcessInfo.processInfo.environment
  return nonEmpty(environment["APPLE_DEVELOPMENT_TEAM"])
    ?? nonEmpty(environment["APPLE_TEAM_ID"])
    ?? devConfigSigningValue("development_team")
    ?? devConfigSigningValue("team_id")
    ?? ""
}

private let appIdentity = AppIdentity.load(defaultName: defaultAppName)
private let appKitDisplayName = "swift appkit test"
private let appKitProductName = "swift appkit test"
private let developmentTeam = configuredDevelopmentTeam()

let baseSettings: SettingsDictionary = [
  "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
  "CURRENT_PROJECT_VERSION": .string(buildVersion),
  "DEVELOPMENT_TEAM": .string(developmentTeam),
  "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
  "MARKETING_VERSION": .string(appIdentity.marketingVersion),
  "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
  "SWIFT_STRICT_CONCURRENCY": "complete",
  "SWIFT_VERSION": "6.0",
]

let appInfoPlist: InfoPlist = .extendingDefault(with: [
  "CFBundleDisplayName": .string(appIdentity.displayName),
  "CFBundleIconName": "AppIcon",
  "CFBundleName": .string(appIdentity.displayName),
  "LSApplicationCategoryType": "public.app-category.developer-tools",
  "UILaunchScreen": [:],
])

let appKitInfoPlist: InfoPlist = .dictionary([
  "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
  "CFBundleDisplayName": .string(appKitDisplayName),
  "CFBundleExecutable": "$(EXECUTABLE_NAME)",
  "CFBundleIconName": "AppIcon",
  "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
  "CFBundleInfoDictionaryVersion": "6.0",
  "CFBundleName": .string(appKitDisplayName),
  "CFBundlePackageType": "APPL",
  "LSApplicationCategoryType": "public.app-category.developer-tools",
  "CFBundleShortVersionString": "$(MARKETING_VERSION)",
  "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
  "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
  "NSPrincipalClass": "NSApplication",
])

let objcAppInfoPlist: InfoPlist = .extendingDefault(with: [
  "CFBundleDisplayName": .string("\(appIdentity.displayName) ObjC AppKit Test"),
  "CFBundleIconName": "AppIcon",
  "CFBundleName": .string("\(appIdentity.displayName) ObjC AppKit Test"),
  "LSApplicationCategoryType": "public.app-category.developer-tools",
])

let appResources: ResourceFileElements = [
  "shared/app/Resources/**"
]

let objcAppResources: ResourceFileElements = [
  "exp/objc-appkit/**/*.strings",
  "shared/app/Resources/**",
  .folderReference(path: "../../examples/WGSExtract"),
]

let coreDependency: TargetDependency = .package(product: "GUIForCLICore")
let appleBuiltResourceSyncScript = TargetScript.post(
  script: "python3 \"$SRCROOT/../../tools/sync_apple_built_resources.py\"",
  name: "Sync built Apple resources",
  basedOnDependencyAnalysis: false
)

let project = Project(
  name: "GUIForCLI",
  organizationName: organizationName,
  options: .options(
    automaticSchemesOptions: .disabled,
    developmentRegion: "en",
    textSettings: .textSettings(usesTabs: false, indentWidth: 2, tabWidth: 2)
  ),
  packages: [
    .package(path: "shared")
  ],
  settings: .settings(base: baseSettings),
  targets: [
    .target(
      name: "GUIForCLIiOS",
      destinations: [.iPhone, .iPad],
      product: .app,
      productName: "GUIForCLI",
      bundleId: "\(bundlePrefix).gui-for-cli.ios",
      deploymentTargets: .iOS("17.0"),
      infoPlist: appInfoPlist,
      sources: [
        "exp/ios-swiftui/**/*.swift",
        "shared/app/**/*.swift",
      ],
      resources: appResources,
      scripts: [appleBuiltResourceSyncScript],
      dependencies: [coreDependency],
      settings: .settings(base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "PRODUCT_NAME": .string(appIdentity.productName),
        "TARGETED_DEVICE_FAMILY": "1,2",
      ])
    ),
    .target(
      name: "GUIForCLIMac",
      destinations: [.mac],
      product: .app,
      productName: "GUIForCLI",
      bundleId: appIdentity.macBundleId,
      deploymentTargets: .macOS("14.0"),
      infoPlist: appInfoPlist,
      sources: [
        "swiftui/**/*.swift",
        "shared/app/**/*.swift",
      ],
      resources: appResources,
      scripts: [appleBuiltResourceSyncScript],
      dependencies: [coreDependency],
      settings: .settings(
        base: [
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "CODE_SIGN_STYLE": "Automatic",
          "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
          "PRODUCT_NAME": .string(appIdentity.productName),
        ],
        configurations: [
          .release(
            name: "Release",
            settings: [
              "ENABLE_HARDENED_RUNTIME": "YES"
            ]
          )
        ]
      )
    ),
    .target(
      name: "GUIForCLIAppKit",
      destinations: [.mac],
      product: .app,
      productName: "GUIForCLIAppKit",
      bundleId: "\(bundlePrefix).gui-for-cli.appkit",
      deploymentTargets: .macOS("14.0"),
      infoPlist: appKitInfoPlist,
      sources: [
        "exp/swift-appkit/**/*.swift"
      ],
      resources: appResources,
      scripts: [appleBuiltResourceSyncScript],
      dependencies: [coreDependency],
      settings: .settings(
        base: [
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "CODE_SIGN_STYLE": "Automatic",
          "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
          "PRODUCT_NAME": .string(appKitProductName),
        ],
        configurations: [
          .release(
            name: "Release",
            settings: [
              "ENABLE_HARDENED_RUNTIME": "YES"
            ]
          )
        ]
      )
    ),
    .target(
      name: "GUIForCLIObjCAppKit",
      destinations: [.mac],
      product: .app,
      productName: "GUIForCLIObjCAppKit",
      bundleId: "\(bundlePrefix).gui-for-cli.objc-appkit-test",
      deploymentTargets: .macOS("14.0"),
      infoPlist: objcAppInfoPlist,
      sources: [
        "exp/objc-appkit/**/*.h",
        "exp/objc-appkit/**/*.m",
      ],
      resources: objcAppResources,
      scripts: [appleBuiltResourceSyncScript],
      settings: .settings(
        base: [
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "CLANG_ENABLE_OBJC_ARC": "YES",
          "CODE_SIGN_STYLE": "Automatic",
          "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
          "GCC_PREPROCESSOR_DEFINITIONS": "GFC_SOURCE_ROOT=\\\"$(SRCROOT)/../..\\\"",
          "PRODUCT_NAME": "GUI for CLI ObjC AppKit Test",
        ],
        configurations: [
          .release(
            name: "Release",
            settings: [
              "ENABLE_HARDENED_RUNTIME": "YES"
            ]
          )
        ]
      )
    ),
  ],
  schemes: [
    .scheme(
      name: "GUIForCLIiOS",
      shared: true,
      buildAction: .buildAction(targets: ["GUIForCLIiOS"]),
      runAction: .runAction(executable: .executable("GUIForCLIiOS")),
      archiveAction: .archiveAction(configuration: .release)
    ),
    .scheme(
      name: "GUIForCLIMac",
      shared: true,
      buildAction: .buildAction(targets: ["GUIForCLIMac"]),
      runAction: .runAction(executable: .executable("GUIForCLIMac")),
      archiveAction: .archiveAction(configuration: .release)
    ),
    .scheme(
      name: "GUIForCLIAppKit",
      shared: true,
      buildAction: .buildAction(targets: ["GUIForCLIAppKit"]),
      runAction: .runAction(executable: .executable("GUIForCLIAppKit")),
      archiveAction: .archiveAction(configuration: .release)
    ),
    .scheme(
      name: "GUIForCLIObjCAppKit",
      shared: true,
      buildAction: .buildAction(targets: ["GUIForCLIObjCAppKit"]),
      runAction: .runAction(executable: .executable("GUIForCLIObjCAppKit")),
      archiveAction: .archiveAction(configuration: .release)
    ),
  ]
)
