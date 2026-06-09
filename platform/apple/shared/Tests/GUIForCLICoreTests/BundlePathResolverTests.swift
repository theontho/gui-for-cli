import Foundation
import Testing
#if os(Windows)
import WinSDK
#endif

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
    setEnvironmentVariable(key, previous)
  }
  setEnvironmentVariable(key, "/resolved")

  let expanded = BundlePathResolver.expand(
    "${\(key)}/output",
    rootURL: URL(fileURLWithPath: "/bundle"))

  #expect(expanded == "/resolved/output")
}

private func setEnvironmentVariable(_ key: String, _ value: String?) {
  #if os(Windows)
  key.withCString(encodedAs: UTF16.self) { keyPointer in
    if let value {
      value.withCString(encodedAs: UTF16.self) { valuePointer in
        _ = SetEnvironmentVariableW(keyPointer, valuePointer)
      }
    } else {
      _ = SetEnvironmentVariableW(keyPointer, nil)
    }
  }
  #else
  if let value {
    setenv(key, value, 1)
  } else {
    unsetenv(key)
  }
  #endif
}
