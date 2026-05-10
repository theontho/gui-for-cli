import Foundation

public enum DataSourceError: LocalizedError, Sendable {
  case scriptFailed(path: String, exitCode: Int32, message: String)
  case launchFailed(path: String, message: String)
  case invalidJSON(path: String, message: String, preview: String)
  case invalidPath(String)
  case timedOut(path: String, seconds: UInt64)
  case unsupportedPlatform

  public var errorDescription: String? {
    switch self {
    case .scriptFailed(let path, let exitCode, let message):
      return "\(path) exited with code \(exitCode): \(message)"
    case .launchFailed(let path, let message):
      return "Could not launch \(path): \(message)"
    case .invalidJSON(let path, let message, let preview):
      return "Could not decode JSON from \(path): \(message). Output: \(preview)"
    case .invalidPath(let path):
      return "Data source path must stay inside the bundle: \(path)"
    case .timedOut(let path, let seconds):
      return "\(path) did not finish within \(seconds) seconds."
    case .unsupportedPlatform:
      return "Script-backed data sources are only available on macOS."
    }
  }
}
