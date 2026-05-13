import GUIForCLICore
import SwiftUI

struct LeadingFormRow<Label: View, Content: View>: View {
  let label: Label
  let content: Content

  init(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
    self.label = label()
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      label
        .frame(width: 190, alignment: .leading)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
