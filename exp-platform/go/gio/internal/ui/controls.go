package ui

import (
	"fmt"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func (g *GioApp) layoutControls(gtx layout.Context, controls []bundle.Control) layout.Dimensions {
	children := make([]layout.FlexChild, 0, len(controls)*2)
	for _, control := range controls {
		control := control
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutControl(gtx, control)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(10)}.Layout(gtx)
			}),
		)
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutControl(gtx layout.Context, control bundle.Control) layout.Dimensions {
	switch control.Kind {
	case "text", "path":
		editor := g.editorFor(control.ID, g.controlValue(control))
		if control.Kind == "path" {
			return g.layoutPathEditor(gtx, pathPickerSpec{
				ID:          control.ID,
				Label:       control.Label,
				Key:         control.ID,
				Tooltip:     control.Tooltip,
				PathType:    control.PathType,
				PathKind:    control.PathKind,
				PathMode:    control.PathMode,
				ButtonID:    "control:" + control.ID,
				InitialPath: editor.Text(),
				OnChoose: func(path string) {
					editor.SetText(path)
					g.persistFormState()
				},
			}, editor, control.Placeholder)
		}
		return g.layoutEditorWithChange(gtx, control.Label, editor, control.Placeholder, g.persistFormState)
	case "dropdown":
		return g.layoutDropdownWithChange(gtx, control.Label, control.ID, control.Options, g.controlValue(control), g.persistFormState)
	case "toggle":
		return g.layoutToggleWithChange(gtx, control.Label, g.toggleFor(control.ID, g.controlValue(control)), g.persistFormState)
	case "checkboxGroup":
		return g.layoutCheckboxGroup(gtx, control)
	case "infoGrid":
		return g.layoutInfoGrid(gtx, control)
	case "libraryList":
		return g.layoutLibraryList(gtx, control)
	case "configEditor":
		return g.layoutConfigEditor(gtx, control)
	default:
		return warningText(g.theme, fmt.Sprintf("%s (%s): unsupported control kind", control.Label, control.Kind)).Layout(gtx)
	}
}

func (g *GioApp) layoutEditor(gtx layout.Context, label string, editor *widget.Editor, hint string) layout.Dimensions {
	return g.layoutEditorWithChange(gtx, label, editor, hint, nil)
}

func (g *GioApp) layoutEditorWithChange(gtx layout.Context, label string, editor *widget.Editor, hint string, onChange func()) layout.Dimensions {
	changed := false
	for {
		event, ok := editor.Update(gtx)
		if !ok {
			break
		}
		if _, ok := event.(widget.ChangeEvent); ok {
			changed = true
		}
	}
	if changed && onChange != nil {
		onChange()
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Editor(g.theme, editor, hint).Layout(gtx)
		}),
	)
}

func (g *GioApp) layoutDropdown(gtx layout.Context, label string, id string, options []bundle.Option, fallback string) layout.Dimensions {
	return g.layoutDropdownWithChange(gtx, label, id, options, fallback, g.persistFormState)
}

func (g *GioApp) layoutDropdownWithChange(gtx layout.Context, label string, id string, options []bundle.Option, fallback string, onChange func()) layout.Dimensions {
	state := g.dropdownFor(id, options, fallback)
	for state.button.Clicked(gtx) {
		if len(state.options) > 0 {
			state.index = (state.index + 1) % len(state.options)
			if onChange != nil {
				onChange()
			}
		}
	}

	value := fallback
	if len(state.options) > 0 {
		value = displayOption(state.options[state.index])
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if strings.TrimSpace(value) == "" {
				value = g.stringLabel("app.control.chooseValue", "Choose value")
			}
			return material.Button(g.theme, &state.button, value).Layout(gtx)
		}),
	)
}

func (g *GioApp) layoutToggleWithChange(gtx layout.Context, label string, toggle *widget.Bool, onChange func()) layout.Dimensions {
	if toggle.Update(gtx) && onChange != nil {
		onChange()
	}
	return material.CheckBox(g.theme, toggle, label).Layout(gtx)
}

func (g *GioApp) layoutCheckboxGroup(gtx layout.Context, control bundle.Control) layout.Dimensions {
	group := g.checkboxGroupFor(control.ID, control.Options)
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, control.Label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
	}
	currentGroup := ""
	for _, option := range group.options {
		option := option
		if option.Group != "" && option.Group != currentGroup {
			currentGroup = option.Group
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return mutedText(g.theme, currentGroup).Layout(gtx)
			}))
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.CheckBox(g.theme, group.values[option.ID], displayOption(option)).Layout(gtx)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutInfoGrid(gtx layout.Context, control bundle.Control) layout.Dimensions {
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, control.Label).Layout(gtx)
		}),
	}
	for _, option := range control.Options {
		option := option
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return mutedText(g.theme, "• "+displayOption(option)).Layout(gtx)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutConfigEditor(gtx layout.Context, control bundle.Control) layout.Dimensions {
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			title := control.Label
			if title == "" {
				title = g.settingsTitle()
			}
			return material.Body1(g.theme, title).Layout(gtx)
		}),
	}
	if control.ConfigFile != nil {
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutConfigFileControls(gtx, control)
			}),
		)
	}
	for _, setting := range control.Settings {
		setting := setting
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				value := g.configValue(control, setting)
				switch setting.Kind {
				case "dropdown":
					return g.layoutDropdownWithChange(gtx, setting.Label, setting.ID, setting.Options, value, func() {
						g.autoSaveConfig(control)
					})
				case "toggle":
					return g.layoutToggleWithChange(gtx, setting.Label, g.toggleFor(setting.ID, value), func() {
						g.autoSaveConfig(control)
					})
				case "path":
					editor := g.editorFor(setting.ID, value)
					return g.layoutPathEditor(gtx, pathPickerSpec{
						ID:          setting.ID,
						Label:       setting.Label,
						Key:         setting.Key,
						Tooltip:     setting.Tooltip,
						PathType:    setting.PathType,
						PathKind:    setting.PathKind,
						PathMode:    setting.PathMode,
						ButtonID:    "setting:" + control.ID + ":" + setting.ID,
						InitialPath: editor.Text(),
						OnChoose: func(path string) {
							editor.SetText(path)
							g.autoSaveConfig(control)
						},
						OnChange: func() {
							g.autoSaveConfig(control)
						},
					}, editor, setting.Placeholder)
				default:
					return g.layoutEditorWithChange(gtx, setting.Label, g.editorFor(setting.ID, value), setting.Placeholder, func() {
						g.autoSaveConfig(control)
					})
				}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				key := "setting:" + control.ID + "." + setting.ID
				if errText := g.dataSourceErrors[key]; errText != "" {
					return g.layoutDataSourceError(gtx, key, errText)
				}
				return layout.Dimensions{}
			}),
		)
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutConfigFileControls(gtx layout.Context, control bundle.Control) layout.Dimensions {
	loadButton := g.configButton(g.configLoadButtons, control.ID)
	for loadButton.Clicked(gtx) {
		if err := g.loadConfig(control); err != nil {
			g.appendLog(g.stringFormat("app.config.loadError.format", "Could not load %{label}: %{error}", map[string]string{
				"label": control.Label,
				"error": err.Error(),
			}))
		}
	}
	editor := g.configPathEditorFor(control)
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body2(g.theme, g.stringLabel("app.settingsFile.label", "Settings File")).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutPathInputRow(gtx, pathPickerSpec{
				ID:          control.ID,
				Label:       control.Label,
				Key:         "configFile",
				Tooltip:     control.Tooltip,
				PathType:    "file",
				ButtonID:    "config-file:" + control.ID,
				InitialPath: editor.Text(),
				OnChoose: func(path string) {
					editor.SetText(path)
					if err := g.loadConfig(control); err != nil {
						g.appendLog(g.stringFormat("app.config.loadError.format", "Could not load %{label}: %{error}", map[string]string{
							"label": control.Label,
							"error": err.Error(),
						}))
					}
				},
				OnChange: func() {
					g.configPaths[control.ID] = editor.Text()
					g.state.ConfigFilePaths[control.ID] = editor.Text()
					g.saveState()
				},
			}, editor, "")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(
				gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return material.Button(g.theme, loadButton, g.stringLabel("app.loadButton.title", "Load")).Layout(gtx)
				}),
			)
		}),
	)
}
