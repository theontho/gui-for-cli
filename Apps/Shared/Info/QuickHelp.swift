import GUIForCLICore
import SwiftUI

struct QuickHelpModifier: ViewModifier {
  let text: String
  @State private var isHovering = false
  @State private var isPresented = false
  @State private var showTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    #if os(macOS)
      content
        .onHover { hovering in
          isHovering = hovering
          showTask?.cancel()
          if hovering {
            showTask = Task {
              try? await Task.sleep(nanoseconds: 180_000_000)
              guard !Task.isCancelled else { return }
              await MainActor.run {
                if isHovering {
                  isPresented = true
                }
              }
            }
          } else {
            isPresented = false
          }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
          InfoPopoverContent(text: text)
        }
        .onDisappear {
          showTask?.cancel()
          showTask = nil
        }
    #else
      content
    #endif
  }
}

extension View {
  func quickHelp(_ text: String) -> some View {
    modifier(QuickHelpModifier(text: text))
  }

  @ViewBuilder
  func destructiveActionStyle(isDestructive: Bool, isDisabled: Bool) -> some View {
    if isDestructive && !isDisabled {
      self
        .foregroundStyle(.red)
        .tint(.red)
    } else {
      self
    }
  }
}
