import AppKit

@MainActor
final class AppKitActionButton: NSButton {
  var invocation: AppKitActionInvocation?
}
