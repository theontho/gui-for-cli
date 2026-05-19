import GUIForCLICore
import SwiftUI

extension ContentView {
  static let initialTerminalHeightFraction: CGFloat = 0.20
  static let minimumTerminalHeight: CGFloat = 96
  static let minimumPageHeight: CGFloat = 260

  @ViewBuilder var detailContent: some View {
    #if os(macOS)
      ZStack(alignment: .bottomTrailing) {
        if isTerminalVisible {
          NativeTerminalSplitView(
            topContent: pageContentWithSetupBar,
            bottomContent: TerminalPane(
              store: terminal,
              labels: localizationLabels,
              textDirection: terminalTextLayoutDirection),
            initialBottomFraction: Self.initialTerminalHeightFraction,
            minimumTopHeight: Self.minimumPageHeight,
            minimumBottomHeight: Self.minimumTerminalHeight
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          VStack(spacing: 0) {
            pageContentWithSetupBar
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        terminalVisibilityButton
          .padding(.trailing, 16)
          .padding(.bottom, 12)
      }
    #else
      ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
          pageContentWithSetupBar

          if isTerminalVisible {
            Divider()
            TerminalPane(
              store: terminal,
              labels: localizationLabels,
              textDirection: terminalTextLayoutDirection
            )
            .frame(height: 240)
          }
        }

        terminalVisibilityButton
          .padding(.trailing, 16)
          .padding(.bottom, 12)
      }
    #endif
  }

  var terminalVisibilityButton: some View {
    let title =
      isTerminalVisible
      ? localizationLabels.terminalHideOutputLabel
      : localizationLabels.terminalShowOutputLabel
    return Button {
      isTerminalVisible.toggle()
    } label: {
      Label(title, systemImage: "rectangle.bottomthird.inset.filled")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityLabel(title)
    .help(title)
  }

  var pageContent: some View {
    PageRenderer(
      page: selectedPage,
      localizationLabels: localizationLabels,
      bundleRootURL: bundleRootURL,
      runAction: { action, context in
        let command = action.command.renderedCommand(resolving: context)
        terminal.start(
          title: action.title,
          command: command,
          workingDirectory: bundleRootURL,
          inputSummary: ActionInputSummary.describe(context, command: action.command))
      },
      headerAccessory: settingsStandardOptionsAccessory
    )
    .environment(\.layoutDirection, swiftUILayoutDirection)
  }

  @ViewBuilder var pageContentWithSetupBar: some View {
    VStack(spacing: 0) {
      if shouldShowGlobalSetupStatusBar {
        SetupGlobalStatusBar(
          labels: localizationLabels,
          setupRun: activeSetupRun,
          isRunning: isSetupRunning,
          action: { goToSetupAndStart() })
      }
      pageContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  var selectedPage: BundlePage {
    manifest.pages.first { $0.id == selectedPageID } ?? manifest.pages[0]
  }

  var swiftUILayoutDirection: LayoutDirection {
    localizationLabels.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
  }

  var terminalTextLayoutDirection: LayoutDirection {
    manifest.terminalTextDirection == .rightToLeft ? .rightToLeft : .leftToRight
  }
}
