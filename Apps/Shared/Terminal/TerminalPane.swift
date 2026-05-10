import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalPane: View {
  @ObservedObject var store: TerminalLogStore
  let labels: BundleLocalizationLabels
  let textDirection: LayoutDirection
  @State private var isShowingCopyFeedback = false
  @State private var copyFeedbackTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .font(.headline)
          .accessibilityLabel(labels.terminalCommandOutputLabel)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(store.tabs) { tab in
              TerminalTabButton(
                tab: tab,
                isSelected: store.selectedTabID == tab.id,
                close: { store.closeTab(tab.id) },
                select: { store.selectedTabID = tab.id }
              )
            }
          }
          .padding(.vertical, 2)
        }

        Spacer()

        Button {
          copySelectedTabText()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(labels.terminalCopyTextLabel)
        .accessibilityLabel(labels.terminalCopyTextLabel)

        if isShowingCopyFeedback {
          Text(labels.terminalCopiedTextLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .animation(.easeOut(duration: 0.15), value: isShowingCopyFeedback)

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          Text(store.selectedTab?.lines.joined(separator: "\n") ?? "")
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: terminalTextAlignment)
            .textSelection(.enabled)
            .padding(12)
            .environment(\.layoutDirection, textDirection)

          Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchorID)
        }
        .onChange(of: store.selectedTabID) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
        .onChange(of: store.selectedLineCount) { _, _ in
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
      }
      .background(.regularMaterial)
    }
    .onDisappear {
      copyFeedbackTask?.cancel()
    }
  }

  private static let bottomAnchorID = "terminal-bottom"

  private var terminalTextAlignment: Alignment {
    textDirection == .rightToLeft ? .trailing : .leading
  }

  private func copySelectedTabText() {
    let text = store.selectedTab?.lines.joined(separator: "\n") ?? ""
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif

    isShowingCopyFeedback = true
    copyFeedbackTask?.cancel()
    copyFeedbackTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(1600))
      guard !Task.isCancelled else { return }
      isShowingCopyFeedback = false
    }
  }
}
