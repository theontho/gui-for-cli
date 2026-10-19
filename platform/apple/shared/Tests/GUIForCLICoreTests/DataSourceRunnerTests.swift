import Foundation
import Testing

@testable import GUIForCLICore

#if os(macOS)
  @Suite struct DataSourceRunnerTests {
    private func bundle(script: String) throws -> URL {
      let root = try temporaryDirectory()
      let scripts = root.appendingPathComponent("scripts", isDirectory: true)
      try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
      try script.write(
        to: scripts.appendingPathComponent("source.sh"), atomically: true, encoding: .utf8)
      return root
    }

    @Test func loadReturnsAsSoonAsTheScriptExitsDespiteBackgroundDescendants() async throws {
      let root = try bundle(
        script: """
          printf '{"values":{"ready":"yes"}}'
          sleep 25 &
          exit 0
          """)
      defer { try? FileManager.default.removeItem(at: root) }
      let started = ContinuousClock.now

      let payload = try await DataSourceRunner.load(
        dataSource: ScriptDataSourceSpec(path: "scripts/source.sh"),
        rootURL: root,
        context: CommandRenderContext())

      #expect(payload.values == ["ready": "yes"])
      #expect(ContinuousClock.now - started < .seconds(3))
    }

    @Test func timeoutFiresOnScheduleForScriptsThatIgnoreTerm() async throws {
      let root = try bundle(script: "trap '' TERM\nsleep 30\n")
      defer { try? FileManager.default.removeItem(at: root) }
      let started = ContinuousClock.now

      await #expect(throws: DataSourceError.self) {
        try await DataSourceRunner.load(
          dataSource: ScriptDataSourceSpec(path: "scripts/source.sh"),
          rootURL: root,
          context: CommandRenderContext(),
          timeout: .milliseconds(500))
      }
      #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func reportsSignalDeathsInsteadOfExitCodes() async throws {
      let root = try bundle(script: "echo boom >&2\nkill -KILL $$\n")
      defer { try? FileManager.default.removeItem(at: root) }

      do {
        _ = try await DataSourceRunner.load(
          dataSource: ScriptDataSourceSpec(path: "scripts/source.sh"),
          rootURL: root,
          context: CommandRenderContext())
        Issue.record("expected the data source to fail")
      } catch let DataSourceError.scriptFailed(_, termination, message) {
        #expect(termination == .signaled(SIGKILL))
        #expect(message == "boom")
      }
    }

    @Test func cancellationTerminatesTheScript() async throws {
      let marker = try temporaryDirectory().appendingPathComponent("pid")
      let root = try bundle(script: "echo $$ > '\(marker.path)'\nsleep 30\n")
      defer { try? FileManager.default.removeItem(at: root) }

      let load = Task {
        try await DataSourceRunner.load(
          dataSource: ScriptDataSourceSpec(path: "scripts/source.sh"),
          rootURL: root,
          context: CommandRenderContext())
      }
      var pid: Int32?
      for _ in 0..<100 where pid == nil {
        try await Task.sleep(for: .milliseconds(20))
        pid = (try? String(contentsOf: marker, encoding: .utf8))
          .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      }
      let scriptPID = try #require(pid)
      load.cancel()
      await #expect(throws: CancellationError.self) { try await load.value }
      for _ in 0..<100 where kill(-scriptPID, 0) == 0 {
        try await Task.sleep(for: .milliseconds(20))
      }
      #expect(kill(-scriptPID, 0) != 0)
    }
  }

  @Suite struct DataSourceSignatureTests {
    let dataSource = ScriptDataSourceSpec(
      path: "scripts/list.py",
      arguments: ["options", "{{ref_path}}"],
      environment: ["LIBRARY": "{{config.genome_library}}"])

    private func signature(_ fields: [String: String], config: [String: String] = [:]) -> String {
      DataSourceRunner.signature(
        dataSource: dataSource,
        rootURL: URL(fileURLWithPath: "/bundle"),
        context: CommandRenderContext(fieldValues: fields, configValues: config))
    }

    @Test func ignoresFieldsTheDataSourceDoesNotReference() {
      #expect(
        signature(["ref_path": "/ref", "output": "a"])
          == signature(["ref_path": "/ref", "output": "ab"]))
    }

    @Test func changesWhenAReferencedPlaceholderChanges() {
      #expect(signature(["ref_path": "/ref"]) != signature(["ref_path": "/other"]))
      #expect(
        signature([:], config: ["genome_library": "a"])
          != signature([:], config: ["genome_library": "b"]))
    }
  }
#endif
