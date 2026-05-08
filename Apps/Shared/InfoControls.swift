import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

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

struct InfoButton: View {
  let text: String
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .help(text)
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      InfoPopoverContent(text: text)
    }
  }
}

struct InfoLabel: View {
  let text: String
  var tooltip: String?
  var font: Font?
  @State private var isPresented = false

  var body: some View {
    HStack(spacing: 6) {
      labelText
      if let tooltip {
        InfoButton(text: tooltip)
      }
    }
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      InfoPopoverContent(text: tooltip ?? "")
    }
  }

  @ViewBuilder private var labelText: some View {
    if let tooltip {
      Text(text)
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .onTapGesture {
          isPresented.toggle()
        }
        .quickHelp(tooltip)
    } else {
      Text(text)
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct InfoPopoverContent: View {
  let text: String
  private var preferredWidth: CGFloat {
    min(max(CGFloat(text.count) * 5.8, 280), 640)
  }

  var body: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(14)
      .frame(width: preferredWidth, alignment: .leading)
  }
}
