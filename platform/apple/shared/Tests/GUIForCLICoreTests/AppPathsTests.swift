import Foundation
import Testing

@testable import GUIForCLICore

@Test func appSupportContainerCanUseAppIdentifierForUninstallDiscovery() {
  let environment = [
    AppPaths.appSupportNameEnvironmentKey: "dev.guiforcli.embed.wgsextract"
  ]
  let directory = AppPaths.bundleWorkspaceDirectory(
    for: "wgs-extract",
    environment: environment)

  #expect(directory.path.contains("/Application Support/dev.guiforcli.embed.wgsextract/"))
  #expect(directory.lastPathComponent == "wgs-extract")
}

@Test func appSupportContainerFallsBackToGenericCLIName() {
  #expect(AppPaths.appSupportContainerName(environment: [:]) == AppPaths.appName)
}
