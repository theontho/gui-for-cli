import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

extension ContentView {
  @ViewBuilder var rootContent: some View {
    #if os(macOS)
      if localizationLabels.layoutDirection == .rightToLeft {
        rightSidebarContent
      } else {
        navigationSplitContent
      }
    #else
      navigationSplitContent
    #endif
  }

  var navigationSplitContent: some View {
    NavigationSplitView {
      sidebarContent(opaqueBackground: false)
        .environment(\.layoutDirection, swiftUILayoutDirection)
        .navigationTitle("Pages")
    } detail: {
      detailContent
        .onAppear(perform: flushStartupMessages)
        .navigationTitle(AppVersion.windowTitle(selectedPage.title))
    }
  }

  func flushStartupMessages() {
    let messages = startupMessages
    guard !messages.isEmpty else { return }
    startupMessages.removeAll()
    for message in messages {
      terminal.appendToMain(message)
    }
  }

  #if os(macOS)
    var rightSidebarContent: some View {
      ZStack(alignment: .topTrailing) {
        HStack(spacing: 0) {
          detailContent
            .onAppear(perform: flushStartupMessages)
            .frame(minWidth: Self.minimumDetailWidth, maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, swiftUILayoutDirection)

          if isRTLSidebarVisible {
            rightSidebarDivider
            rightSidebarPane
          }
        }

        if !isRTLSidebarVisible {
          rtlSidebarToggleButton(
            title: localizationLabels.sidebarShowLabel,
            systemImage: "chevron.left",
            action: { isRTLSidebarVisible = true }
          )
          .padding(12)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background)
    }

    var rightSidebarPane: some View {
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        sidebarContent(opaqueBackground: true)
      }
      .overlay(alignment: .topLeading) {
        rtlSidebarToggleButton(
          title: localizationLabels.sidebarHideLabel,
          systemImage: "chevron.right",
          action: { isRTLSidebarVisible = false }
        )
        .padding(10)
      }
      .frame(width: Self.clampedSidebarWidth(rtlSidebarWidth))
      .frame(maxHeight: .infinity)
      .clipped()
      .environment(\.layoutDirection, swiftUILayoutDirection)
    }

    func rtlSidebarToggleButton(
      title: String,
      systemImage: String,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        Image(systemName: systemImage)
          .frame(width: 26, height: 26)
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .help(title)
      .accessibilityLabel(title)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    var rightSidebarDivider: some View {
      ZStack {
        Color.clear
        Rectangle()
          .fill(Color(nsColor: .separatorColor))
          .frame(width: 1)
      }
      .frame(width: 8)
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let startWidth = rtlSidebarDragStartWidth ?? rtlSidebarWidth
            rtlSidebarDragStartWidth = startWidth
            rtlSidebarWidth = Self.clampedSidebarWidth(startWidth - value.translation.width)
          }
          .onEnded { value in
            let startWidth = rtlSidebarDragStartWidth ?? rtlSidebarWidth
            rtlSidebarWidth = Self.clampedSidebarWidth(startWidth - value.translation.width)
            rtlSidebarDragStartWidth = nil
          }
      )
      .onHover { isHovering in
        if isHovering {
          NSCursor.resizeLeftRight.push()
        } else {
          NSCursor.pop()
        }
      }
    }
  #endif
}
