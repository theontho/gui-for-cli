import Combine
import Foundation

/// Watches a bundle's source root for filesystem changes and emits a debounced
/// signal whenever any file under it is modified.
///
/// Enabled only when the `GUIFORCLI_HOT_RELOAD=1` environment variable is set,
/// matching the developer-only nature of the feature. `start(at:)` may be called
/// repeatedly and reuses the same watchers for the same root.
@MainActor
final class BundleHotReloader {
  static let shared = BundleHotReloader()

  let changes = PassthroughSubject<URL, Never>()

  private var watchedRoot: URL?
  /// Each source owns its descriptor and closes it from its cancel handler.
  private var sources: [any DispatchSourceFileSystemObject] = []
  private var pendingEmit: Task<Void, Never>?

  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["GUIFORCLI_HOT_RELOAD"] == "1"
  }

  func start(at rootURL: URL) {
    guard Self.isEnabled else { return }
    if watchedRoot == rootURL { return }
    stop()
    watchedRoot = rootURL
    attachWatcher(at: rootURL)
    let enumerator = FileManager.default.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
    while let url = enumerator?.nextObject() as? URL {
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        attachWatcher(at: url)
      }
    }
  }

  func stop() {
    for source in sources { source.cancel() }
    sources.removeAll()
    pendingEmit?.cancel()
    pendingEmit = nil
    watchedRoot = nil
  }

  private func attachWatcher(at url: URL) {
    let fd = open(url.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .extend, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility))
    source.setEventHandler { [weak self] in
      Task { @MainActor in
        self?.scheduleEmit(for: url)
      }
    }
    source.setCancelHandler {
      close(fd)
    }
    source.resume()
    sources.append(source)
  }

  private func scheduleEmit(for url: URL) {
    pendingEmit?.cancel()
    pendingEmit = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      self?.changes.send(url)
    }
  }
}
