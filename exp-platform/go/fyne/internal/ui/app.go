package ui

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
	gfc "github.com/theontho/gui-for-cli/apps/fyne/internal/runtime"
)

type RunOptions struct {
	StartedAt time.Time
}

type App struct {
	fyneApp fyne.App
	window  fyne.Window
	bundle  *bundle.AppBundle
	model   *gfc.Model

	startedAt time.Time
	status    *widget.Label
	content   *fyne.Container
	terminal  *container.AppTabs

	terminalEntries map[string]*terminalEntry
	runningCommands map[string]*exec.Cmd
	runningActions  map[string]bool
	logEntry        *widget.Entry
	mu              sync.Mutex
}

func Run(fyneApp fyne.App, loaded *bundle.AppBundle, options RunOptions) error {
	model := gfc.NewModel(loaded)
	app := &App{
		fyneApp:         fyneApp,
		bundle:          loaded,
		model:           model,
		startedAt:       options.StartedAt,
		status:          widget.NewLabel("Ready"),
		terminalEntries: map[string]*terminalEntry{},
		runningCommands: map[string]*exec.Cmd{},
		runningActions:  map[string]bool{},
	}
	if app.startedAt.IsZero() {
		app.startedAt = time.Now()
	}
	if err := model.Bootstrap(); err != nil {
		app.appendLog(fmt.Sprintf("Startup warning: %v", err))
	}
	app.window = fyneApp.NewWindow(fmt.Sprintf("%s (Fyne)", loaded.Manifest.DisplayName))
	app.window.Resize(fyne.NewSize(1440, 920))
	app.window.SetCloseIntercept(func() {
		app.terminateAllCommands()
		app.window.Close()
	})
	app.rebuild()
	app.printMetric("windowConfigured")
	go func() {
		time.Sleep(350 * time.Millisecond)
		app.printMetric("firstFrameRendered")
		app.refreshCurrentPageDataSources()
	}()
	app.window.ShowAndRun()
	return nil
}

func (a *App) rebuild() {
	page := a.currentPage()
	a.status.SetText(a.readyStatus())
	a.content = container.NewVBox(a.pageHeader(page), a.renderPage(page))
	main := container.NewBorder(a.topBar(), nil, nil, nil, container.NewVScroll(a.content))
	body := fyne.CanvasObject(main)
	if a.model.State.TerminalVisible {
		split := container.NewVSplit(main, a.buildTerminal())
		split.Offset = 0.72
		body = split
	}
	if a.model.State.SidebarVisible {
		sidebar := a.sidebar()
		if isRTL(a.bundle.LocalizationCode) {
			body = container.NewBorder(nil, nil, nil, sidebar, body)
		} else {
			body = container.NewBorder(nil, nil, sidebar, nil, body)
		}
	}
	a.window.SetContent(body)
}

func (a *App) topBar() fyne.CanvasObject {
	title := widget.NewLabelWithStyle(a.bundle.Manifest.TextIcon+" "+a.bundle.Manifest.DisplayName, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	language := a.languageSelect()
	setup := widget.NewButton("Run setup", a.runSetup)
	workspace := widget.NewButton("Open workspace", func() {
		if err := openPath(a.bundle.BundleWorkspaceRoot); err != nil {
			a.showError(err)
		}
	})
	sidebar := widget.NewButton(toggleLabel("Sidebar", a.model.State.SidebarVisible), func() {
		a.model.State.SidebarVisible = !a.model.State.SidebarVisible
		_ = a.model.SaveState()
		a.rebuild()
	})
	terminal := widget.NewButton(toggleLabel("Terminal", a.model.State.TerminalVisible), func() {
		a.model.State.TerminalVisible = !a.model.State.TerminalVisible
		_ = a.model.SaveState()
		a.rebuild()
	})
	controls := container.NewHBox(language, setup, workspace, sidebar, terminal)
	summary := widget.NewLabel(a.bundle.Manifest.Summary)
	summary.Wrapping = fyne.TextWrapWord
	return container.NewVBox(container.NewBorder(nil, nil, title, controls), summary, a.status)
}

func (a *App) pageHeader(page bundle.Page) fyne.CanvasObject {
	title := widget.NewLabelWithStyle(iconPrefix(page.TextIcon)+page.Title, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	summary := widget.NewLabel(page.Summary)
	summary.Wrapping = fyne.TextWrapWord
	return container.NewVBox(title, summary, widget.NewSeparator())
}

func (a *App) sidebar() fyne.CanvasObject {
	items := []fyne.CanvasObject{}
	lastGroup := ""
	for _, page := range a.bundle.Manifest.Pages {
		if page.SidebarGroup != "" && page.SidebarGroup != lastGroup {
			items = append(items, widget.NewLabelWithStyle(page.SidebarGroup, fyne.TextAlignLeading, fyne.TextStyle{Bold: true}))
			lastGroup = page.SidebarGroup
		}
		page := page
		label := iconPrefix(page.TextIcon) + page.Title
		button := widget.NewButton(label, func() {
			a.model.State.SelectedPageID = page.ID
			_ = a.model.SaveState()
			a.rebuild()
			a.refreshCurrentPageDataSources()
		})
		if page.ID == a.model.State.SelectedPageID {
			button.Importance = widget.HighImportance
		}
		items = append(items, button)
	}
	box := container.NewVBox(items...)
	return container.NewPadded(container.NewVScroll(box))
}

func (a *App) languageSelect() fyne.CanvasObject {
	if len(a.bundle.LocalizationOptions) == 0 {
		return widget.NewLabel(a.bundle.LocalizationCode)
	}
	labels := []string{}
	codeByLabel := map[string]string{}
	selected := ""
	for _, option := range a.bundle.LocalizationOptions {
		label := fmt.Sprintf("%s · %s", option.DisplayName, option.Code)
		labels = append(labels, label)
		codeByLabel[label] = option.Code
		if option.Code == a.bundle.LocalizationCode {
			selected = label
		}
	}
	selectWidget := widget.NewSelect(labels, func(label string) {
		code := codeByLabel[label]
		if code == "" || code == a.bundle.LocalizationCode {
			return
		}
		reloaded, err := bundle.Load(bundle.LoadOptions{
			BundleRoot:         a.bundle.BundleRoot,
			BuiltinStringsRoot: a.bundle.BuiltinStringsRoot,
			LocalizationCode:   code,
		})
		if err != nil {
			a.showError(err)
			return
		}
		a.bundle = reloaded
		a.model.Bundle = reloaded
		a.model.State.LocalizationCode = code
		_ = a.model.SaveState()
		a.rebuild()
	})
	selectWidget.PlaceHolder = "Language"
	selectWidget.SetSelected(selected)
	return selectWidget
}

func (a *App) currentPage() bundle.Page {
	for _, page := range a.bundle.Manifest.Pages {
		if page.ID == a.model.State.SelectedPageID {
			return page
		}
	}
	if len(a.bundle.Manifest.Pages) > 0 {
		return a.bundle.Manifest.Pages[0]
	}
	return bundle.Page{ID: "empty", Title: "No pages"}
}

func (a *App) refreshCurrentPageDataSources() {
	pageID := a.currentPage().ID
	go func() {
		if err := a.model.RefreshDataSourcesForPage(pageID); err != nil {
			a.appendLog(fmt.Sprintf("Refresh warning: %v", err))
		}
		fyne.Do(func() { a.rebuild() })
	}()
}

func (a *App) showError(err error) {
	if err == nil || a.window == nil {
		return
	}
	dialog.ShowError(err, a.window)
}

func (a *App) readyStatus() string {
	return fmt.Sprintf("%s · %s · %d pages", a.bundle.LocalizationCode, a.bundle.BundleWorkspaceRoot, len(a.bundle.Manifest.Pages))
}

func (a *App) printMetric(name string) {
	fmt.Printf("metric %s_ms=%.1f\n", name, time.Since(a.startedAt).Seconds()*1000)
}

func iconPrefix(icon string) string {
	if strings.TrimSpace(icon) == "" {
		return ""
	}
	return icon + " "
}

func toggleLabel(label string, visible bool) string {
	if visible {
		return "Hide " + label
	}
	return "Show " + label
}

func isRTL(locale string) bool {
	base := strings.ToLower(strings.Split(locale, "-")[0])
	switch base {
	case "ar", "fa", "he", "ur":
		return true
	default:
		return false
	}
}

func openPath(path string) error {
	switch runtime.GOOS {
	case "darwin":
		return exec.Command("open", path).Start()
	case "windows":
		return exec.Command("cmd", "/C", "start", "", path).Start()
	default:
		return exec.Command("xdg-open", path).Start()
	}
}
