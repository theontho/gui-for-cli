import SwiftUI

@main
struct GUIForCLIMacApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView(platformName: "macOS")
        .frame(minWidth: 1080, minHeight: 760)
    }
  }
}
