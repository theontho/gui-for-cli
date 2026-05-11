package ui

import (
	"sort"
	"strings"

	"gioui.org/widget"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func (g *GioApp) editorFor(id string, value string) *widget.Editor {
	if existing, ok := g.textFields[id]; ok {
		return existing
	}
	editor := new(widget.Editor)
	editor.SingleLine = true
	editor.SetText(value)
	g.textFields[id] = editor
	return editor
}

func (g *GioApp) toggleFor(id string, value string) *widget.Bool {
	if existing, ok := g.toggles[id]; ok {
		return existing
	}
	toggle := new(widget.Bool)
	toggle.Value = strings.EqualFold(value, "true") || strings.EqualFold(value, "yes")
	g.toggles[id] = toggle
	return toggle
}

func (g *GioApp) dropdownFor(id string, options []bundle.Option, fallback string) *dropdownState {
	if existing, ok := g.dropdowns[id]; ok {
		if len(options) > 0 && !sameOptionIDs(existing.options, options) {
			existing.options = append([]bundle.Option(nil), options...)
			existing.index = selectedOptionIndex(existing.options, fallback)
		}
		return existing
	}
	state := &dropdownState{
		options: append([]bundle.Option(nil), options...),
		index:   selectedOptionIndex(options, fallback),
	}
	g.dropdowns[id] = state
	return state
}

func (g *GioApp) checkboxGroupFor(id string, options []bundle.Option) *checkboxGroupState {
	if existing, ok := g.checkboxGroups[id]; ok {
		if !sameOptionIDs(existing.options, options) {
			existing.options = append([]bundle.Option(nil), options...)
			for _, option := range existing.options {
				if existing.values[option.ID] == nil {
					existing.values[option.ID] = new(widget.Bool)
				}
			}
		}
		return existing
	}
	state := &checkboxGroupState{
		options: append([]bundle.Option(nil), options...),
		values:  map[string]*widget.Bool{},
	}
	persisted := selectedIDs(g.state.CheckedOptions[id])
	for _, option := range state.options {
		value := new(widget.Bool)
		if _, ok := persisted[option.ID]; ok {
			value.Value = true
		} else {
			value.Value = option.Selected
		}
		state.values[option.ID] = value
	}
	g.checkboxGroups[id] = state
	return state
}

func (g *GioApp) clickableForPage(id string) *widget.Clickable {
	if existing, ok := g.pageButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.pageButtons[id] = clickable
	return clickable
}

func (g *GioApp) clickableForAction(id string) *widget.Clickable {
	if existing, ok := g.actionButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.actionButtons[id] = clickable
	return clickable
}

func (g *GioApp) clickableForRowAction(id string) *widget.Clickable {
	if existing, ok := g.rowActionButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.rowActionButtons[id] = clickable
	return clickable
}

func (g *GioApp) configButton(buttons map[string]*widget.Clickable, id string) *widget.Clickable {
	if existing, ok := buttons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	buttons[id] = clickable
	return clickable
}

func (g *GioApp) pathPickerButtonFor(id string) *widget.Clickable {
	if existing, ok := g.pathPickerButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.pathPickerButtons[id] = clickable
	return clickable
}

func (g *GioApp) dataSourceRetryButtonFor(id string) *widget.Clickable {
	if existing, ok := g.dataSourceRetryButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.dataSourceRetryButtons[id] = clickable
	return clickable
}

func (g *GioApp) configPathEditorFor(control bundle.Control) *widget.Editor {
	if existing, ok := g.configPathFields[control.ID]; ok {
		return existing
	}
	editor := new(widget.Editor)
	editor.SingleLine = true
	editor.SetText(g.configPaths[control.ID])
	g.configPathFields[control.ID] = editor
	return editor
}

func selectedOptionIndex(options []bundle.Option, fallback string) int {
	for index, option := range options {
		if option.ID == fallback || option.Selected {
			return index
		}
	}
	return 0
}

func sameOptionIDs(left []bundle.Option, right []bundle.Option) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index].ID != right[index].ID || left[index].Title != right[index].Title {
			return false
		}
	}
	return true
}

func displayOption(option bundle.Option) string {
	title := option.Title
	if title == "" {
		title = option.ID
	}
	if option.Status != "" {
		title += " (" + option.Status + ")"
	}
	return title
}

func selectedIDs(values []string) map[string]struct{} {
	selected := map[string]struct{}{}
	for _, value := range values {
		for _, item := range strings.Split(value, ",") {
			item = strings.TrimSpace(item)
			if item != "" {
				selected[item] = struct{}{}
			}
		}
	}
	return selected
}

func sortedSelectedIDs(group *checkboxGroupState) []string {
	selected := make([]string, 0, len(group.values))
	for _, option := range group.options {
		if group.values[option.ID].Value {
			selected = append(selected, option.ID)
		}
	}
	sort.Strings(selected)
	return selected
}
