import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ContentView: View {
  let platformName: String

  @State private var manifest: CLIBundleManifest
  @State private var selectedPageID: String?
  @State private var fieldValues: [String: String]
  @State private var checkedOptions: [String: Set<String>]
  @State private var bundleRootURL: URL?
  @State private var isImportingBundle = false
  @StateObject private var terminal = TerminalLogStore()

  init(
    platformName: String,
    manifest: CLIBundleManifest = DemoBundle.wgsExtract,
    bundleRootURL: URL? = DemoBundle.wgsExtractResourceRootURL
  ) {
    self.platformName = platformName
    _manifest = State(initialValue: manifest)
    _selectedPageID = State(initialValue: manifest.pages.first?.id)
    _fieldValues = State(initialValue: manifest.initialFieldValues)
    _checkedOptions = State(initialValue: manifest.initialCheckedOptions)
    _bundleRootURL = State(initialValue: bundleRootURL)
  }

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        BundleHeader(manifest: manifest, rootURL: bundleRootURL)
          .padding(.horizontal)
          .padding(.top, 14)
          .padding(.bottom, 10)

        List(selection: $selectedPageID) {
          ForEach(manifest.pages) { page in
            Label(page.title, systemImage: "doc.text")
              .tag(page.id)
          }
        }
      }
      .navigationTitle("Pages")
    } detail: {
      VStack(spacing: 0) {
        PageRenderer(
          page: selectedPage,
          fieldValues: $fieldValues,
          checkedOptions: $checkedOptions,
          runAction: { action in
            terminal.start(title: action.title, command: action.command.displayCommand)
          }
        )

        Divider()

        TerminalPane(store: terminal)
      }
      .navigationTitle(selectedPage.title)
      .toolbar {
        ToolbarItemGroup {
          Button {
            isImportingBundle = true
          } label: {
            Label("Import Bundle", systemImage: "square.and.arrow.down")
          }

          Button {
            runSetup()
          } label: {
            Label("Setup", systemImage: "checkmark.shield")
          }

          Button {
            terminal.appendToMain("Settings selected for \(platformName).")
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
        }
      }
    }
    .fileImporter(
      isPresented: $isImportingBundle,
      allowedContentTypes: Self.importableBundleTypes,
      allowsMultipleSelection: false
    ) { result in
      importBundle(from: result)
    }
  }

  private var selectedPage: BundlePage {
    manifest.pages.first { $0.id == selectedPageID } ?? manifest.pages[0]
  }

  private static var importableBundleTypes: [UTType] {
    [
      .folder,
      .item,
      UTType(filenameExtension: "json"),
      UTType(filenameExtension: "zip"),
      UTType(filenameExtension: "tar"),
      UTType(filenameExtension: "tgz"),
      UTType(filenameExtension: "gz"),
    ].compactMap { $0 }
  }

  private func importBundle(from result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else {
        terminal.appendToMain("[import] No bundle selected.")
        return
      }

      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let loaded = try BundleSourceLoader().load(from: url)
      manifest = loaded.manifest
      bundleRootURL = loaded.rootURL
      selectedPageID = loaded.manifest.pages[0].id
      fieldValues = loaded.manifest.initialFieldValues
      checkedOptions = loaded.manifest.initialCheckedOptions
      terminal.replaceMain([
        "[import] Loaded bundle: \(loaded.manifest.displayName)",
        "[import] Manifest: \(loaded.manifestURL.path)",
        "[import] Pages: \(loaded.manifest.pages.map(\.title).joined(separator: ", "))",
      ])
    } catch {
      terminal.appendToMain("[import:error] \(error.localizedDescription)")
    }
  }

  private func runSetup() {
    guard let bundleRootURL else {
      terminal.replaceMain([
        "[setup] Import a bundle folder or archive to run setup scripts.",
        "[setup] The built-in demo manifest is loaded without a writable bundle root.",
      ])
      return
    }

    do {
      let commands = try SetupCommandPlanner().plan(for: manifest, rootURL: bundleRootURL)
      terminal.startSetup(commands)
    } catch {
      terminal.appendToMain("[setup:error] \(error.localizedDescription)")
    }
  }
}

#Preview {
  ContentView(platformName: "Preview")
}

private struct BundleHeader: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?

  var body: some View {
    VStack(spacing: 10) {
      if manifest.sidebarIconStyle != .hidden {
        BundleIconView(manifest: manifest, rootURL: rootURL, size: 72)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(manifest.displayName)
          .font(.headline.weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .center)
        Text(manifest.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .help(manifest.summary)
      }
    }
  }
}

private struct BundleIconView: View {
  let manifest: CLIBundleManifest
  let rootURL: URL?
  var size: CGFloat = 34

  var body: some View {
    iconContent
      .frame(width: size, height: size)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22))
  }

  @ViewBuilder private var iconContent: some View {
    switch manifest.sidebarIconStyle {
    case .automatic:
      if let image = bundleImage {
        imageIcon(image)
      } else if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .image:
      if let image = bundleImage {
        imageIcon(image)
      } else {
        symbolIcon
      }
    case .emoji:
      if let emoji = nonEmptyEmoji {
        emojiIcon(emoji)
      } else {
        symbolIcon
      }
    case .symbol, .hidden:
      symbolIcon
    }
  }

  private func imageIcon(_ image: Image) -> some View {
    image
      .resizable()
      .scaledToFit()
  }

  private func emojiIcon(_ emoji: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )
      Text(emoji)
        .font(.system(size: size * 0.54))
    }
  }

  private var symbolIcon: some View {
    Image(systemName: manifest.iconName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(.tint)
      .padding(size * 0.2)
  }

  private var bundleImage: Image? {
    guard let rootURL, let iconPath = manifest.iconPath, !iconPath.isEmpty else {
      return nil
    }
    let url = rootURL.appendingPathComponent(iconPath, isDirectory: false)
    #if os(macOS)
      guard let image = NSImage(contentsOf: url) else { return nil }
      return Image(nsImage: image)
    #else
      guard let image = UIImage(contentsOfFile: url.path) else { return nil }
      return Image(uiImage: image)
    #endif
  }

  private var nonEmptyEmoji: String? {
    guard let emoji = manifest.iconEmoji, !emoji.isEmpty else {
      return nil
    }
    return emoji
  }
}

private struct PageRenderer: View {
  let page: BundlePage
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  var runAction: (ActionSpec) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text(page.title)
            .font(.largeTitle.weight(.semibold))
          Text(page.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(page.summary)
        }

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            fieldValues: $fieldValues,
            checkedOptions: $checkedOptions,
            runAction: runAction
          )
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
  }
}

private struct SectionRenderer: View {
  let section: PageSection
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  var runAction: (ActionSpec) -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        if let subtitle = section.subtitle {
          Text(subtitle)
            .foregroundStyle(.secondary)
            .help(subtitle)
        }

        ForEach(section.controls) { control in
          ControlRenderer(
            control: control,
            value: binding(for: control),
            checkedIDs: checkedBinding(for: control)
          )
        }

        if !section.actions.isEmpty {
          Divider()
          ActionRow(actions: section.actions, runAction: runAction)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      if let title = section.title {
        Label(title, systemImage: "rectangle.3.group")
      }
    }
  }

  private func binding(for control: ControlSpec) -> Binding<String> {
    Binding(
      get: { fieldValues[control.id, default: control.value ?? ""] },
      set: { fieldValues[control.id] = $0 }
    )
  }

  private func checkedBinding(for control: ControlSpec) -> Binding<Set<String>> {
    Binding(
      get: {
        checkedOptions[control.id, default: Set(control.options.filter(\.selected).map(\.id))]
      },
      set: { checkedOptions[control.id] = $0 }
    )
  }
}

private struct ControlRenderer: View {
  let control: ControlSpec
  @Binding var value: String
  @Binding var checkedIDs: Set<String>

  var body: some View {
    switch control.kind {
    case .text:
      labeledControl {
        TextField(control.placeholder ?? "", text: $value)
      }
    case .path:
      labeledControl {
        HStack {
          TextField(control.placeholder ?? "", text: $value)
          Button("Choose...") {}
        }
      }
    case .dropdown:
      labeledControl {
        Picker("", selection: $value) {
          ForEach(control.options) { option in
            Text(option.title).tag(option.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
    case .toggle:
      labeledControl {
        Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
          .labelsHidden()
      }
    case .checkboxGroup:
      VStack(alignment: .leading, spacing: 10) {
        label
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], spacing: 8) {
          ForEach(control.options) { option in
            Toggle(
              option.title,
              isOn: Binding(
                get: { checkedIDs.contains(option.id) },
                set: { isSelected in
                  if isSelected {
                    checkedIDs.insert(option.id)
                  } else {
                    checkedIDs.remove(option.id)
                  }
                }
              )
            )
            #if os(macOS)
              .toggleStyle(.checkbox)
            #endif
          }
        }
      }
      .help(control.tooltip ?? "")
    case .infoGrid:
      VStack(alignment: .leading, spacing: 10) {
        label
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .leading)], spacing: 8) {
          ForEach(control.options) { option in
            Text(option.title)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
      .help(control.tooltip ?? "")
    }
  }

  private var label: some View {
    HStack(spacing: 6) {
      Text(control.label)
        .font(.headline)
      if let tooltip = control.tooltip {
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .help(tooltip)
      }
    }
  }

  private func labeledControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    LabeledContent {
      content()
        .frame(maxWidth: .infinity)
    } label: {
      label
    }
    .help(control.tooltip ?? "")
  }
}

private struct ActionRow: View {
  let actions: [ActionSpec]
  var runAction: (ActionSpec) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], spacing: 10) {
      ForEach(actions) { action in
        ActionButton(action: action) {
          runAction(action)
        }
      }
    }
  }
}

private struct ActionButton: View {
  let action: ActionSpec
  var run: () -> Void

  var body: some View {
    Button(role: action.role == .destructive ? .destructive : nil, action: run) {
      Text(action.title)
        .frame(maxWidth: .infinity)
    }
    .controlSize(.regular)
    .help(action.tooltip ?? action.command.displayCommand)
  }
}

private struct TerminalPane: View {
  @ObservedObject var store: TerminalLogStore

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Label("Command Output", systemImage: "terminal")
          .font(.headline)

        Picker("Tab", selection: $store.selectedTabID) {
          ForEach(store.tabs) { tab in
            Text(tab.title).tag(Optional(tab.id))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220)

        Spacer()

        Button {
          store.closeSelectedTab()
        } label: {
          Label("Close or Clear", systemImage: "xmark.circle")
        }
        .disabled(store.tabs.isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      ScrollView {
        Text(store.selectedTab?.lines.joined(separator: "\n") ?? "")
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(12)
      }
      .background(.regularMaterial)
    }
    .frame(height: 240)
  }
}

@MainActor
private final class TerminalLogStore: ObservableObject {
  @Published var tabs: [TerminalTab] = [
    TerminalTab(
      title: "Main", command: "main",
      lines: [
        "[08:00:00] GUI for CLI started.",
        "[08:00:00] Loaded sample bundle: WGS Extract.",
        "[08:00:00] Bundle setup can check PATH tools, bundled scripts, and Homebrew packages.",
      ])
  ]
  @Published var selectedTabID: UUID?

  private var tasks: [UUID: Task<Void, Never>] = [:]

  init() {
    selectedTabID = tabs.first?.id
  }

  var selectedTab: TerminalTab? {
    tabs.first { $0.id == selectedTabID }
  }

  func appendToMain(_ line: String) {
    guard let mainID = tabs.first?.id else { return }
    append(line, to: mainID)
  }

  func replaceMain(_ lines: [String]) {
    guard !tabs.isEmpty else { return }
    tabs[0].lines = lines
    selectedTabID = tabs[0].id
  }

  func start(title: String, command: String) {
    let tab = TerminalTab(
      title: title, command: command,
      lines: [
        "$ \(command)",
        "[queued] Preparing command environment...",
      ])
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.simulateRun(tabID: tab.id, command: command)
    }
  }

  func startSetup(_ commands: [SetupCommand]) {
    guard !commands.isEmpty else {
      appendToMain("[setup] Bundle has no setup steps.")
      return
    }

    let tab = TerminalTab(
      title: "Setup",
      command: "bundle setup",
      lines: commands.flatMap { command in
        [
          "==> \(command.label)",
          "$ \(command.displayCommand)",
        ]
      }
    )
    tabs.append(tab)
    selectedTabID = tab.id

    tasks[tab.id] = Task { @MainActor [weak self] in
      await self?.runSetup(tabID: tab.id, commands: commands)
    }
  }

  func closeSelectedTab() {
    guard let selectedTabID else { return }
    if tabs.first?.id == selectedTabID {
      tabs[0].lines.removeAll()
      tabs[0].lines.append("[cleared] Main log cleared.")
      return
    }

    tasks[selectedTabID]?.cancel()
    tasks[selectedTabID] = nil
    tabs.removeAll { $0.id == selectedTabID }
    self.selectedTabID = tabs.first?.id
  }

  private func simulateRun(tabID: UUID, command: String) async {
    do {
      try await Task.sleep(for: .milliseconds(250))
      append("[running] \(command)", to: tabID)
      try await Task.sleep(for: .milliseconds(350))
      append("[stdout] This starter currently simulates CLI execution.", to: tabID)
      append(
        "[stdout] Wire CommandSpec to Process on macOS when bundle execution is enabled.", to: tabID
      )
      try await Task.sleep(for: .milliseconds(250))
      append("[done] exit code 0", to: tabID)
    } catch {
      append("[cancelled] \(command)", to: tabID)
    }
    tasks[tabID] = nil
  }

  private func runSetup(tabID: UUID, commands: [SetupCommand]) async {
    let runner = SetupCommandRunner()
    for command in commands {
      if Task.isCancelled {
        append("[cancelled] setup stopped", to: tabID)
        break
      }

      do {
        let result = try await Task.detached {
          try runner.run(command)
        }.value
        if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          append(result.output.trimmingCharacters(in: .newlines), to: tabID)
        }
        if result.exitStatus != 0 {
          append("[exit \(result.exitStatus)] \(command.label)", to: tabID)
          if !command.optional { break }
        } else {
          append("[ok] \(command.label)", to: tabID)
        }
      } catch {
        append("[error] \(command.label): \(error.localizedDescription)", to: tabID)
        if !command.optional { break }
      }
    }
    tasks[tabID] = nil
  }

  private func append(_ line: String, to tabID: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
    tabs[index].lines.append(line)
  }
}

private struct TerminalTab: Identifiable {
  let id = UUID()
  var title: String
  var command: String
  var lines: [String]
}

private extension CLIBundleManifest {
  var initialFieldValues: [String: String] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .reduce(into: [:]) { values, control in
        values[control.id] = control.value ?? values[control.id] ?? ""
      }
  }

  var initialCheckedOptions: [String: Set<String>] {
    pages
      .flatMap(\.sections)
      .flatMap(\.controls)
      .filter { $0.kind == .checkboxGroup }
      .reduce(into: [:]) { values, control in
        values[control.id] = Set(control.options.filter(\.selected).map(\.id))
      }
  }
}
