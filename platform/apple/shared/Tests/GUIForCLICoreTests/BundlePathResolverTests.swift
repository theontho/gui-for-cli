import Foundation
import Testing

@testable import GUIForCLICore

@Test func bundlePathResolverPreservesUnsetEnvironmentVariables() {
  let expanded = BundlePathResolver.expand(
    "${GUI_FOR_CLI_MISSING}/output",
    rootURL: URL(fileURLWithPath: "/bundle"),
    environment: [:])

  #expect(expanded == "${GUI_FOR_CLI_MISSING}/output")
}

@Test func bundlePathResolverExpandsSetEnvironmentVariable() {
  let expanded = BundlePathResolver.expand(
    "${GUI_FOR_CLI_SET}/output",
    rootURL: URL(fileURLWithPath: "/bundle"),
    environment: ["GUI_FOR_CLI_SET": "/resolved"])

  #expect(expanded == "/resolved/output")
}

@Test func bundlePathResolverExpandsTokensAndKeepsUnknownPlaceholders() {
  let expanded = BundlePathResolver.expand(
    "{{ bundleRoot }}/{{ref_path}}/{{configHome}}",
    rootURL: URL(fileURLWithPath: "/bundle"),
    environment: ["XDG_CONFIG_HOME": "/xdg"])

  #expect(expanded == "/bundle/{{ref_path}}//xdg")
}
