import SwiftUI

@main
struct GUIForCLIMacApp: App {
  @StateObject private var textScale = AppTextScale()

  var body: some Scene {
    WindowGroup {
      ContentView(platformName: "macOS")
        .frame(minWidth: 840, minHeight: 680)
        .dynamicTypeSize(textScale.dynamicTypeSize)
    }
    .commands {
      CommandGroup(after: .toolbar) {
        Divider()

        Button("Increase Text Size") {
          textScale.increase()
        }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(!textScale.canIncrease)

        Button("Decrease Text Size") {
          textScale.decrease()
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(!textScale.canDecrease)

        Divider()

        Button("Reset Text Size") {
          textScale.reset()
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(!textScale.canReset)
      }
    }
  }
}
