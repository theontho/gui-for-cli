import AppKit
import Darwin
import Foundation
import WebKit

private var serverPIDForSignal: pid_t = 0

final class WebViewShellApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  private let startedAt = DispatchTime.now()
  private var serverProcess: Process?
  private var window: NSWindow?
  private var webView: WKWebView?
  private var didReportReady = false

  private var runtime: WebViewRuntime

  override init() {
    do {
      runtime = try WebViewRuntime.resolve()
    } catch {
      fputs("error=\(error)\n", stderr)
      exit(1)
    }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    printMetric("appDidFinishLaunching")
    launchServer()
    waitForServerThenLoad()
  }

  func applicationWillTerminate(_ notification: Notification) {
    terminateServer()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func launchServer() {
    let process = Process()
    let portFileURL =
      runtime.port == 0
      ? FileManager.default.temporaryDirectory.appendingPathComponent(
        "gui-for-cli-webview-\(UUID().uuidString).port")
      : nil
    process.executableURL = runtime.nodeURL
    process.currentDirectoryURL = runtime.rootURL
    process.arguments = [
      runtime.serverURL.path,
      "--port", "\(runtime.port)",
      "--host", runtime.host,
      "--bundle", runtime.bundleURL.path,
    ]
    var environment = ProcessInfo.processInfo.environment
    environment["GFC_PARENT_PID"] = "\(ProcessInfo.processInfo.processIdentifier)"
    if let portFileURL {
      environment["GFC_PORT_FILE"] = portFileURL.path
    }
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      serverProcess = process
      serverPIDForSignal = process.processIdentifier
      print("node_pid=\(process.processIdentifier)")
      printMetric("nodeProcessStarted")
      if let portFileURL {
        runtime.port = try waitForAssignedPort(fileURL: portFileURL)
      }
    } catch {
      if let portFileURL {
        try? FileManager.default.removeItem(at: portFileURL)
      }
      terminateServer()
      fputs("error=failedToLaunchNode: \(error)\n", stderr)
      NSApp.terminate(nil)
    }
  }

  private func terminateServer() {
    if let serverProcess, serverProcess.isRunning {
      serverProcess.terminate()
    }
    serverPIDForSignal = 0
  }

  private func waitForAssignedPort(fileURL: URL) throws -> Int {
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
      if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
        let port = Int(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
        port > 0
      {
        try? FileManager.default.removeItem(at: fileURL)
        return port
      }
      Thread.sleep(forTimeInterval: 0.025)
    }
    throw RuntimeError.portFileTimeout(fileURL.path)
  }

  private func waitForServerThenLoad() {
    guard let url = runtime.url(path: "/api/manifest") else {
      fputs("error=invalidManifestURL\n", stderr)
      NSApp.terminate(nil)
      return
    }
    poll(url: url) { [weak self] in
      guard let self else { return }
      printMetric("serverManifestReady")
      DispatchQueue.main.async {
        self.createWindowAndLoad()
      }
    }
  }

  private func poll(
    url: URL, deadline: DispatchTime = .now() + .seconds(15), completion: @escaping () -> Void
  ) {
    URLSession.shared.dataTask(with: url) { [weak self] _, response, _ in
      guard let self else { return }
      if (response as? HTTPURLResponse)?.statusCode == 200 {
        completion()
        return
      }
      guard DispatchTime.now() < deadline else {
        fputs("error=serverStartupTimeout\n", stderr)
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
        guard let self else { return }
        self.poll(url: url, deadline: deadline, completion: completion)
      }
    }.resume()
  }

  private func createWindowAndLoad() {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    self.webView = webView

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "GUI for CLI WebView Shell"
    window.center()
    window.contentView = webView
    window.makeKeyAndOrderFront(nil)
    self.window = window

    printMetric("windowShown")
    guard let url = runtime.url(path: "/") else {
      fputs("error=invalidWebUIURL\n", stderr)
      NSApp.terminate(nil)
      return
    }
    webView.load(URLRequest(url: url))
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    printMetric("webNavigationDidFinish")
    pollForRenderedPage()
  }

  private func pollForRenderedPage(deadline: DispatchTime = .now() + .seconds(15)) {
    guard !didReportReady, let webView else { return }
    let script = """
      (() => {
        const app = document.querySelector('#app');
        return Boolean(app && app.dataset.state === 'ready' && document.title);
      })()
      """
    webView.evaluateJavaScript(script) { [weak self] value, _ in
      guard let self else { return }
      if (value as? Bool) == true {
        self.didReportReady = true
        self.printMetric("webAppRendered")
      } else if DispatchTime.now() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
          self?.pollForRenderedPage(deadline: deadline)
        }
      } else {
        fputs("error=webAppRenderTimeout\n", stderr)
        NSApp.terminate(nil)
      }
    }
  }

  private func printMetric(_ name: String) {
    let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
    let milliseconds = Double(elapsed) / 1_000_000
    print("metric \(name)_ms=\(String(format: "%.1f", milliseconds))")
    fflush(stdout)
  }
}

struct WebViewRuntime {
  let rootURL: URL
  let nodeURL: URL
  let serverURL: URL
  let bundleURL: URL
  let host: String
  var port: Int

  static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws
    -> Self
  {
    let host = environment["GFC_HOST"] ?? "127.0.0.1"
    let port = try configuredPort(environment: environment)
    let rootURL = try runtimeRoot(environment: environment)
    let nodeURL = try nodeURL(rootURL: rootURL, environment: environment)
    let serverURL = rootURL.appendingPathComponent("platform/typescript/dist/web/src/server/main.js")
    let bundleURL =
      environment["GFC_BUNDLE"].map(URL.init(fileURLWithPath:))
      ?? rootURL.appendingPathComponent("examples/WGSExtract")

    guard FileManager.default.fileExists(atPath: serverURL.path) else {
      throw RuntimeError.missingPath("WebUI server script", serverURL.path)
    }
    guard FileManager.default.fileExists(atPath: bundleURL.path) else {
      throw RuntimeError.missingPath("bundle", bundleURL.path)
    }

    return Self(
      rootURL: rootURL, nodeURL: nodeURL, serverURL: serverURL, bundleURL: bundleURL, host: host,
      port: port)
  }

  private static func runtimeRoot(environment: [String: String]) throws -> URL {
    if let root = environment["GFC_REPO_ROOT"] {
      return URL(fileURLWithPath: root)
    }
    if let resourceURL = Bundle.main.resourceURL,
      FileManager.default.fileExists(
        atPath: resourceURL.appendingPathComponent("platform/typescript/dist/web/src/server/main.js").path)
    {
      return resourceURL
    }
    throw RuntimeError.missingRuntimeRoot
  }

  private static func nodeURL(rootURL: URL, environment: [String: String]) throws -> URL {
    if let nodePath = environment["GFC_NODE_PATH"] {
      return URL(fileURLWithPath: nodePath)
    }
    let bundled = rootURL.appendingPathComponent("node/bin/node")
    guard FileManager.default.isExecutableFile(atPath: bundled.path) else {
      throw RuntimeError.missingPath("bundled Node runtime", bundled.path)
    }
    return bundled
  }

  private static func configuredPort(environment: [String: String]) throws -> Int {
    guard let value = environment["GFC_PORT"], !value.isEmpty else {
      return 0
    }
    guard let port = Int(value), port >= 0, port <= UInt16.max else {
      throw RuntimeError.invalidPort(value)
    }
    return port
  }

  func url(path: String) -> URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = port
    components.path = path
    return components.url
  }
}

enum RuntimeError: Error, CustomStringConvertible {
  case missingRuntimeRoot
  case missingPath(String, String)
  case invalidPort(String)
  case portFileTimeout(String)

  var description: String {
    switch self {
    case .missingRuntimeRoot:
      return "Could not find bundled WebUI resources. Set GFC_REPO_ROOT for development runs."
    case let .missingPath(label, path):
      return "Missing \(label): \(path)"
    case let .invalidPort(value):
      return "Invalid GFC_PORT: \(value)"
    case let .portFileTimeout(path):
      return "Timed out waiting for WebUI server port file: \(path)"
    }
  }
}

let app = NSApplication.shared
let delegate = WebViewShellApp()
signal(SIGTERM) { _ in
  if serverPIDForSignal > 0 {
    kill(serverPIDForSignal, SIGTERM)
  }
  exit(0)
}
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
