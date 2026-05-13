import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct TerminalTabButton: View {
  var tab: TerminalTab
  var isSelected: Bool
  var close: () -> Void
  var select: () -> Void
  @State private var showsStatusExplanation = false

  var body: some View {
    HStack(spacing: 4) {
      Button {
        select()
        if tab.status != nil {
          showsStatusExplanation = true
        }
      } label: {
        HStack(spacing: 4) {
          if tab.isRunning {
            ProgressView()
              .controlSize(.small)
          } else if let status = tab.status {
            Image(systemName: status.symbolName)
              .foregroundStyle(status.tint)
              .accessibilityLabel(status.accessibilityLabel)
          }
          Text(tab.title)
            .lineLimit(1)
        }
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showsStatusExplanation, arrowEdge: .bottom) {
        if let status = tab.status {
          VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: status.symbolName)
              .font(.headline)
              .foregroundStyle(status.tint)
            Text(status.blurb)
              .font(.callout)
              .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(status.detail)
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(14)
          .frame(width: 320, alignment: .leading)
        }
      }

      if !tab.isMain {
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.caption2.weight(.semibold))
            .padding(3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.isRunning ? "Cancel \(tab.title)" : "Close \(tab.title)")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(backgroundColor)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .strokeBorder(borderColor, lineWidth: tab.status == nil ? 0 : 1)
    }
  }

  private var backgroundColor: Color {
    if let status = tab.status {
      return status.tint.opacity(isSelected ? 0.28 : 0.16)
    }
    return isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
  }

  private var borderColor: Color {
    tab.status?.tint.opacity(isSelected ? 0.65 : 0.35) ?? .clear
  }
}
