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

  private let runtime: WebViewRuntime

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

  private func launchServer() {
    let process = Process()
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
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      serverProcess = process
      serverPIDForSignal = process.processIdentifier
      print("node_pid=\(process.processIdentifier)")
      printMetric("nodeProcessStarted")
    } catch {
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

  private func waitForServerThenLoad() {
    let url = URL(string: "http://\(runtime.host):\(runtime.port)/api/manifest")!
    poll(url: url) { [weak self] in
      guard let self else { return }
      printMetric("serverManifestReady")
      DispatchQueue.main.async {
        self.createWindowAndLoad()
      }
    }
  }

  private func poll(url: URL, completion: @escaping () -> Void) {
    URLSession.shared.dataTask(with: url) { _, response, _ in
      if (response as? HTTPURLResponse)?.statusCode == 200 {
        completion()
        return
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(25)) {
        self.poll(url: url, completion: completion)
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
    webView.load(URLRequest(url: URL(string: "http://\(runtime.host):\(runtime.port)/")!))
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    printMetric("webNavigationDidFinish")
    pollForRenderedPage()
  }

  private func pollForRenderedPage() {
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
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
          self.pollForRenderedPage()
        }
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
  let port: Int

  static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws
    -> Self
  {
    let host = environment["GFC_HOST"] ?? "127.0.0.1"
    let port = try Int(environment["GFC_PORT"] ?? "") ?? freePort()
    let rootURL = try runtimeRoot(environment: environment)
    let nodeURL = try nodeURL(rootURL: rootURL, environment: environment)
    let serverURL = rootURL.appendingPathComponent("WebUI/dist/server/main.js")
    let bundleURL =
      environment["GFC_BUNDLE"].map(URL.init(fileURLWithPath:))
      ?? rootURL.appendingPathComponent("Examples/WGSExtract")

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
        atPath: resourceURL.appendingPathComponent("WebUI/dist/server/main.js").path)
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

  private static func freePort() throws -> Int {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw RuntimeError.noFreePort }
    defer { close(socketFD) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        Darwin.bind(socketFD, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else { throw RuntimeError.noFreePort }

    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        getsockname(socketFD, rebound, &length)
      }
    }
    guard nameResult == 0 else { throw RuntimeError.noFreePort }
    return Int(UInt16(bigEndian: address.sin_port))
  }
}

enum RuntimeError: Error, CustomStringConvertible {
  case missingRuntimeRoot
  case missingPath(String, String)
  case noFreePort

  var description: String {
    switch self {
    case .missingRuntimeRoot:
      return "Could not find bundled WebUI resources. Set GFC_REPO_ROOT for development runs."
    case let .missingPath(label, path):
      return "Missing \(label): \(path)"
    case .noFreePort:
      return "Could not allocate a local server port."
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
