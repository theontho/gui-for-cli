import Foundation

public enum ConfigBootstrapError: LocalizedError, Equatable {
  case unsafeScriptPath(String)
  case missingScript(URL)
  case scriptFailed(URL, Int32, String)
  case invalidScriptOutput(URL, String)
  case missingScriptContents(URL)
  case unsupportedScriptPlatform

  public var errorDescription: String? {
    switch self {
    case .unsafeScriptPath(let path):
      "Config bootstrap script path must be relative and stay inside the bundle: \(path)"
    case .missingScript(let url):
      "Config bootstrap script does not exist: \(url.path)"
    case .scriptFailed(let url, let status, let output):
      "Config bootstrap script failed with exit code \(status): \(url.path)\n\(output)"
    case .invalidScriptOutput(let url, let output):
      "Config bootstrap script did not return valid JSON: \(url.path)\n\(output)"
    case .missingScriptContents(let url):
      "Config bootstrap script contents file does not exist: \(url.path)"
    case .unsupportedScriptPlatform:
      "Config bootstrap scripts are only available on macOS."
    }
  }
}
