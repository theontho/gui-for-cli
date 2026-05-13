package ui

import (
	"fmt"
	"image/color"
	"strings"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

type GioApp struct {
	window *app.Window
	theme  *material.Theme
	bundle *bundle.AppBundle

	startedAt                 time.Time
	firstFramePrinted         bool
	initialDataRefreshStarted bool

	sidebarList     layout.List
	contentList     layout.List
	terminalTabList layout.List
	terminalEditor  widget.Editor

	pageButtons            map[string]*widget.Clickable
	actionButtons          map[string]*widget.Clickable
	rowActionButtons       map[string]*widget.Clickable
	pathPickerButtons      map[string]*widget.Clickable
	terminalTabButtons     map[string]*widget.Clickable
	terminalCloseButtons   map[string]*widget.Clickable
	dataSourceRetryButtons map[string]*widget.Clickable
	configLoadButtons      map[string]*widget.Clickable
	setupButton            widget.Clickable
	workspaceButton        widget.Clickable
	confirmButton          widget.Clickable
	cancelButton           widget.Clickable
	sidebarToggleButton    widget.Clickable
	sidebarCloseButton     widget.Clickable
	terminalToggleButton   widget.Clickable
	terminalCopyButton     widget.Clickable

	dropdowns        map[string]*dropdownState
	textFields       map[string]*widget.Editor
	configPathFields map[string]*widget.Editor
	toggles          map[string]*widget.Bool
	checkboxGroups   map[string]*checkboxGroupState

	activePageID string
	status       string

	state                bundleState
	configPaths          map[string]string
	configValues         map[string]string
	sectionValues        map[string]map[string]string
	dataSourceErrors     map[string]string
	setupRun             *setupRunState
	pendingConfirm       *pendingConfirmation
	confirmInput         widget.Editor
	runningSetup         bool
	terminalEntries      []terminalEntry
	activeTerminalIndex  int
	terminalCopyFeedback bool
	runningCommands      map[string]*runningCommand
	runningActionKeys    map[string]bool

	logMu          sync.Mutex
	setupMu        sync.Mutex
	actionMu       sync.Mutex
	terminalEvents chan terminalEvent
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

type pendingConfirmation struct {
	action    bundle.Action
	actionKey string
	rowValues map[string]string
}

func Run(window *app.Window, loadedBundle *bundle.AppBundle, startedAt time.Time) error {
	ui := newApp(window, loadedBundle, startedAt)
	var ops op.Ops

	for {
		switch event := window.Event().(type) {
		case app.DestroyEvent:
			ui.terminateAllRunningCommands()
			return event.Err
		case app.FrameEvent:
			ui.drainLogs()
			gtx := app.NewContext(&ops, event)
			ui.layout(gtx)
			event.Frame(gtx.Ops)
			if !ui.firstFramePrinted {
				ui.printMetric("firstFrameRendered")
				ui.firstFramePrinted = true
				ui.refreshDataSourcesAfterFirstFrame()
			}
		}
	}
}

func newApp(window *app.Window, loadedBundle *bundle.AppBundle, startedAt time.Time) *GioApp {
	th := material.NewTheme()

	ui := &GioApp{
		window:                 window,
		theme:                  th,
		bundle:                 loadedBundle,
		startedAt:              startedAt,
		sidebarList:            layout.List{Axis: layout.Vertical},
		contentList:            layout.List{Axis: layout.Vertical},
		terminalTabList:        layout.List{Axis: layout.Horizontal},
		pageButtons:            map[string]*widget.Clickable{},
		actionButtons:          map[string]*widget.Clickable{},
		rowActionButtons:       map[string]*widget.Clickable{},
		pathPickerButtons:      map[string]*widget.Clickable{},
		terminalTabButtons:     map[string]*widget.Clickable{},
		terminalCloseButtons:   map[string]*widget.Clickable{},
		dataSourceRetryButtons: map[string]*widget.Clickable{},
		configLoadButtons:      map[string]*widget.Clickable{},
		dropdowns:              map[string]*dropdownState{},
		textFields:             map[string]*widget.Editor{},
		configPathFields:       map[string]*widget.Editor{},
		toggles:                map[string]*widget.Bool{},
		checkboxGroups:         map[string]*checkboxGroupState{},
		configPaths:            map[string]string{},
		configValues:           map[string]string{},
		sectionValues:          map[string]map[string]string{},
		dataSourceErrors:       map[string]string{},
		terminalEvents:         make(chan terminalEvent, 512),
		runningCommands:        map[string]*runningCommand{},
		runningActionKeys:      map[string]bool{},
	}
	ui.terminalEditor.ReadOnly = true
	ui.terminalEditor.SingleLine = false
	ui.confirmInput.SingleLine = true
	ui.status = ui.readyStatus()

	if err := ui.bootstrapState(); err != nil {
		ui.appendLog(fmt.Sprintf("Startup warning: %v", err))
	}
	ui.applyTheme()
	if ui.state.LocalizationCode != nil && *ui.state.LocalizationCode != "" && *ui.state.LocalizationCode != loadedBundle.LocalizationCode {
		if err := ui.reloadLocalization(*ui.state.LocalizationCode); err != nil {
			ui.appendLog(fmt.Sprintf("Language warning: %v", err))
		}
	}
	if len(ui.bundle.Manifest.Pages) > 0 {
		ui.activePageID = ui.bundle.Manifest.Pages[0].ID
	}
	if ui.state.SelectedPageID != "" && ui.pageExists(ui.state.SelectedPageID) {
		ui.activePageID = ui.state.SelectedPageID
	}
	ui.ensureMainTerminal()
	ui.appendTerminalLineDirect("main", fmt.Sprintf("Loaded bundle %q from %s", ui.bundle.Manifest.DisplayName, ui.bundle.BundleRoot))

	ui.seedState()
	return ui
}

func (g *GioApp) layout(gtx layout.Context) layout.Dimensions {
	paint.Fill(gtx.Ops, g.theme.Palette.Bg)
	inset := layout.UniformInset(unit.Dp(16))
	return inset.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		content := layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return g.layoutContent(gtx)
		})
		children := []layout.FlexChild{content}
		if g.sidebarVisible() {
			sidebar := []layout.FlexChild{
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Spacer{Width: unit.Dp(16)}.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.X = min(gtx.Constraints.Max.X, gtx.Dp(300))
					return g.layoutSidebar(gtx)
				}),
			}
			if g.layoutDirectionRTL() {
				children = append(children, sidebar...)
			} else {
				children = append(
					[]layout.FlexChild{
						sidebar[1],
						sidebar[0],
					},
					content,
				)
			}
		}
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
	})
}

func (g *GioApp) layoutDirectionRTL() bool {
	code := g.bundle.LocalizationCode
	if selected := g.selectedLocalizationCode(); selected != "" {
		code = selected
	}
	return localeCodeIsRTL(code)
}

func localeCodeIsRTL(code string) bool {
	normalized := strings.ToLower(strings.TrimSpace(code))
	if normalized == "" {
		return false
	}
	language := normalized
	if index := strings.IndexAny(language, "-_"); index >= 0 {
		language = language[:index]
	}
	switch language {
	case "ar", "fa", "he", "iw", "ps", "ur", "yi":
		return true
	default:
		return false
	}
}

func (g *GioApp) refreshDataSourcesAfterFirstFrame() {
	if g.initialDataRefreshStarted {
		return
	}
	g.initialDataRefreshStarted = true
	go func() {
		if err := g.refreshDataSources(); err != nil {
			g.appendLog(fmt.Sprintf("Data source warning: %v", err))
		}
		g.window.Invalidate()
	}()
}

func (g *GioApp) layoutSidebar(gtx layout.Context) layout.Dimensions {
	for g.sidebarCloseButton.Clicked(gtx) {
		g.setSidebarVisible(false)
	}
	items := g.bundle.Manifest.Pages
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(
				gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					title := material.H5(g.theme, g.bundle.Manifest.DisplayName)
					title.Color = g.theme.Palette.Fg
					return title.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return material.Button(g.theme, &g.sidebarCloseButton, "×").Layout(gtx)
				}),
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, g.bundle.Manifest.Summary).Layout(gtx)
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
					g.state.SelectedPageID = page.ID
					g.saveState()
					if err := g.refreshDataSourcesForPage(page.ID); err != nil {
						g.appendLog(fmt.Sprintf("Data source warning: %v", err))
					}
				}

				label := g.iconPrefix(page.TextIcon, page.IconName, "•") + page.Title
				if page.SidebarGroup != "" {
					label = fmt.Sprintf("%s — %s", page.SidebarGroup, label)
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
	for g.sidebarToggleButton.Clicked(gtx) {
		g.setSidebarVisible(!g.sidebarVisible())
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(
				gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return material.H4(g.theme, g.iconPrefix(page.TextIcon, page.IconName, "📄")+page.Title).Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					label := g.stringLabel("app.sidebar.hide.label", "Hide Sidebar")
					if !g.sidebarVisible() {
						label = g.stringLabel("app.sidebar.show.label", "Show Sidebar")
					}
					return material.Button(g.theme, &g.sidebarToggleButton, label).Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return g.layoutTerminalToggle(gtx)
				}),
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, page.Summary).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(16)}.Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			renderers := g.contentRenderers(page)
			return g.contentList.Layout(gtx, len(renderers), func(gtx layout.Context, index int) layout.Dimensions {
				return renderers[index](gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(12)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !g.terminalVisible() {
				return layout.Dimensions{}
			}
			return g.layoutTerminalPane(gtx)
		}),
	)
}

func (g *GioApp) contentRenderers(page bundle.Page) []func(layout.Context) layout.Dimensions {
	renderers := []func(layout.Context) layout.Dimensions{}
	if page.ID == "settings" {
		renderers = append(renderers, g.layoutStandardOptions)
	}
	if page.ID == "settings" || len(g.bundle.Manifest.Setup.Steps) > 0 && page.ID == g.activePageID && page.ID == "settings" {
		renderers = append(renderers, g.layoutSetupStatus)
	}
	if g.pendingConfirm != nil {
		renderers = append(renderers, g.layoutPendingConfirmation)
	}
	for _, section := range page.Sections {
		section := section
		renderers = append(renderers, func(gtx layout.Context) layout.Dimensions {
			return g.layoutSection(gtx, section)
		})
	}
	return renderers
}

func (g *GioApp) layoutSection(gtx layout.Context, section bundle.Section) layout.Dimensions {
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(
			gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				title := material.H6(g.theme, g.iconPrefix(section.TextIcon, section.IconName, "▦")+section.Title)
				return title.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if strings.TrimSpace(section.Subtitle) == "" {
					return layout.Dimensions{}
				}
				return mutedText(g.theme, section.Subtitle).Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				key := "section:" + section.ID
				if errText := g.dataSourceErrors[key]; errText != "" {
					return g.layoutDataSourceError(gtx, key, errText)
				}
				return layout.Dimensions{}
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
				return g.layoutActions(gtx, section.Actions, nil, "section:"+section.ID)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(20)}.Layout(gtx)
			}),
		)
	})
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
		g.editorFor(control.ID, g.controlValue(control))
	case "dropdown":
		g.dropdownFor(control.ID, control.Options, g.controlValue(control))
	case "toggle":
		g.toggleFor(control.ID, g.controlValue(control))
	case "checkboxGroup":
		g.checkboxGroupFor(control.ID, control.Options)
	case "configEditor":
		if control.ConfigFile != nil {
			g.configPathEditorFor(control)
		}
		for _, setting := range control.Settings {
			value := g.configValue(control, setting)
			switch setting.Kind {
			case "dropdown":
				g.dropdownFor(setting.ID, setting.Options, value)
			case "toggle":
				g.toggleFor(setting.ID, value)
			default:
				g.editorFor(setting.ID, value)
			}
		}
	}
}

func (g *GioApp) activePage() bundle.Page {
	for _, page := range g.bundle.Manifest.Pages {
		if page.ID == g.activePageID {
			return page
		}
	}
	if len(g.bundle.Manifest.Pages) == 0 {
		return bundle.Page{Title: g.stringLabel("app.page.empty.title", "No Pages")}
	}
	return g.bundle.Manifest.Pages[0]
}

func (g *GioApp) pageExists(id string) bool {
	for _, page := range g.bundle.Manifest.Pages {
		if page.ID == id {
			return true
		}
	}
	return false
}

func (g *GioApp) printMetric(name string) {
	fmt.Printf("metric %s_ms=%.1f\n", name, time.Since(g.startedAt).Seconds()*1000)
}

func mutedText(theme *material.Theme, text string) material.LabelStyle {
	body := material.Body2(theme, text)
	body.Color = color.NRGBA{R: 96, G: 96, B: 96, A: 255}
	return body
}

func warningText(theme *material.Theme, text string) material.LabelStyle {
	body := material.Body2(theme, text)
	body.Color = color.NRGBA{R: 160, G: 82, B: 45, A: 255}
	return body
}

func min(left int, right int) int {
	if left < right {
		return left
	}
	return right
}
