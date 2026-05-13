import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

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
