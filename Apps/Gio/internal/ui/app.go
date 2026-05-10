package ui

import (
	"bufio"
	"fmt"
	"image/color"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

var placeholderPattern = regexp.MustCompile(`\{\{([^{}]+)\}\}`)

type GioApp struct {
	window *app.Window
	theme  *material.Theme
	bundle *bundle.AppBundle

	startedAt         time.Time
	firstFramePrinted bool

	sidebarList layout.List
	contentList layout.List
	logEditor   widget.Editor

	pageButtons    map[string]*widget.Clickable
	actionButtons  map[string]*widget.Clickable
	dropdowns      map[string]*dropdownState
	textFields     map[string]*widget.Editor
	toggles        map[string]*widget.Bool
	checkboxGroups map[string]*checkboxGroupState

	activePageID string
	status       string
	logLines     []string

	logMu     sync.Mutex
	logEvents chan string
}

type dropdownState struct {
	button  widget.Clickable
	options []bundle.Option
	index   int
}

type checkboxGroupState struct {
	options []bundle.Option
	values  map[string]*widget.Bool
}

func Run(window *app.Window, loadedBundle *bundle.AppBundle, startedAt time.Time) error {
	ui := newApp(window, loadedBundle, startedAt)
	var ops op.Ops

	for {
		switch event := window.Event().(type) {
		case app.DestroyEvent:
			return event.Err
		case app.FrameEvent:
			ui.drainLogs()
			gtx := app.NewContext(&ops, event)
			ui.layout(gtx)
			event.Frame(gtx.Ops)
			if !ui.firstFramePrinted {
				ui.printMetric("firstFrameRendered")
				ui.firstFramePrinted = true
			}
		}
	}
}

func newApp(window *app.Window, loadedBundle *bundle.AppBundle, startedAt time.Time) *GioApp {
	th := material.NewTheme()
	th.Palette.ContrastBg = color.NRGBA{R: 36, G: 99, B: 235, A: 255}

	ui := &GioApp{
		window:         window,
		theme:          th,
		bundle:         loadedBundle,
		startedAt:      startedAt,
		sidebarList:    layout.List{Axis: layout.Vertical},
		contentList:    layout.List{Axis: layout.Vertical},
		pageButtons:    map[string]*widget.Clickable{},
		actionButtons:  map[string]*widget.Clickable{},
		dropdowns:      map[string]*dropdownState{},
		textFields:     map[string]*widget.Editor{},
		toggles:        map[string]*widget.Bool{},
		checkboxGroups: map[string]*checkboxGroupState{},
		logEvents:      make(chan string, 512),
	}
	ui.logEditor.ReadOnly = true
	ui.logEditor.SingleLine = false
	ui.logLines = []string{fmt.Sprintf("Loaded bundle %q from %s", loadedBundle.Manifest.DisplayName, loadedBundle.BundleRoot)}
	ui.status = "Ready"

	if len(loadedBundle.Manifest.Pages) > 0 {
		ui.activePageID = loadedBundle.Manifest.Pages[0].ID
	}

	ui.seedState()
	return ui
}

func (g *GioApp) layout(gtx layout.Context) layout.Dimensions {
	inset := layout.UniformInset(unit.Dp(16))
	return inset.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal}.Layout(
			gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Max.X = min(gtx.Constraints.Max.X, gtx.Dp(280))
				return g.layoutSidebar(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Width: unit.Dp(16)}.Layout(gtx)
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return g.layoutContent(gtx)
			}),
		)
	})
}

func (g *GioApp) layoutSidebar(gtx layout.Context) layout.Dimensions {
	items := g.bundle.Manifest.Pages
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			title := material.H5(g.theme, g.bundle.Manifest.DisplayName)
			title.Color = color.NRGBA{A: 255}
			return title.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			summary := material.Body1(g.theme, g.bundle.Manifest.Summary)
			return summary.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(16)}.Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return g.sidebarList.Layout(gtx, len(items), func(gtx layout.Context, index int) layout.Dimensions {
				page := items[index]
				clickable := g.clickableForPage(page.ID)
				for clickable.Clicked(gtx) {
					g.activePageID = page.ID
				}

				label := page.Title
				if page.SidebarGroup != "" {
					label = fmt.Sprintf("%s — %s", page.SidebarGroup, page.Title)
				}
				if page.ID == g.activePageID {
					label = "● " + label
				}

				return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return material.Button(g.theme, clickable, label).Layout(gtx)
				})
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(16)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			label := material.Caption(g.theme, g.status)
			label.Color = color.NRGBA{R: 80, G: 80, B: 80, A: 255}
			return label.Layout(gtx)
		}),
	)
}

func (g *GioApp) layoutContent(gtx layout.Context) layout.Dimensions {
	page := g.activePage()
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			title := material.H4(g.theme, page.Title)
			return title.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			summary := material.Body1(g.theme, page.Summary)
			return summary.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(16)}.Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			items := len(page.Sections) + 1
			return g.contentList.Layout(gtx, items, func(gtx layout.Context, index int) layout.Dimensions {
				if index == len(page.Sections) {
					return g.layoutLogs(gtx)
				}
				return g.layoutSection(gtx, page.Sections[index])
			})
		}),
	)
}

func (g *GioApp) layoutSection(gtx layout.Context, section bundle.Section) layout.Dimensions {
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(
			gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				title := material.H6(g.theme, section.Title)
				return title.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if strings.TrimSpace(section.Subtitle) == "" {
					return layout.Dimensions{}
				}
				return layout.UniformInset(unit.Dp(2)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					label := material.Body2(g.theme, section.Subtitle)
					label.Color = color.NRGBA{R: 96, G: 96, B: 96, A: 255}
					return label.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutControls(gtx, section.Controls)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutActions(gtx, section.Actions)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(20)}.Layout(gtx)
			}),
		)
	})
}

func (g *GioApp) layoutControls(gtx layout.Context, controls []bundle.Control) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, g.controlChildren(controls)...)
}

func (g *GioApp) controlChildren(controls []bundle.Control) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, len(controls))
	for _, control := range controls {
		control := control
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutControl(gtx, control)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
		)
	}
	return children
}

func (g *GioApp) layoutControl(gtx layout.Context, control bundle.Control) layout.Dimensions {
	switch control.Kind {
	case "text", "path":
		return g.layoutEditor(gtx, control.Label, g.editorFor(control.ID, control.Value), control.Placeholder)
	case "dropdown":
		return g.layoutDropdown(gtx, control.Label, control.ID, control.Options, control.Value)
	case "toggle":
		return material.CheckBox(g.theme, g.toggleFor(control.ID, control.Value), control.Label).Layout(gtx)
	case "checkboxGroup":
		return g.layoutCheckboxGroup(gtx, control)
	case "configEditor":
		return g.layoutConfigEditor(gtx, control)
	default:
		message := material.Body2(g.theme, fmt.Sprintf("%s (%s): unsupported in Gio benchmark shell", control.Label, control.Kind))
		message.Color = color.NRGBA{R: 128, G: 64, B: 0, A: 255}
		return message.Layout(gtx)
	}
}

func (g *GioApp) layoutEditor(gtx layout.Context, label string, editor *widget.Editor, hint string) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			style := material.Editor(g.theme, editor, hint)
			return style.Layout(gtx)
		}),
	)
}

func (g *GioApp) layoutDropdown(gtx layout.Context, label string, id string, options []bundle.Option, fallback string) layout.Dimensions {
	state := g.dropdownFor(id, options, fallback)
	for state.button.Clicked(gtx) {
		if len(state.options) == 0 {
			continue
		}
		state.index = (state.index + 1) % len(state.options)
	}

	value := fallback
	if len(state.options) > 0 {
		value = state.options[state.index].Title
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
			buttonLabel := "Choose value"
			if strings.TrimSpace(value) != "" {
				buttonLabel = value
			}
			return material.Button(g.theme, &state.button, buttonLabel).Layout(gtx)
		}),
	)
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
	for _, option := range group.options {
		option := option
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.CheckBox(g.theme, group.values[option.ID], option.Title).Layout(gtx)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutConfigEditor(gtx layout.Context, control bundle.Control) layout.Dimensions {
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			title := control.Label
			if title == "" {
				title = "Settings"
			}
			return material.Body1(g.theme, title).Layout(gtx)
		}),
	}
	for _, setting := range control.Settings {
		setting := setting
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				switch setting.Kind {
				case "dropdown":
					return g.layoutDropdown(gtx, setting.Label, setting.ID, setting.Options, setting.Value)
				case "toggle":
					return material.CheckBox(g.theme, g.toggleFor(setting.ID, setting.Value), setting.Label).Layout(gtx)
				default:
					return g.layoutEditor(gtx, setting.Label, g.editorFor(setting.ID, setting.Value), setting.Placeholder)
				}
			}),
		)
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutActions(gtx layout.Context, actions []bundle.Action) layout.Dimensions {
	if len(actions) == 0 {
		return layout.Dimensions{}
	}
	children := make([]layout.FlexChild, 0, len(actions))
	for _, action := range actions {
		action := action
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutAction(gtx, action)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
			}),
		)
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutAction(gtx layout.Context, action bundle.Action) layout.Dimensions {
	button := g.clickableForAction(action.ID)
	for button.Clicked(gtx) {
		g.runAction(action)
	}

	missing := g.missingRequiredValues(action.Command)
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, button, action.Title).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			note := action.Tooltip
			if len(missing) > 0 {
				note = fmt.Sprintf("Missing inputs: %s", strings.Join(missing, ", "))
			}
			if strings.TrimSpace(note) == "" {
				return layout.Dimensions{}
			}
			return layout.UniformInset(unit.Dp(2)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				body := material.Body2(g.theme, note)
				body.Color = color.NRGBA{R: 96, G: 96, B: 96, A: 255}
				return body.Layout(gtx)
			})
		}),
	)
}

func (g *GioApp) layoutLogs(gtx layout.Context) layout.Dimensions {
	g.logEditor.SetText(strings.Join(g.logLines, "\n"))
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.H6(g.theme, "Command Output").Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			editor := material.Editor(g.theme, &g.logEditor, "")
			return editor.Layout(gtx)
		}),
	)
}

func (g *GioApp) seedState() {
	for _, page := range g.bundle.Manifest.Pages {
		for _, section := range page.Sections {
			for _, control := range section.Controls {
				g.seedControl(control)
			}
		}
	}
}

func (g *GioApp) seedControl(control bundle.Control) {
	switch control.Kind {
	case "text", "path":
		g.editorFor(control.ID, control.Value)
	case "dropdown":
		g.dropdownFor(control.ID, control.Options, control.Value)
	case "toggle":
		g.toggleFor(control.ID, control.Value)
	case "checkboxGroup":
		g.checkboxGroupFor(control.ID, control.Options)
	case "configEditor":
		for _, setting := range control.Settings {
			switch setting.Kind {
			case "dropdown":
				g.dropdownFor(setting.ID, setting.Options, setting.Value)
			case "toggle":
				g.toggleFor(setting.ID, setting.Value)
			default:
				g.editorFor(setting.ID, setting.Value)
			}
		}
	}
}

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
		return existing
	}
	state := &dropdownState{options: append([]bundle.Option(nil), options...)}
	for index, option := range state.options {
		if option.Selected || option.ID == fallback {
			state.index = index
			break
		}
	}
	g.dropdowns[id] = state
	return state
}

func (g *GioApp) checkboxGroupFor(id string, options []bundle.Option) *checkboxGroupState {
	if existing, ok := g.checkboxGroups[id]; ok {
		return existing
	}
	state := &checkboxGroupState{
		options: append([]bundle.Option(nil), options...),
		values:  map[string]*widget.Bool{},
	}
	for _, option := range state.options {
		value := new(widget.Bool)
		value.Value = option.Selected
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

func (g *GioApp) activePage() bundle.Page {
	for _, page := range g.bundle.Manifest.Pages {
		if page.ID == g.activePageID {
			return page
		}
	}
	if len(g.bundle.Manifest.Pages) == 0 {
		return bundle.Page{Title: "No Pages"}
	}
	return g.bundle.Manifest.Pages[0]
}

func (g *GioApp) runAction(action bundle.Action) {
	executable, arguments, missing := g.renderCommand(action.Command)
	if len(missing) > 0 {
		g.status = "Action blocked"
		g.appendLog(fmt.Sprintf("Skipped %s: missing %s", action.Title, strings.Join(missing, ", ")))
		return
	}

	commandLine := strings.Join(append([]string{executable}, arguments...), " ")
	g.status = fmt.Sprintf("Running %s", action.Title)
	g.appendLog(fmt.Sprintf("> %s", commandLine))

	go func() {
		command := exec.Command(executable, arguments...)
		command.Dir = g.bundle.BundleRoot
		if runtime.GOOS == "windows" && strings.HasSuffix(strings.ToLower(executable), ".sh") {
			if bashPath, err := exec.LookPath("bash"); err == nil {
				command = exec.Command(bashPath, append([]string{executable}, arguments...)...)
				command.Dir = g.bundle.BundleRoot
			}
		}

		stdout, err := command.StdoutPipe()
		if err != nil {
			g.appendLog(fmt.Sprintf("Could not capture stdout: %v", err))
			return
		}
		stderr, err := command.StderrPipe()
		if err != nil {
			g.appendLog(fmt.Sprintf("Could not capture stderr: %v", err))
			return
		}

		if err := command.Start(); err != nil {
			g.appendLog(fmt.Sprintf("Command start failed: %v", err))
			g.status = "Command failed"
			g.window.Invalidate()
			return
		}

		var wg sync.WaitGroup
		wg.Add(2)
		go g.streamPipe(stdout, &wg)
		go g.streamPipe(stderr, &wg)
		wg.Wait()

		if err := command.Wait(); err != nil {
			g.appendLog(fmt.Sprintf("Command failed: %v", err))
			g.status = "Command failed"
		} else {
			g.appendLog("Command completed successfully.")
			g.status = "Ready"
		}
		g.window.Invalidate()
	}()
}

func (g *GioApp) streamPipe(pipe interface{ Read([]byte) (int, error) }, wg *sync.WaitGroup) {
	defer wg.Done()
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		g.appendLog(scanner.Text())
	}
}

func (g *GioApp) renderCommand(command bundle.Command) (string, []string, []string) {
	context := g.contextValues()
	missing := missingPlaceholders([]string{command.Executable}, context)
	if len(missing) > 0 {
		return "", nil, missing
	}

	argsMissing := missingPlaceholders(command.Arguments, context)
	if len(argsMissing) > 0 {
		return "", nil, argsMissing
	}

	renderedArgs := interpolateAll(command.Arguments, context)
	for _, optionalGroup := range command.OptionalArguments {
		if len(missingPlaceholders(optionalGroup, context)) == 0 {
			renderedArgs = append(renderedArgs, interpolateAll(optionalGroup, context)...)
		}
	}

	return interpolate(command.Executable, context), renderedArgs, nil
}

func (g *GioApp) missingRequiredValues(command bundle.Command) []string {
	context := g.contextValues()
	placeholders := append(extractPlaceholders(command.Executable), extractPlaceholders(strings.Join(command.Arguments, "\n"))...)
	unique := map[string]struct{}{}
	missing := make([]string, 0, len(placeholders))
	for _, placeholder := range placeholders {
		if _, seen := unique[placeholder]; seen {
			continue
		}
		unique[placeholder] = struct{}{}
		if strings.TrimSpace(context[placeholder]) == "" {
			missing = append(missing, placeholder)
		}
	}
	sort.Strings(missing)
	return missing
}

func (g *GioApp) contextValues() map[string]string {
	values := map[string]string{
		"bundleRoot":      g.bundle.BundleRoot,
		"bundleWorkspace": g.bundle.BundleWorkspaceRoot,
		"home":            userHomeDir(),
	}
	for key, editor := range g.textFields {
		values[key] = editor.Text()
	}
	for key, dropdown := range g.dropdowns {
		if len(dropdown.options) == 0 {
			continue
		}
		values[key] = dropdown.options[dropdown.index].ID
	}
	for key, toggle := range g.toggles {
		if toggle.Value {
			values[key] = "true"
		} else {
			values[key] = "false"
		}
	}
	for key, group := range g.checkboxGroups {
		selected := make([]string, 0, len(group.values))
		for _, option := range group.options {
			if group.values[option.ID].Value {
				selected = append(selected, option.ID)
			}
		}
		sort.Strings(selected)
		values[key] = strings.Join(selected, ",")
	}
	return values
}

func (g *GioApp) appendLog(line string) {
	g.logMu.Lock()
	defer g.logMu.Unlock()
	select {
	case g.logEvents <- line:
	default:
		g.logLines = append(g.logLines, line)
	}
	g.window.Invalidate()
}

func (g *GioApp) drainLogs() {
	for {
		select {
		case line := <-g.logEvents:
			g.logLines = append(g.logLines, line)
			if len(g.logLines) > 400 {
				g.logLines = g.logLines[len(g.logLines)-400:]
			}
		default:
			return
		}
	}
}

func (g *GioApp) printMetric(name string) {
	fmt.Printf("metric %s_ms=%.1f\n", name, time.Since(g.startedAt).Seconds()*1000)
}

func extractPlaceholders(value string) []string {
	matches := placeholderPattern.FindAllStringSubmatch(value, -1)
	placeholders := make([]string, 0, len(matches))
	for _, match := range matches {
		placeholders = append(placeholders, strings.TrimSpace(match[1]))
	}
	return placeholders
}

func missingPlaceholders(values []string, context map[string]string) []string {
	seen := map[string]struct{}{}
	missing := []string{}
	for _, value := range values {
		for _, placeholder := range extractPlaceholders(value) {
			if _, ok := seen[placeholder]; ok {
				continue
			}
			seen[placeholder] = struct{}{}
			if strings.TrimSpace(context[placeholder]) == "" {
				missing = append(missing, placeholder)
			}
		}
	}
	return missing
}

func interpolateAll(values []string, context map[string]string) []string {
	rendered := make([]string, 0, len(values))
	for _, value := range values {
		rendered = append(rendered, interpolate(value, context))
	}
	return rendered
}

func interpolate(value string, context map[string]string) string {
	return placeholderPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := placeholderPattern.FindStringSubmatch(match)
		if len(parts) < 2 {
			return match
		}
		return context[strings.TrimSpace(parts[1])]
	})
}

func userHomeDir() string {
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return ""
}

func min(left int, right int) int {
	if left < right {
		return left
	}
	return right
}
