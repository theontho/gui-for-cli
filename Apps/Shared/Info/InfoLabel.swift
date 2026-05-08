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
