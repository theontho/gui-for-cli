import GUIForCLICore
import SwiftUI

struct ActionRow: View {
  let actions: [ActionSpec]
  let context: CommandRenderContext
  var runAction: (ActionSpec) -> Void

  var body: some View {
    let visibleActions = actions.filter { $0.isVisible(resolving: context) }
    if visibleActions.count == 1, let action = visibleActions.first {
      HStack {
        actionButton(action)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
      }
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
        ForEach(visibleActions) { action in
          actionButton(action)
            .frame(maxHeight: .infinity, alignment: .top)
        }
      }
    }
  }

  private func actionButton(_ action: ActionSpec) -> some View {
    ActionButton(action: action) {
      runAction(action)
    }
    .environment(\.commandRenderContext, context)
  }
}
