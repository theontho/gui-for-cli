import Foundation
import Testing

@testable import GUIForCLICore

@Test func bundleTestRunnerExecutesSetupAndActionsWithInputs() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  let plan = BundleTestPlan(
    name: "smoke",
    inputs: BundleTestInputs(fieldValues: ["sample": "Ada"]),
    steps: [
      BundleTestStep(kind: .setup),
      BundleTestStep(kind: .action, actionID: "say-hello", requiredOutput: ["action:Ada"]),
    ])
  let progress = BundleTestProgressCollector()

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: plan,
    options: BundleTestRunnerOptions(
      workspaceURL: workspaceURL,
      progressHandler: progress.append))

  #expect(report.status == .passed)
  #expect(report.summary.passed == 2)
  #expect(report.steps[0].output.contains("setup-ok"))
  #expect(report.steps[1].command?.contains("action:Ada") == true)
  #expect(report.steps[1].output == "action:Ada\n")
  #expect(progress.messages().contains { $0.contains("Bundle test started: smoke") })
  #expect(progress.messages().contains { $0.contains("Step 1/2 started: setup") })
  #expect(progress.messages().contains { $0.contains("Step 2/2 passed") })
  #expect(progress.output().contains("setup-ok"))
  #expect(progress.output().contains("action:Ada"))
}

@Test func bundleTestRunnerReportsMissingInputsAndSkipsRemainingSteps() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let plan = BundleTestPlan(
    steps: [
      BundleTestStep(kind: .action, actionID: "say-hello"),
      BundleTestStep(kind: .action, actionID: "say-hello"),
    ])

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: plan,
    options: BundleTestRunnerOptions(
      workspaceURL: bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")))

  #expect(report.status == .failed)
  #expect(report.steps[0].status == .failed)
  #expect(report.steps[0].error == "Missing input values: sample")
  #expect(report.steps[1].status == .skipped)
}

@Test func bundleTestRunnerExpandsBundleTokensInRowValues() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  let rowRef = workspaceURL.appendingPathComponent("reference/genomes/hg19.fa.gz").path
  let plan = BundleTestPlan(
    steps: [
      BundleTestStep(
        kind: .action,
        actionID: "show-row-ref",
        controlID: "refs",
        rowValues: ["ref": "{{bundleWorkspace}}/reference/genomes/hg19.fa.gz"],
        requiredOutput: ["action:\(rowRef)"])
    ])

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: plan,
    options: BundleTestRunnerOptions(workspaceURL: workspaceURL))

  #expect(report.status == .passed)
  #expect(report.steps[0].output == "action:\(rowRef)\n")
}

@Test func bundleTestRunnerOverlaysExplicitRowValuesOntoHydratedRow() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  let overrideRef = workspaceURL.appendingPathComponent("reference/genomes/override.fa.gz").path
  let plan = BundleTestPlan(
    steps: [
      BundleTestStep(
        kind: .action,
        actionID: "show-row-context",
        controlID: "refs",
        rowID: "hg19",
        rowValues: ["ref": "{{bundleWorkspace}}/reference/genomes/override.fa.gz"],
        requiredOutput: ["action:hg19|GRCh37|\(overrideRef)|installed"])
    ])

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: plan,
    options: BundleTestRunnerOptions(workspaceURL: workspaceURL))

  #expect(report.status == .passed)
  #expect(report.steps[0].output == "action:hg19|GRCh37|\(overrideRef)|installed\n")
}

@Test func bundleTestRunnerRejectsUnmanagedExplicitWorkspace() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
  let existingURL = workspaceURL.appendingPathComponent("keep.txt")
  try "do-not-overwrite".write(to: existingURL, atomically: true, encoding: .utf8)

  #expect(throws: BundleLoadError.unmanagedWorkspace(workspaceURL)) {
    _ = try BundleTestRunner().run(
      bundleURL: bundleURL,
      plan: BundleTestPlan(steps: []),
      options: BundleTestRunnerOptions(workspaceURL: workspaceURL))
  }
  #expect(try String(contentsOf: existingURL, encoding: .utf8) == "do-not-overwrite")
}

@Test func bundleTestRunnerUpgradesOlderManagedExplicitWorkspace() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
  try "GUI for CLI bundle workspace\n".write(
    to: workspaceURL.appendingPathComponent(".bundle-workspace"),
    atomically: true,
    encoding: .utf8)
  let olderMetadata = TestWorkspaceMetadata(
    version: 1,
    sourceRoot: bundleURL.standardizedFileURL.path,
    sourceSignature: [])
  let olderData = try JSONEncoder().encode(olderMetadata)
  let metadataURL = workspaceURL.appendingPathComponent(".gui-for-cli-workspace.json")
  try olderData.write(to: metadataURL, options: .atomic)

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: BundleTestPlan(steps: []),
    options: BundleTestRunnerOptions(workspaceURL: workspaceURL))

  #expect(report.status == .passed)
  let updatedMetadata = try JSONDecoder().decode(
    TestWorkspaceMetadata.self,
    from: Data(contentsOf: metadataURL))
  #expect(updatedMetadata.version == 2)
  #expect(updatedMetadata.sourceRoot == bundleURL.standardizedFileURL.path)
}

@Test func bundleTestRunnerExpandsBundleTokensInCheckedOptions() throws {
  let bundleURL = try writeBundleTestFixture()
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let workspaceURL = bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")
  let selectedFormat = workspaceURL.appendingPathComponent("reference/genomes/hg19.fa.gz").path
  let plan = BundleTestPlan(
    steps: [
      BundleTestStep(
        kind: .action,
        actionID: "show-formats",
        inputs: BundleTestInputs(
          checkedOptions: ["formats": ["{{bundleWorkspace}}/reference/genomes/hg19.fa.gz"]]),
        requiredOutput: ["action:\(selectedFormat)"])
    ])

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: plan,
    options: BundleTestRunnerOptions(workspaceURL: workspaceURL))

  #expect(report.status == .passed)
  #expect(report.steps[0].output == "action:\(selectedFormat)\n")
}

@Test func bundleTestRunnerOmitsSetupExitCodeOnTimeout() throws {
  let bundleURL = try writeBundleTestFixture(setupScript: "sleep 1\n")
  defer { try? FileManager.default.removeItem(at: bundleURL.deletingLastPathComponent()) }

  let report = try BundleTestRunner().run(
    bundleURL: bundleURL,
    plan: BundleTestPlan(
      steps: [
        BundleTestStep(kind: .setup, timeoutSeconds: 0.01)
      ]),
    options: BundleTestRunnerOptions(
      workspaceURL: bundleURL.deletingLastPathComponent().appendingPathComponent("workspace")))

  let step = try #require(report.steps.first)
  #expect(report.status == .failed)
  #expect(step.status == .failed)
  #expect(step.timedOut)
  #expect(step.exitCode == nil)
  #expect(step.error == "Setup command timed out: Setup")
}

@Test func bundleTestProcessRunnerCapsStoredOutputButStreamsFullOutput() throws {
  let progress = BundleTestStringCollector()
  let command = RenderedCommand(
    executable: "/bin/sh",
    arguments: [
      "-c", "i=0; while [ \"$i\" -lt 256 ]; do printf x; i=$((i + 1)); done",
    ])

  let result = try BundleTestProcessRunner(maxOutputBytes: 64).run(
    command: command,
    workingDirectory: nil,
    onOutput: progress.append)

  #expect(result.exitStatus == 0)
  #expect(result.output.utf8.count < progress.output().utf8.count)
  #expect(result.output.contains("[output truncated after 64 bytes]"))
  #expect(progress.output().count == 256)
}

private func writeBundleTestFixture(setupScript: String = "printf 'setup-ok\n'\n") throws -> URL {
  let root = try temporaryDirectory()
  let bundleURL = root.appendingPathComponent("Bundle", isDirectory: true)
  let scriptsURL = bundleURL.appendingPathComponent("scripts", isDirectory: true)
  try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
  try setupScript.write(
    to: scriptsURL.appendingPathComponent("setup.sh"),
    atomically: true,
    encoding: .utf8)
  try manifestJSON.write(
    to: bundleURL.appendingPathComponent("manifest.json"),
    atomically: true,
    encoding: .utf8)
  return bundleURL
}

private let manifestJSON = #"""
  {
    "id": "dev.guiforcli.bundle-test-fixture",
    "displayName": "Bundle Test Fixture",
    "summary": "Exercises the bundle test runner.",
    "setup": {
      "steps": [
        {
          "id": "setup",
          "kind": "setupScript",
          "label": "Setup",
          "value": "scripts/setup.sh"
        }
      ]
    },
    "pages": [
      {
        "id": "main",
        "title": "Main",
        "summary": "Main actions",
        "sections": [
          {
            "id": "inputs",
            "controls": [
              {
                "id": "sample",
                "label": "Sample",
                "kind": "text"
              },
              {
                "id": "refs",
                "label": "Refs",
                "kind": "libraryList",
                "rowTemplate": {
                  "id": "{{id}}",
                  "title": "{{name}}",
                  "values": {
                    "ref": "{{ref}}"
                  },
                  "status": "{{status}}"
                },
                "items": [
                  {
                    "id": "hg19",
                    "name": "GRCh37",
                    "ref": "reference/genomes/hg19.fa.gz",
                    "status": "installed"
                  }
                ],
                "rowActions": [
                  {
                    "id": "show-row-ref",
                    "title": "Show row ref",
                    "command": {
                      "executable": "/bin/sh",
                      "arguments": [
                        "-c",
                        "printf 'action:{{row.ref}}\\n'"
                      ]
                    }
                  },
                  {
                    "id": "show-row-context",
                    "title": "Show row context",
                    "command": {
                      "executable": "/bin/sh",
                      "arguments": [
                        "-c",
                        "printf 'action:{{row.id}}|{{row.title}}|{{row.ref}}|{{row.status}}\\n'"
                      ]
                    }
                  }
                ]
              }
            ],
            "actions": [
              {
                "id": "say-hello",
                "title": "Say hello",
                "command": {
                  "executable": "/bin/sh",
                  "arguments": [
                    "-c",
                    "printf 'action:{{sample}}\\n'"
                  ]
                }
              },
              {
                "id": "show-formats",
                "title": "Show formats",
                "command": {
                  "executable": "/bin/sh",
                  "arguments": [
                    "-c",
                    "printf 'action:{{formats}}\\n'"
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
  }
  """#

private final class BundleTestProgressCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var progressMessages: [String] = []
  private var outputChunks: [String] = []

  func append(_ event: BundleTestProgressEvent) {
    lock.lock()
    switch event {
    case .message(let message):
      progressMessages.append(message)
    case .commandOutput(let chunk):
      outputChunks.append(chunk)
    }
    lock.unlock()
  }

  func messages() -> [String] {
    lock.lock()
    let values = progressMessages
    lock.unlock()
    return values
  }

  func output() -> String {
    lock.lock()
    let text = outputChunks.joined()
    lock.unlock()
    return text
  }
}

private final class BundleTestStringCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks: [String] = []

  func append(_ chunk: String) {
    lock.lock()
    chunks.append(chunk)
    lock.unlock()
  }

  func output() -> String {
    lock.lock()
    let text = chunks.joined()
    lock.unlock()
    return text
  }
}

private struct TestWorkspaceMetadata: Codable {
  var version: Int
  var sourceRoot: String
  var sourceSignature: [String]
}
