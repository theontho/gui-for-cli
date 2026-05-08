import GUIForCLICore
import SwiftUI

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
