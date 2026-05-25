import Foundation

public struct BundleTestReport: Codable, Equatable, Sendable {
  public var planName: String?
  public var bundleID: String
  public var bundleName: String
  public var bundleVersion: String?
  public var bundleRoot: String
  public var status: BundleTestStatus
  public var startedAt: String
  public var finishedAt: String
  public var summary: BundleTestSummary
  public var messages: [String]
  public var steps: [BundleTestStepReport]

  public init(
    planName: String? = nil,
    bundleID: String,
    bundleName: String,
    bundleVersion: String? = nil,
    bundleRoot: String,
    status: BundleTestStatus,
    startedAt: String,
    finishedAt: String,
    summary: BundleTestSummary,
    messages: [String] = [],
    steps: [BundleTestStepReport]
  ) {
    self.planName = planName
    self.bundleID = bundleID
    self.bundleName = bundleName
    self.bundleVersion = bundleVersion
    self.bundleRoot = bundleRoot
    self.status = status
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.summary = summary
    self.messages = messages
    self.steps = steps
  }
}

public struct BundleTestSummary: Codable, Equatable, Sendable {
  public var total: Int
  public var passed: Int
  public var failed: Int
  public var skipped: Int

  public init(total: Int, passed: Int, failed: Int, skipped: Int) {
    self.total = total
    self.passed = passed
    self.failed = failed
    self.skipped = skipped
  }
}

public struct BundleTestStepReport: Codable, Equatable, Sendable {
  public var index: Int
  public var id: String?
  public var kind: BundleTestStepKind
  public var actionID: String?
  public var status: BundleTestStatus
  public var command: String?
  public var exitCode: Int32?
  public var timedOut: Bool
  public var startedAt: String
  public var finishedAt: String
  public var durationSeconds: Double
  public var output: String
  public var error: String?

  public init(
    index: Int,
    id: String? = nil,
    kind: BundleTestStepKind,
    actionID: String? = nil,
    status: BundleTestStatus,
    command: String? = nil,
    exitCode: Int32? = nil,
    timedOut: Bool = false,
    startedAt: String,
    finishedAt: String,
    durationSeconds: Double,
    output: String = "",
    error: String? = nil
  ) {
    self.index = index
    self.id = id
    self.kind = kind
    self.actionID = actionID
    self.status = status
    self.command = command
    self.exitCode = exitCode
    self.timedOut = timedOut
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.durationSeconds = durationSeconds
    self.output = output
    self.error = error
  }
}

public enum BundleTestStatus: String, Codable, Equatable, Sendable {
  case passed
  case failed
  case skipped
}
