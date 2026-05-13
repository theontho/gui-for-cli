import Foundation
import GUIForCLICore

@MainActor
final class AppKitActionInvocation: NSObject {
  let action: ActionSpec
  private let contextProvider: @MainActor () -> CommandRenderContext

  init(action: ActionSpec, contextProvider: @escaping @MainActor () -> CommandRenderContext) {
    self.action = action
    self.contextProvider = contextProvider
  }

  func context() -> CommandRenderContext {
    contextProvider()
  }
}
