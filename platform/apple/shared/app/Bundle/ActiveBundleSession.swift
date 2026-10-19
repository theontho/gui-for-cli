import Foundation
import GUIForCLICore

/// A loaded bundle together with the stores that own its processes and
/// pending writes, so whoever replaces the bundle can tear it all down.
@MainActor
final class ActiveBundleSession: Identifiable {
  let id = UUID()
  let session: BundleSession
  let sourceRootURL: URL
  let terminal: TerminalLogStore
  let configStore: BundleConfigStore

  init(session: BundleSession, sourceRootURL: URL) {
    self.session = session
    self.sourceRootURL = sourceRootURL
    let terminal = TerminalLogStore(
      exitCodeReference: session.manifest.effectiveExitCodeReference,
      localizationLabels: session.localizationLabels,
      locale: Locale(identifier: session.localizationCode),
      startupLines: session.startupMessages)
    self.terminal = terminal
    configStore = BundleConfigStore(session: session) { [weak terminal] message in
      terminal?.appendToMain(message)
    }
  }

  /// Writes pending state and terminates every process tree the session started.
  func tearDown() {
    configStore.flushPendingWrites()
    terminal.terminateAll()
  }
}
