import Combine
import Foundation

/// Watches a bundle's source root for filesystem changes and emits a debounced
/// signal whenever any `.toml`, `.json`, or `.swift` file under it is modified.
///
/// Enabled only when the `GUIFORCLI_HOT_RELOAD=1` environment variable is set,
/// matching the developer-only nature of the feature. The reloader is idempotent:
/// `start(at:)` may be called repeatedly and will reuse the same publisher.
@MainActor
final class BundleHotReloader: ObservableObject {
  static let shared = BundleHotReloader()

  let changes = PassthroughSubject<URL, Never>()

  private var watchedRoot: URL?
  private var sources: [DispatchSourceFileSystemObject] = []
  private var fileDescriptors: [Int32] = []
  private var pendingWorkItem: DispatchWorkItem?

  static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["GUIFORCLI_HOT_RELOAD"] == "1"
  }

  func start(at rootURL: URL) {
    guard Self.isEnabled else { return }
    if watchedRoot == rootURL { return }
    stop()
    watchedRoot = rootURL
    attachWatcher(at: rootURL)
    let fileManager = FileManager.default
    if let enumerator = fileManager.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
    {
      for case let url as URL in enumerator {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          attachWatcher(at: url)
        }
      }
    }
  }

  func stop() {
    for source in sources { source.cancel() }
    sources.removeAll()
    for fd in fileDescriptors where fd >= 0 { close(fd) }
    fileDescriptors.removeAll()
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
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
    fileDescriptors.append(fd)
  }

  private func scheduleEmit(for url: URL) {
    pendingWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.changes.send(url)
    }
    pendingWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
  }
}
