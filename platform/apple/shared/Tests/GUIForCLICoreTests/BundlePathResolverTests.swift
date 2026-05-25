import Foundation
import Testing

@testable import GUIForCLICore

@Test func bundlePathResolverPreservesUnsetEnvironmentVariables() {
  let key = "GUI_FOR_CLI_MISSING_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

  let expanded = BundlePathResolver.expand(
    "${\(key)}/output",
    rootURL: URL(fileURLWithPath: "/bundle"))

  #expect(expanded == "${\(key)}/output")
}

@Test func bundlePathResolverExpandsSetEnvironmentVariable() {
  let key = "GUI_FOR_CLI_SET_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
  let previous = ProcessInfo.processInfo.environment[key]
  defer {
    if let previous {
      _ = setenv(key, previous, 1)
    } else {
      _ = unsetenv(key)
    }
  }
  _ = setenv(key, "/resolved", 1)

  let expanded = BundlePathResolver.expand(
    "${\(key)}/output",
    rootURL: URL(fileURLWithPath: "/bundle"))

  #expect(expanded == "/resolved/output")
}
