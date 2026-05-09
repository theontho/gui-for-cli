import GUIForCLICore
import SwiftUI

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
    .accessibilityLabel(Text("Info"))
    .accessibilityHint(Text(text))
    .popover(isPresented: $isPresented, arrowEdge: .top) {
      InfoPopoverContent(text: text)
    }
  }
}
