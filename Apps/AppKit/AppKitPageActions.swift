import AppKit
import GUIForCLICore

extension AppKitPageViewController {
  func actionRow(_ actions: [ActionSpec], context: CommandRenderContext) -> NSView {
    let row = AppKitViewFactory.horizontalStack()
    for action in actions where action.isVisible(resolving: context) {
      let displayCommand = action.command.displayCommand(resolving: context)
      let missing = action.command.missingPlaceholders(resolving: context)
      let disabledReason = action.disabledReason(resolving: context)
      let button = AppKitActionButton(
        title: action.iconOnly ? "" : action.title,
        target: self,
        action: #selector(actionButtonPressed(_:)))
      button.invocation = AppKitActionInvocation(action: action, context: context)
      if action.iconOnly {
        button.image = NSImage(
          systemSymbolName: action.iconName ?? "play.fill",
          accessibilityDescription: action.title)
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
      }
      button.toolTip = actionHelp(
        action: action,
        context: context,
        missingPlaceholders: missing,
        disabledReason: disabledReason,
        displayCommand: displayCommand)
      button.setAccessibilityLabel(action.title)
      button.isEnabled =
        missing.isEmpty && disabledReason == nil
        && !terminal.isCommandRunning(displayCommand)
      if action.role == .destructive {
        button.hasDestructiveAction = true
      }
      row.addArrangedSubview(button)
    }
    return row
  }

  func actionHelp(
    action: ActionSpec,
    context: CommandRenderContext,
    missingPlaceholders: [String],
    disabledReason: String?,
    displayCommand: String
  ) -> String {
    let base = action.tooltip ?? displayCommand
    if !missingPlaceholders.isEmpty {
      let missing = missingPlaceholders.map {
        context.label(for: $0) ?? Self.placeholderLabel($0)
      }.joined(separator: ", ")
      return "\(base)\n\nMissing: \(missing)"
    }
    if let disabledReason {
      return "\(base)\n\n\(disabledReason)"
    }
    return base
  }

  @objc func textFieldCommitted(_ sender: NSTextField) {
    guard let control = control(with: sender.identifier?.rawValue) else { return }
    state.setValue(sender.stringValue, for: control)
  }

  @objc func dropdownChanged(_ sender: NSPopUpButton) {
    guard let control = control(with: sender.identifier?.rawValue),
      let value = sender.selectedItem?.representedObject as? String
    else { return }
    state.setValue(value, for: control)
  }

  @objc func toggleChanged(_ sender: NSSwitch) {
    guard let control = control(with: sender.identifier?.rawValue) else { return }
    state.setValue(sender.state == .on ? "true" : "false", for: control)
  }

  @objc func checkboxChanged(_ sender: NSButton) {
    guard let parts = sender.identifier?.rawValue.split(separator: "\u{1f}").map(String.init),
      parts.count == 2,
      let control = control(with: parts[0])
    else { return }
    var selected = state.selectedOptions(for: control)
    if sender.state == .on {
      selected.insert(parts[1])
    } else {
      selected.remove(parts[1])
    }
    state.setSelectedOptions(selected, for: control)
  }

  @objc func choosePath(_ sender: NSButton) {
    guard let control = control(with: sender.identifier?.rawValue) else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = initialDirectoryURL(for: state.value(for: control))
    if panel.runModal() == .OK, let url = panel.url {
      state.setValue(url.path, for: control)
      renderPage()
    }
  }

  @objc func settingTextCommitted(_ sender: NSTextField) {
    updateSetting(sender.identifier?.rawValue, value: sender.stringValue)
  }

  @objc func settingDropdownChanged(_ sender: NSPopUpButton) {
    updateSetting(
      sender.identifier?.rawValue, value: sender.selectedItem?.representedObject as? String ?? "")
  }

  @objc func settingToggleChanged(_ sender: NSSwitch) {
    updateSetting(sender.identifier?.rawValue, value: sender.state == .on ? "true" : "false")
  }

  @objc func loadConfig(_ sender: NSButton) {
    guard let control = control(with: sender.identifier?.rawValue) else { return }
    state.loadConfig(control)
    renderPage()
  }

  @objc func saveConfig(_ sender: NSButton) {
    guard let control = control(with: sender.identifier?.rawValue) else { return }
    state.saveConfig(control)
  }

  @objc func actionButtonPressed(_ sender: NSButton) {
    guard let invocation = (sender as? AppKitActionButton)?.invocation else { return }
    if let confirmation = invocation.action.confirm,
      !confirm(confirmation, context: invocation.context)
    {
      return
    }
    let command = invocation.action.command.renderedCommand(resolving: invocation.context)
    terminal.start(
      title: invocation.action.title, command: command, workingDirectory: state.bundleRootURL)
  }

  @objc func runSetup() {
    do {
      let commands = try SetupCommandPlanner().plan(
        for: state.manifest, rootURL: state.bundleRootURL)
      terminal.startSetup(commands) { [weak self] setupRun in
        self?.state.persistSetupRun(setupRun)
        self?.renderPage()
      }
    } catch {
      terminal.appendToMain("[setup:error] \(error.localizedDescription)")
    }
  }

  @objc func openBundleWorkspace() {
    NSWorkspace.shared.open(state.bundleRootURL)
  }

  func updateSetting(_ rawID: String?, value: String) {
    guard let parts = rawID?.split(separator: "\u{1f}").map(String.init),
      parts.count == 2,
      let control = control(with: parts[0]),
      let setting = control.settings.first(where: { $0.id == parts[1] })
    else { return }
    state.setConfigSettingValue(value, for: setting, in: control)
  }

  func confirm(_ confirmation: ActionConfirmationSpec, context: CommandRenderContext) -> Bool {
    let alert = NSAlert()
    alert.messageText = context.interpolated(confirmation.title)
    alert.informativeText = confirmation.message.map(context.interpolated) ?? ""
    alert.addButton(withTitle: confirmation.confirmButtonTitle)
    alert.addButton(withTitle: confirmation.cancelButtonTitle)
    return alert.runModal() == .alertFirstButtonReturn
  }

  func control(with id: String?) -> ControlSpec? {
    guard let id else { return nil }
    return page.sections.flatMap(\.controls).first { $0.id == id }
  }

  private static func placeholderLabel(_ placeholder: String) -> String {
    placeholder
      .replacingOccurrences(of: "row.", with: "")
      .replacingOccurrences(of: "config.", with: "")
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
  }

  private func initialDirectoryURL(for rawPath: String) -> URL? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let expanded = (trimmed as NSString).expandingTildeInPath
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
      let url = URL(fileURLWithPath: expanded)
      return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
    let parent = URL(fileURLWithPath: expanded).deletingLastPathComponent()
    return FileManager.default.fileExists(atPath: parent.path) ? parent : nil
  }
}
