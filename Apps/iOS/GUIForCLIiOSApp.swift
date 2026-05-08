import SwiftUI

@main
struct GUIForCLIiOSApp: App {
  @StateObject private var textScale = AppTextScale()

  var body: some Scene {
    WindowGroup {
      ContentView(platformName: "iOS")
        .dynamicTypeSize(textScale.dynamicTypeSize)
    }
  }
}
