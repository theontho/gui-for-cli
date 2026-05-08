import Foundation

public struct ConfigBootstrapResult: Equatable, Sendable {
  public var controlID: String
  public var label: String
  public var url: URL
  public var status: ConfigBootstrapStatus
  public var keyCount: Int

  public init(
    controlID: String,
    label: String,
    url: URL,
    status: ConfigBootstrapStatus,
    keyCount: Int
  ) {
    self.controlID = controlID
    self.label = label
    self.url = url
    self.status = status
    self.keyCount = keyCount
  }

  public var message: String {
    switch status {
    case .created:
      "Created \(keyCount) setting(s) at \(url.path)"
    case .merged:
      "Added \(keyCount) missing setting(s) to \(url.path)"
    case .skippedExisting:
      "Settings already exist at \(url.path)"
    case .unchanged:
      "Settings already contain all configured keys at \(url.path)"
    case .wouldCreate:
      "Would create \(keyCount) setting(s) at \(url.path)"
    case .wouldMerge:
      "Would add \(keyCount) missing setting(s) to \(url.path)"
    case .wouldSkipExisting:
      "Would leave existing settings at \(url.path)"
    case .wouldLeaveUnchanged:
      "Would leave complete settings unchanged at \(url.path)"
    }
  }
}

public enum ConfigBootstrapStatus: String, Equatable, Sendable {
  case created
  case merged
  case skippedExisting
  case unchanged
  case wouldCreate
  case wouldMerge
  case wouldSkipExisting
  case wouldLeaveUnchanged
}
