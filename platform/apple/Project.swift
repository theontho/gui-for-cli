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

  static func load(defaultName: String) -> AppIdentity {
    let configURL = repoRootURL.appendingPathComponent("tmp/app-identity.json")
    guard
      let data = try? Data(contentsOf: configURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return AppIdentity(displayName: defaultName, productName: defaultName)
    }

    let manifestDisplayName = (json["embeddedBundlePath"] as? String).flatMap { path in
      bundleDisplayName(inBundleAt: path)
    }
    let resolvedDisplayName =
      nonEmpty(json["displayName"] as? String) ?? manifestDisplayName ?? defaultName
    let resolvedProductName = nonEmpty(json["productName"] as? String) ?? resolvedDisplayName
    return AppIdentity(displayName: resolvedDisplayName, productName: resolvedProductName)
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

private let appIdentity = AppIdentity.load(defaultName: defaultAppName)
private let appKitDisplayName = "swift appkit test"
private let appKitProductName = "swift appkit test"

let baseSettings: SettingsDictionary = [
  "CURRENT_PROJECT_VERSION": .string(buildVersion),
  "DEVELOPMENT_TEAM": "",
  "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
  "MARKETING_VERSION": .string(marketingVersion),
  "SWIFT_STRICT_CONCURRENCY": "complete",
  "SWIFT_VERSION": "6.0",
]

let appInfoPlist: InfoPlist = .extendingDefault(with: [
  "CFBundleDisplayName": .string(appIdentity.displayName),
  "CFBundleIconName": "AppIcon",
  "CFBundleName": .string(appIdentity.displayName),
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
  "CFBundleShortVersionString": "$(MARKETING_VERSION)",
  "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
  "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
  "NSPrincipalClass": "NSApplication",
])

let objcAppInfoPlist: InfoPlist = .extendingDefault(with: [
  "CFBundleDisplayName": .string("\(appIdentity.displayName) ObjC AppKit Test"),
  "CFBundleIconName": "AppIcon",
  "CFBundleName": .string("\(appIdentity.displayName) ObjC AppKit Test"),
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
      dependencies: [coreDependency],
      settings: .settings(base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "PRODUCT_NAME": .string(appIdentity.productName),
        "TARGETED_DEVICE_FAMILY": "1,2",
      ])
    ),
    .target(
      name: "GUIForCLIMac",
      destinations: [.mac],
      product: .app,
      productName: "GUIForCLI",
      bundleId: "\(bundlePrefix).gui-for-cli.mac",
      deploymentTargets: .macOS("14.0"),
      infoPlist: appInfoPlist,
      sources: [
        "swiftui/**/*.swift",
        "shared/app/**/*.swift",
      ],
      resources: appResources,
      dependencies: [coreDependency],
      settings: .settings(base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "PRODUCT_NAME": .string(appIdentity.productName),
      ])
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
      dependencies: [coreDependency],
      settings: .settings(base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "PRODUCT_NAME": .string(appKitProductName),
      ])
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
      settings: .settings(base: [
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "GCC_PREPROCESSOR_DEFINITIONS": "GFC_SOURCE_ROOT=\\\"$(SRCROOT)/../..\\\"",
        "PRODUCT_NAME": "GUI for CLI ObjC AppKit Test",
      ])
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
