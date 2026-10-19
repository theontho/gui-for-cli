import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalPane: View {
  let store: TerminalLogStore
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
                labels: labels,
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

      Group {
        if let tab = store.selectedTab {
          TerminalTextView(buffer: tab.output, textDirection: textDirection)
        } else {
          Color.clear
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial)
    }
    .onDisappear {
      copyFeedbackTask?.cancel()
    }
  }

  private func copySelectedTabText() {
    let text = store.selectedTab?.output.text ?? ""
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
