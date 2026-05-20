import GUIForCLICore
import SwiftUI

struct ActionRow: View {
  let actions: [ActionSpec]
  let context: CommandRenderContext
  var runAction: (ActionSpec) -> Void

  var body: some View {
    let visibleActions = actions.filter { $0.isVisible(resolving: context) }
    let reserveEstimateSpace = visibleActions.contains { $0.estimatedDurationLabel != nil }
    if visibleActions.count == 1, let action = visibleActions.first {
      HStack(alignment: .top) {
        actionButton(action, reserveEstimateSpace: reserveEstimateSpace)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
      }
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
        ForEach(visibleActions) { action in
          actionButton(action, reserveEstimateSpace: reserveEstimateSpace)
        }
      }
    }
  }

  private func actionButton(_ action: ActionSpec, reserveEstimateSpace: Bool) -> some View {
    ActionButton(action: action, reserveEstimateSpace: reserveEstimateSpace) {
      runAction(action)
    }
    .environment(\.commandRenderContext, context)
  }
}
