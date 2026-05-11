import AppKit
import GUIForCLICore

extension AppKitPageViewController {
  func controlView(_ control: ControlSpec) -> NSView {
    switch control.kind {
    case .text:
      return labeledControl(control) {
        let field = NSTextField(string: state.value(for: control))
        field.placeholderString = control.placeholder
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        field.identifier = NSUserInterfaceItemIdentifier(control.id)
        field.setAccessibilityLabel(control.label)
        return field
      }
    case .path:
      return pathControlView(control)
    case .dropdown:
      return dropdownControlView(control)
    case .toggle:
      return labeledControl(control) {
        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(control.id)
        toggle.state = state.value(for: control) == "true" ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        return toggle
      }
    case .checkboxGroup:
      return checkboxGroupView(control)
    case .infoGrid:
      return infoGridView(control)
    case .libraryList:
      return libraryListView(control)
    case .configEditor:
      return configEditorView(control)
    }
  }

  func labeledControl(_ control: ControlSpec, build: () -> NSView) -> NSView {
    let row = AppKitViewFactory.horizontalStack(spacing: 12)
    let label = AppKitViewFactory.titleLabel(control.label, size: bodyFontSize, weight: .medium)
    label.widthAnchor.constraint(equalToConstant: 180).isActive = true
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    let content = build()
    content.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(label)
    row.addArrangedSubview(content)
    if let tooltip = control.tooltip {
      row.toolTip = tooltip
    }
    row.setAccessibilityLabel(control.label)
    return row
  }

  func configEditorView(_ control: ControlSpec) -> NSView {
    let stack = AppKitViewFactory.verticalStack(spacing: 12)
    stack.addArrangedSubview(
      AppKitViewFactory.titleLabel(control.label, size: bodyFontSize, weight: .medium))
    if let configURL = state.resolvedConfigURL(for: control) {
      stack.addArrangedSubview(
        AppKitViewFactory.secondaryLabel(
          "\(labels.settingsFileLabel): \(configURL.path)", size: bodyFontSize - 1))
    }

    for setting in control.settings {
      stack.addArrangedSubview(settingControl(setting, in: control))
    }

    let actions = AppKitViewFactory.horizontalStack()
    let load = NSButton(
      title: labels.loadButtonTitle, target: self, action: #selector(loadConfig(_:)))
    load.identifier = NSUserInterfaceItemIdentifier(control.id)
    let save = NSButton(title: "Save", target: self, action: #selector(saveConfig(_:)))
    save.identifier = NSUserInterfaceItemIdentifier(control.id)
    actions.addArrangedSubview(load)
    actions.addArrangedSubview(save)
    stack.addArrangedSubview(actions)
    return stack
  }

  func settingControl(_ setting: ConfigSettingSpec, in control: ControlSpec) -> NSView {
    let row = AppKitViewFactory.horizontalStack(spacing: 12)
    let label = AppKitViewFactory.titleLabel(setting.label, size: bodyFontSize, weight: .regular)
    label.widthAnchor.constraint(equalToConstant: 180).isActive = true
    row.addArrangedSubview(label)

    switch setting.kind {
    case .dropdown:
      let popup = NSPopUpButton()
      popup.identifier = NSUserInterfaceItemIdentifier("\(control.id)\u{1f}\(setting.id)")
      popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
      for option in setting.options {
        popup.addItem(withTitle: displayTitle(for: option))
        popup.lastItem?.representedObject = option.id
      }
      let current = state.configSettingValue(for: setting, in: control)
      if let index = setting.options.firstIndex(where: { $0.id == current }) {
        popup.selectItem(at: index)
      }
      popup.target = self
      popup.action = #selector(settingDropdownChanged(_:))
      row.addArrangedSubview(popup)
    case .toggle:
      let toggle = NSSwitch()
      toggle.identifier = NSUserInterfaceItemIdentifier("\(control.id)\u{1f}\(setting.id)")
      toggle.state = state.configSettingValue(for: setting, in: control) == "true" ? .on : .off
      toggle.target = self
      toggle.action = #selector(settingToggleChanged(_:))
      row.addArrangedSubview(toggle)
    default:
      let field = NSTextField(string: state.configSettingValue(for: setting, in: control))
      field.placeholderString = setting.placeholder
      field.identifier = NSUserInterfaceItemIdentifier("\(control.id)\u{1f}\(setting.id)")
      field.target = self
      field.action = #selector(settingTextCommitted(_:))
      field.setAccessibilityLabel(setting.label)
      row.addArrangedSubview(field)
      field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
    }

    return row
  }

  func libraryListView(_ control: ControlSpec) -> NSView {
    let stack = AppKitViewFactory.verticalStack(spacing: 10)
    stack.addArrangedSubview(
      AppKitViewFactory.titleLabel(control.label, size: bodyFontSize, weight: .medium))
    let rows = control.hydratedRows
    if rows.isEmpty, control.dataSource != nil, loadingIDs.contains(control.id) {
      stack.addArrangedSubview(
        AppKitViewFactory.secondaryLabel(labels.loadingTitle, size: bodyFontSize))
      return stack
    }
    for row in rows {
      let rowBox = AppKitViewFactory.verticalStack(spacing: 6)
      rowBox.addArrangedSubview(
        AppKitViewFactory.titleLabel(row.title ?? row.id, size: bodyFontSize, weight: .medium))
      for column in control.columns {
        if let value = row.values[column.id]?.nonEmpty {
          rowBox.addArrangedSubview(
            AppKitViewFactory.secondaryLabel("\(column.title): \(value)", size: bodyFontSize - 1))
        }
      }
      if !control.rowActions.isEmpty {
        rowBox.addArrangedSubview(
          actionRow(control.rowActions, context: commandContext(rowValues: row.values)))
      }
      stack.addArrangedSubview(AppKitViewFactory.boxed(title: nil, content: rowBox))
    }
    return stack
  }

  private func pathControlView(_ control: ControlSpec) -> NSView {
    labeledControl(control) {
      let row = AppKitViewFactory.horizontalStack()
      let field = NSTextField(string: state.value(for: control))
      field.placeholderString = control.placeholder
      field.target = self
      field.action = #selector(textFieldCommitted(_:))
      field.identifier = NSUserInterfaceItemIdentifier(control.id)
      field.setAccessibilityLabel(control.label)
      let button = NSButton(
        title: labels.chooseButtonTitle, target: self, action: #selector(choosePath(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(control.id)
      button.setAccessibilityLabel("\(labels.chooseButtonTitle) \(control.label)")
      row.addArrangedSubview(field)
      row.addArrangedSubview(button)
      field.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
      button.setContentHuggingPriority(.required, for: .horizontal)
      return row
    }
  }

  private func dropdownControlView(_ control: ControlSpec) -> NSView {
    labeledControl(control) {
      let popup = NSPopUpButton()
      popup.identifier = NSUserInterfaceItemIdentifier(control.id)
      popup.setAccessibilityLabel(control.label)
      popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
      for option in control.options {
        popup.addItem(withTitle: displayTitle(for: option))
        popup.lastItem?.representedObject = option.id
      }
      if let index = control.options.firstIndex(where: { $0.id == state.value(for: control) }) {
        popup.selectItem(at: index)
      }
      popup.target = self
      popup.action = #selector(dropdownChanged(_:))
      return popup
    }
  }

  private func checkboxGroupView(_ control: ControlSpec) -> NSView {
    let stack = AppKitViewFactory.verticalStack(spacing: 8)
    stack.addArrangedSubview(
      AppKitViewFactory.titleLabel(control.label, size: bodyFontSize, weight: .medium))
    let selected = state.selectedOptions(for: control)
    for option in control.options {
      let button = NSButton(
        checkboxWithTitle: displayTitle(for: option), target: self,
        action: #selector(checkboxChanged(_:)))
      button.identifier = NSUserInterfaceItemIdentifier("\(control.id)\u{1f}\(option.id)")
      button.setAccessibilityLabel("\(control.label): \(displayTitle(for: option))")
      button.state = selected.contains(option.id) ? .on : .off
      stack.addArrangedSubview(button)
    }
    return stack
  }

  private func infoGridView(_ control: ControlSpec) -> NSView {
    let stack = AppKitViewFactory.verticalStack(spacing: 8)
    stack.addArrangedSubview(
      AppKitViewFactory.titleLabel(control.label, size: bodyFontSize, weight: .medium))
    for option in control.options {
      stack.addArrangedSubview(
        AppKitViewFactory.secondaryLabel(displayTitle(for: option), size: bodyFontSize))
    }
    return stack
  }
}
