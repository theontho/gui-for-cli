import GUIForCLICore
import SwiftUI

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
