import GUIForCLICore
import SwiftUI

struct InitialConfigValues {
  var values: [String: String]
  var messages: [String]
}

struct ConfigSettingBinding {
  var control: ControlSpec
  var setting: ConfigSettingSpec
}

struct SidebarPageGroup: Identifiable {
  let id: String
  let title: String?
  var pages: [BundlePage]

  static func groups(for pages: [BundlePage]) -> [SidebarPageGroup] {
    pages.reduce(into: []) { groups, page in
      let groupTitle = normalizedGroupTitle(page.sidebarGroup)
      if let lastIndex = groups.indices.last, groups[lastIndex].title == groupTitle {
        groups[lastIndex].pages.append(page)
      } else {
        let groupID = "\(groups.count)-\(groupTitle ?? "ungrouped")"
        groups.append(SidebarPageGroup(id: groupID, title: groupTitle, pages: [page]))
      }
    }
  }

  private static func normalizedGroupTitle(_ title: String?) -> String? {
    guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
      return nil
    }
    return title
  }
}
@MainActor
final class AppTextScale: ObservableObject {
  private static let defaultsKey = "appTextScaleStep"
  private static let minimumStep = -3
  private static let maximumStep = 5

  @Published private(set) var step: Int {
    didSet {
      UserDefaults.standard.set(step, forKey: Self.defaultsKey)
    }
  }

  init() {
    step = UserDefaults.standard.integer(forKey: Self.defaultsKey)
    step = Self.clamped(step)
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch step {
    case ...(-3):
      return .xSmall
    case -2:
      return .small
    case -1:
      return .medium
    case 0:
      return .large
    case 1:
      return .xLarge
    case 2:
      return .xxLarge
    case 3:
      return .xxxLarge
    case 4:
      return .accessibility1
    default:
      return .accessibility2
    }
  }

  var canIncrease: Bool { step < Self.maximumStep }
  var canDecrease: Bool { step > Self.minimumStep }
  var canReset: Bool { step != 0 }

  func increase() {
    step = Self.clamped(step + 1)
  }

  func decrease() {
    step = Self.clamped(step - 1)
  }

  func reset() {
    step = 0
  }

  private static func clamped(_ step: Int) -> Int {
    min(max(step, minimumStep), maximumStep)
  }
}
#if os(macOS)
  struct NativeTerminalSplitView<TopContent: View, BottomContent: View>: NSViewRepresentable {
    let topContent: TopContent
    let bottomContent: BottomContent
    let initialBottomFraction: CGFloat
    let minimumTopHeight: CGFloat
    let minimumBottomHeight: CGFloat

    func makeCoordinator() -> Coordinator {
      Coordinator(
        initialBottomFraction: initialBottomFraction,
        minimumTopHeight: minimumTopHeight,
        minimumBottomHeight: minimumBottomHeight)
    }

    func makeNSView(context: Context) -> NSSplitView {
      let splitView = NSSplitView()
      splitView.isVertical = false
      splitView.dividerStyle = .thin

      let bottomHostingView = NSHostingView(rootView: bottomContent)
      let topHostingView = NSHostingView(rootView: topContent)
      context.coordinator.bottomHostingView = bottomHostingView
      context.coordinator.topHostingView = topHostingView

      splitView.addArrangedSubview(topHostingView)
      splitView.addArrangedSubview(bottomHostingView)
      context.coordinator.scheduleInitialPosition(in: splitView)
      return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
      context.coordinator.bottomHostingView?.rootView = bottomContent
      context.coordinator.topHostingView?.rootView = topContent
      context.coordinator.scheduleInitialPosition(in: splitView)
    }

    @MainActor final class Coordinator: NSObject {
      var topHostingView: NSHostingView<TopContent>?
      var bottomHostingView: NSHostingView<BottomContent>?

      private let initialBottomFraction: CGFloat
      private let minimumTopHeight: CGFloat
      private let minimumBottomHeight: CGFloat
      private var didSetInitialPosition = false

      init(
        initialBottomFraction: CGFloat,
        minimumTopHeight: CGFloat,
        minimumBottomHeight: CGFloat
      ) {
        self.initialBottomFraction = initialBottomFraction
        self.minimumTopHeight = minimumTopHeight
        self.minimumBottomHeight = minimumBottomHeight
      }

      func scheduleInitialPosition(in splitView: NSSplitView) {
        guard !didSetInitialPosition else { return }
        Task { @MainActor [weak self, weak splitView] in
          guard let self, let splitView else { return }
          self.applyInitialPosition(in: splitView)
        }
      }

      private func applyInitialPosition(in splitView: NSSplitView) {
        guard splitView.bounds.height > 0 else {
          scheduleInitialPosition(in: splitView)
          return
        }
        let maximumBottomHeight = max(
          minimumBottomHeight,
          splitView.bounds.height - minimumTopHeight - splitView.dividerThickness)
        let bottomHeight = min(
          max(splitView.bounds.height * initialBottomFraction, minimumBottomHeight),
          maximumBottomHeight)
        let topHeight = splitView.bounds.height - bottomHeight - splitView.dividerThickness
        splitView.setPosition(topHeight, ofDividerAt: 0)
        didSetInitialPosition = true
      }
    }
  }
#endif
