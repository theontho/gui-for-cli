package ui

import (
	"fmt"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
	gfc "github.com/theontho/gui-for-cli/apps/fyne/internal/runtime"
)

func (a *App) renderPage(page bundle.Page) fyne.CanvasObject {
	sections := []fyne.CanvasObject{}
	for _, section := range page.Sections {
		section := section
		title := widget.NewLabelWithStyle(iconPrefix(section.TextIcon)+section.Title, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
		subtitle := widget.NewLabel(section.Subtitle)
		subtitle.Wrapping = fyne.TextWrapWord
		children := []fyne.CanvasObject{title, subtitle}
		if err := a.model.DataErrors["section:"+section.ID]; err != "" {
			children = append(children, warningLabel(err))
		}
		for _, control := range section.Controls {
			children = append(children, a.renderControl(control))
		}
		children = append(children, a.renderActions(section.Actions, nil, "section:"+section.ID)...)
		sections = append(sections, widget.NewCard("", "", container.NewVBox(children...)))
	}
	if len(sections) == 0 {
		return widget.NewLabel("This bundle page has no sections.")
	}
	return container.NewVBox(sections...)
}

func (a *App) renderControl(control bundle.Control) fyne.CanvasObject {
	label := widget.NewLabelWithStyle(control.Label, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	var field fyne.CanvasObject
	switch control.Kind {
	case "text":
		field = a.textEntry(control.ID, a.model.State.FieldValues[control.ID], control.Placeholder, func(value string) {
			a.model.SetField(control.ID, value)
		})
	case "path":
		field = a.pathEntry(control.ID, a.model.State.FieldValues[control.ID], control)
	case "dropdown":
		field = a.dropdown(control.ID, control.Options, a.model.State.FieldValues[control.ID], func(value string) {
			a.model.SetField(control.ID, value)
		})
	case "toggle":
		check := widget.NewCheck(control.Label, func(value bool) {
			a.model.SetField(control.ID, fmt.Sprint(value))
		})
		check.SetChecked(a.model.State.FieldValues[control.ID] == "true")
		return container.NewVBox(check, helpLabel(control.Tooltip), dataErrorLabel(a.model.DataErrors["control:"+control.ID]))
	case "checkboxGroup":
		field = a.checkboxGroup(control)
	case "configEditor":
		field = a.configEditor(control)
	case "libraryList":
		field = a.libraryList(control)
	default:
		field = warningLabel("Unsupported control kind: " + control.Kind)
	}
	return container.NewVBox(label, field, helpLabel(control.Tooltip), dataErrorLabel(a.model.DataErrors["control:"+control.ID]))
}

func (a *App) textEntry(id string, value string, placeholder string, changed func(string)) *widget.Entry {
	entry := widget.NewEntry()
	entry.SetText(value)
	entry.PlaceHolder = placeholder
	entry.OnChanged = changed
	return entry
}

func (a *App) pathEntry(id string, value string, control bundle.Control) fyne.CanvasObject {
	entry := a.textEntry(id, value, control.Placeholder, func(value string) { a.model.SetField(id, value) })
	browse := widget.NewButton("Browse…", func() {
		a.showPathDialog(control, func(path string) {
			entry.SetText(path)
			a.model.SetField(id, path)
		})
	})
	return container.NewBorder(nil, nil, nil, browse, entry)
}

func (a *App) dropdown(id string, options []bundle.Option, selected string, changed func(string)) fyne.CanvasObject {
	labels := []string{}
	idByLabel := map[string]string{}
	selectedLabel := ""
	for _, option := range options {
		label := option.Title
		if option.Status != "" {
			label += " · " + option.Status
		}
		labels = append(labels, label)
		idByLabel[label] = option.ID
		if option.ID == selected {
			selectedLabel = label
		}
	}
	selectWidget := widget.NewSelect(labels, func(label string) {
		if idByLabel[label] != "" {
			changed(idByLabel[label])
		}
	})
	selectWidget.PlaceHolder = "Choose…"
	if selectedLabel != "" {
		selectWidget.SetSelected(selectedLabel)
	}
	if len(labels) == 0 {
		selectWidget.Disable()
	}
	return selectWidget
}

func (a *App) checkboxGroup(control bundle.Control) fyne.CanvasObject {
	selected := map[string]bool{}
	for _, id := range a.model.State.CheckedOptions[control.ID] {
		selected[id] = true
	}
	checks := []fyne.CanvasObject{}
	for _, option := range control.Options {
		option := option
		check := widget.NewCheck(option.Title, func(value bool) {
			a.model.SetChecked(control.ID, option.ID, value)
		})
		check.SetChecked(selected[option.ID])
		checks = append(checks, check)
	}
	if len(checks) == 0 {
		return widget.NewLabel("No choices available.")
	}
	return container.NewVBox(checks...)
}

func (a *App) configEditor(control bundle.Control) fyne.CanvasObject {
	path := a.model.State.ConfigFilePaths[control.ID]
	pathEntry := widget.NewEntry()
	pathEntry.SetText(path)
	pathEntry.OnChanged = func(value string) {
		a.model.State.ConfigFilePaths[control.ID] = a.model.ResolvePathTokens(value, "")
		_ = a.model.SaveState()
	}
	load := widget.NewButton("Load", func() {
		if err := a.model.LoadConfig(control); err != nil {
			a.showError(err)
			return
		}
		a.rebuild()
	})
	settings := []fyne.CanvasObject{widget.NewLabel("Settings file"), container.NewBorder(nil, nil, nil, load, pathEntry)}
	for _, setting := range control.Settings {
		settings = append(settings, a.renderSetting(control, setting))
	}
	return container.NewVBox(settings...)
}

func (a *App) renderSetting(control bundle.Control, setting bundle.ConfigSetting) fyne.CanvasObject {
	label := widget.NewLabelWithStyle(setting.Label, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	key := gfc.ConfigValueKey(control, setting)
	value := a.model.ConfigValues[key]
	var field fyne.CanvasObject
	switch setting.Kind {
	case "path":
		entry := widget.NewEntry()
		entry.PlaceHolder = setting.Placeholder
		entry.SetText(value)
		entry.OnChanged = func(next string) { a.model.SetConfig(control, setting, next) }
		browseControl := bundle.Control{ID: setting.ID, PathKind: setting.PathKind, PathType: setting.PathType, PathMode: setting.PathMode}
		browse := widget.NewButton("Browse…", func() {
			a.showPathDialog(browseControl, func(path string) {
				entry.SetText(path)
				a.model.SetConfig(control, setting, path)
			})
		})
		field = container.NewBorder(nil, nil, nil, browse, entry)
	case "dropdown":
		field = a.dropdown(setting.ID, setting.Options, value, func(next string) { a.model.SetConfig(control, setting, next) })
	case "toggle":
		check := widget.NewCheck(setting.Label, func(next bool) { a.model.SetConfig(control, setting, fmt.Sprint(next)) })
		check.SetChecked(value == "true")
		field = check
	default:
		field = a.textEntry(setting.ID, value, setting.Placeholder, func(next string) { a.model.SetConfig(control, setting, next) })
	}
	return container.NewVBox(label, field, helpLabel(setting.Tooltip), dataErrorLabel(a.model.DataErrors["setting:"+control.ID+"."+setting.ID]))
}

func (a *App) libraryList(control bundle.Control) fyne.CanvasObject {
	rows := gfc.HydrateRows(control)
	if len(rows) == 0 {
		return widget.NewLabel("No rows available. Use Refresh after installing or generating data.")
	}
	cards := []fyne.CanvasObject{}
	baseContext := a.model.Context(nil)
	for _, row := range rows {
		row := row
		values := []fyne.CanvasObject{}
		if row.Status != "" {
			values = append(values, widget.NewLabel("Status: "+row.Status))
		}
		for _, column := range control.Columns {
			if value := row.Values[column.ID]; value != "" {
				values = append(values, widget.NewLabel(column.Title+": "+value))
			}
		}
		if len(row.Tags) > 0 {
			values = append(values, widget.NewLabel("Tags: "+tagTitles(row.Tags)))
		}
		rowContext := gfc.RowContext(baseContext, row)
		actions := a.renderActionsWithContext(control.RowActions, row.Values, "row:"+control.ID+":"+row.ID, rowContext)
		values = append(values, actions...)
		cards = append(cards, widget.NewCard(row.Title, row.Tooltip, container.NewVBox(values...)))
	}
	return container.NewVBox(cards...)
}

func (a *App) showPathDialog(control bundle.Control, selected func(string)) {
	kind := strings.ToLower(firstNonEmpty(control.PathKind, control.PathType))
	if kind == "directory" || kind == "folder" {
		d := dialog.NewFolderOpen(func(uri fyne.ListableURI, err error) {
			if err != nil {
				a.showError(err)
				return
			}
			if uri != nil {
				selected(uri.Path())
			}
		}, a.window)
		d.Show()
		return
	}
	if strings.ToLower(control.PathMode) == "save" {
		d := dialog.NewFileSave(func(writer fyne.URIWriteCloser, err error) {
			if err != nil {
				a.showError(err)
				return
			}
			if writer != nil {
				path := writer.URI().Path()
				_ = writer.Close()
				selected(path)
			}
		}, a.window)
		d.Show()
		return
	}
	d := dialog.NewFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			a.showError(err)
			return
		}
		if reader != nil {
			path := reader.URI().Path()
			_ = reader.Close()
			selected(path)
		}
	}, a.window)
	d.Show()
}

func warningLabel(text string) fyne.CanvasObject {
	label := widget.NewLabel("⚠ " + text)
	label.Wrapping = fyne.TextWrapWord
	return label
}

func helpLabel(text string) fyne.CanvasObject {
	if strings.TrimSpace(text) == "" {
		return widget.NewLabel("")
	}
	label := widget.NewLabel(text)
	label.Wrapping = fyne.TextWrapWord
	return label
}

func dataErrorLabel(text string) fyne.CanvasObject {
	if strings.TrimSpace(text) == "" {
		return widget.NewLabel("")
	}
	return warningLabel(text)
}

func tagTitles(tags []bundle.Tag) string {
	values := []string{}
	for _, tag := range tags {
		values = append(values, tag.Title)
	}
	return strings.Join(values, ", ")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func friendlyPath(path string) string {
	if path == "" {
		return ""
	}
	return filepath.Clean(path)
}
