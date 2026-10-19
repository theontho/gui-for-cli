import Foundation

public enum DataSourceError: LocalizedError, Sendable {
  case scriptFailed(path: String, termination: ProcessTermination, message: String)
  case launchFailed(path: String, message: String)
  case invalidJSON(path: String, message: String, preview: String)
  case invalidPath(String)
  case timedOut(path: String, timeout: Duration)
  case unsupportedPlatform

  public var errorDescription: String? {
    switch self {
    case .scriptFailed(let path, let termination, let message):
      return "\(path) failed (\(termination.summary)): \(message)"
    case .launchFailed(let path, let message):
      return "Could not launch \(path): \(message)"
    case .invalidJSON(let path, let message, let preview):
      return "Could not decode JSON from \(path): \(message). Output: \(preview)"
    case .invalidPath(let path):
      return "Data source path must stay inside the bundle: \(path)"
    case .timedOut(let path, let timeout):
      return "\(path) did not finish within \(timeout.components.seconds) seconds."
    case .unsupportedPlatform:
      return "Script-backed data sources are only available on macOS."
    }
  }
}
