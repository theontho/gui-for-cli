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
          copySelectedOutput()
        } label: {
          Label(labels.terminalCopyOutputLabel, systemImage: "doc.on.doc")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(selectedOutput.isEmpty)
        .accessibilityLabel(labels.terminalCopyOutputLabel)
        .help(labels.terminalCopyOutputLabel)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

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
  }

  private static let bottomAnchorID = "terminal-bottom"

  private var terminalTextAlignment: Alignment {
    textDirection == .rightToLeft ? .trailing : .leading
  }

  private var selectedOutput: String {
    store.selectedTab?.lines.joined(separator: "\n") ?? ""
  }

  private func copySelectedOutput() {
    let output = selectedOutput
    guard !output.isEmpty else { return }
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(output, forType: .string)
    #else
      UIPasteboard.general.string = output
    #endif
  }
}
