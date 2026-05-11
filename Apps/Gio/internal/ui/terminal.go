package ui

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"sync"

	"gioui.org/io/clipboard"
	"gioui.org/layout"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"
)

type terminalEntry struct {
	ID              string
	Kind            string
	Title           string
	Body            string
	Command         string
	Running         bool
	CancelRequested bool
	Status          *terminalStatus
}

type terminalStatus struct {
	Severity string
	Symbol   string
	Title    string
	Summary  string
	Detail   string
}

type terminalEvent struct {
	TabID   string
	Line    string
	Kind    string
	Running *bool
	Status  *terminalStatus
}

type runningCommand struct {
	command *exec.Cmd
}

func (g *GioApp) layoutTerminalToggle(gtx layout.Context) layout.Dimensions {
	for g.terminalToggleButton.Clicked(gtx) {
		g.setTerminalVisible(!g.terminalVisible())
	}
	label := g.stringLabel("app.terminal.hideOutput.label", "Hide Command Output")
	if !g.terminalVisible() {
		label = g.stringLabel("app.terminal.showOutput.label", "Show Command Output")
	}
	return material.Button(g.theme, &g.terminalToggleButton, label).Layout(gtx)
}

func (g *GioApp) layoutTerminalPane(gtx layout.Context) layout.Dimensions {
	g.ensureMainTerminal()
	g.handleTerminalHeaderClicks(gtx)
	active := g.activeTerminal()
	if strings.EqualFold(g.bundle.Manifest.TerminalTextDirection, "rtl") {
		g.terminalEditor.Alignment = text.End
	} else {
		g.terminalEditor.Alignment = text.Start
	}
	g.terminalEditor.SetText(active.Body)
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(
			gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutTerminalHeader(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if active.Status == nil {
					return layout.Dimensions{}
				}
				text := strings.TrimSpace(active.Status.Title + ": " + active.Status.Summary)
				if active.Status.Severity == "error" || active.Status.Severity == "warning" {
					return warningText(g.theme, text).Layout(gtx)
				}
				return mutedText(g.theme, text).Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				maxHeight := gtx.Dp(240)
				if gtx.Constraints.Max.Y > maxHeight {
					gtx.Constraints.Max.Y = maxHeight
				}
				minHeight := gtx.Dp(160)
				if gtx.Constraints.Max.Y < minHeight {
					minHeight = gtx.Constraints.Max.Y
				}
				gtx.Constraints.Min.Y = minHeight
				return material.Editor(g.theme, &g.terminalEditor, "").Layout(gtx)
			}),
		)
	})
}

func (g *GioApp) layoutTerminalHeader(gtx layout.Context) layout.Dimensions {
	copyLabel := g.stringLabel("app.terminal.copyText.label", "Copy terminal text")
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, "⌘").Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return g.terminalTabList.Layout(gtx, len(g.terminalEntries), func(gtx layout.Context, index int) layout.Dimensions {
				entry := g.terminalEntries[index]
				return g.layoutTerminalTab(gtx, entry, index)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, &g.terminalCopyButton, copyLabel).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !g.terminalCopyFeedback {
				return layout.Dimensions{}
			}
			return mutedText(g.theme, " "+g.stringLabel("app.terminal.copiedText.label", "Copied!")).Layout(gtx)
		}),
	)
}

func (g *GioApp) layoutTerminalTab(gtx layout.Context, entry terminalEntry, index int) layout.Dimensions {
	button := g.terminalButtonFor(entry.ID)
	closeButton := g.terminalCloseButtonFor(entry.ID)
	label := terminalTabLabel(entry)
	if index == g.activeTerminalIndex {
		label = "● " + label
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, button, label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if index == 0 {
				return layout.Spacer{Width: unit.Dp(6)}.Layout(gtx)
			}
			closeLabel := "×"
			if entry.Running {
				closeLabel = "Cancel"
			}
			return material.Button(g.theme, closeButton, closeLabel).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Width: unit.Dp(6)}.Layout(gtx)
		}),
	)
}

func (g *GioApp) handleTerminalHeaderClicks(gtx layout.Context) {
	for g.terminalCopyButton.Clicked(gtx) {
		text := g.activeTerminal().Body
		gtx.Execute(clipboard.WriteCmd{Type: "application/text", Data: io.NopCloser(strings.NewReader(text))})
		g.terminalCopyFeedback = true
	}
	for index := range g.terminalEntries {
		entry := g.terminalEntries[index]
		for g.terminalButtonFor(entry.ID).Clicked(gtx) {
			g.activeTerminalIndex = index
		}
		for g.terminalCloseButtonFor(entry.ID).Clicked(gtx) {
			g.closeTerminalTab(index)
			return
		}
	}
}

func (g *GioApp) terminalButtonFor(id string) *widget.Clickable {
	if existing, ok := g.terminalTabButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.terminalTabButtons[id] = clickable
	return clickable
}

func (g *GioApp) terminalCloseButtonFor(id string) *widget.Clickable {
	if existing, ok := g.terminalCloseButtons[id]; ok {
		return existing
	}
	clickable := new(widget.Clickable)
	g.terminalCloseButtons[id] = clickable
	return clickable
}

func (g *GioApp) startCommandTerminal(title string, commandLine string) string {
	id := fmt.Sprintf("command-%d", len(g.terminalEntries)+1)
	g.ensureMainTerminal()
	entry := terminalEntry{
		ID:      id,
		Kind:    "command",
		Title:   title,
		Command: commandLine,
		Body:    "> " + commandLine,
		Running: true,
	}
	g.terminalEntries = append(g.terminalEntries, entry)
	if len(g.terminalEntries) > 40 {
		g.terminalEntries = append(g.terminalEntries[:1], g.terminalEntries[len(g.terminalEntries)-39:]...)
	}
	g.activeTerminalIndex = len(g.terminalEntries) - 1
	g.setTerminalVisible(true)
	return id
}

func (g *GioApp) startSetupTerminal() string {
	id := "setup"
	for index, entry := range g.terminalEntries {
		if entry.ID == id {
			g.terminalEntries[index] = terminalEntry{ID: id, Kind: "command", Title: "Setup", Running: true}
			g.activeTerminalIndex = index
			g.setTerminalVisible(true)
			return id
		}
	}
	g.terminalEntries = append(g.terminalEntries, terminalEntry{ID: id, Kind: "command", Title: "Setup", Running: true})
	g.activeTerminalIndex = len(g.terminalEntries) - 1
	g.setTerminalVisible(true)
	return id
}

func (g *GioApp) finishTerminal(tabID string, kind string, status *terminalStatus) {
	running := false
	g.sendTerminalEvent(terminalEvent{TabID: tabID, Kind: kind, Running: &running, Status: status})
}

func (g *GioApp) appendTerminalLine(tabID string, line string) {
	g.sendTerminalEvent(terminalEvent{TabID: tabID, Line: line})
}

func (g *GioApp) sendTerminalEvent(event terminalEvent) {
	g.logMu.Lock()
	defer g.logMu.Unlock()
	select {
	case g.terminalEvents <- event:
	default:
		g.applyTerminalEvent(event)
	}
	if g.window != nil && g.firstFramePrinted {
		g.window.Invalidate()
	}
}

func (g *GioApp) appendTerminalLineDirect(tabID string, line string) {
	g.applyTerminalEvent(terminalEvent{TabID: tabID, Line: line})
}

func (g *GioApp) drainLogs() {
	for {
		select {
		case event := <-g.terminalEvents:
			g.applyTerminalEvent(event)
		default:
			return
		}
	}
}

func (g *GioApp) applyTerminalEvent(event terminalEvent) {
	g.ensureMainTerminal()
	index := g.terminalIndex(event.TabID)
	if index < 0 {
		index = 0
	}
	entry := &g.terminalEntries[index]
	if event.Line != "" {
		entry.Body = appendTerminalBody(entry.Body, event.Line)
	}
	if event.Kind != "" {
		entry.Kind = event.Kind
	}
	if event.Running != nil {
		entry.Running = *event.Running
	}
	if event.Status != nil {
		entry.Status = event.Status
	}
	if g.activeTerminalIndex >= len(g.terminalEntries) {
		g.activeTerminalIndex = len(g.terminalEntries) - 1
	}
}

func (g *GioApp) ensureMainTerminal() {
	title := g.stringLabel("app.terminal.mainTab.title", "Main")
	if len(g.terminalEntries) > 0 && g.terminalEntries[0].ID == "main" {
		g.terminalEntries[0].Title = title
		return
	}
	g.terminalEntries = append([]terminalEntry{{
		ID:    "main",
		Kind:  "main",
		Title: title,
	}}, g.terminalEntries...)
	g.activeTerminalIndex++
	if g.activeTerminalIndex >= len(g.terminalEntries) {
		g.activeTerminalIndex = 0
	}
}

func (g *GioApp) activeTerminal() terminalEntry {
	g.ensureMainTerminal()
	if g.activeTerminalIndex < 0 || g.activeTerminalIndex >= len(g.terminalEntries) {
		g.activeTerminalIndex = 0
	}
	return g.terminalEntries[g.activeTerminalIndex]
}

func (g *GioApp) closeTerminalTab(index int) {
	if index <= 0 || index >= len(g.terminalEntries) {
		return
	}
	entry := g.terminalEntries[index]
	if entry.Running {
		g.cancelTerminal(entry.ID)
		return
	}
	delete(g.terminalTabButtons, entry.ID)
	delete(g.terminalCloseButtons, entry.ID)
	g.terminalEntries = append(g.terminalEntries[:index], g.terminalEntries[index+1:]...)
	if g.activeTerminalIndex >= len(g.terminalEntries) {
		g.activeTerminalIndex = len(g.terminalEntries) - 1
	}
	if g.activeTerminalIndex > index {
		g.activeTerminalIndex--
	}
}

func (g *GioApp) cancelTerminal(tabID string) {
	if index := g.terminalIndex(tabID); index >= 0 {
		g.terminalEntries[index].CancelRequested = true
		g.terminalEntries[index].Status = &terminalStatus{
			Severity: "warning",
			Symbol:   "!",
			Title:    g.stringLabel("exitCodes.default.130.title", "Command cancelled"),
			Summary:  g.stringLabel("exitCodes.default.130.summary", "The command was interrupted by the user."),
			Detail:   g.terminalEntries[index].Command,
		}
		g.appendTerminalLineDirect(tabID, "Cancellation requested.")
	}
	g.cancelRunningCommand(tabID)
}

func (g *GioApp) registerRunningCommand(tabID string, command *exec.Cmd) {
	g.logMu.Lock()
	defer g.logMu.Unlock()
	g.runningCommands[tabID] = &runningCommand{command: command}
}

func (g *GioApp) unregisterRunningCommand(tabID string) {
	g.logMu.Lock()
	defer g.logMu.Unlock()
	delete(g.runningCommands, tabID)
}

func (g *GioApp) cancelRunningCommand(tabID string) {
	g.logMu.Lock()
	running := g.runningCommands[tabID]
	g.logMu.Unlock()
	if running != nil {
		terminateProcessTree(running.command)
	}
}

func (g *GioApp) terminalIndex(tabID string) int {
	if tabID == "" {
		tabID = "main"
	}
	for index, entry := range g.terminalEntries {
		if entry.ID == tabID {
			return index
		}
	}
	return -1
}

func (g *GioApp) terminalCancelRequested(tabID string) bool {
	g.logMu.Lock()
	defer g.logMu.Unlock()
	index := g.terminalIndex(tabID)
	return index >= 0 && g.terminalEntries[index].CancelRequested
}

func (g *GioApp) terminalVisible() bool {
	return g.state.TerminalVisible == nil || *g.state.TerminalVisible
}

func (g *GioApp) setTerminalVisible(visible bool) {
	g.state.TerminalVisible = &visible
	g.saveState()
}

func (g *GioApp) sidebarVisible() bool {
	return g.state.SidebarVisible == nil || *g.state.SidebarVisible
}

func (g *GioApp) setSidebarVisible(visible bool) {
	g.state.SidebarVisible = &visible
	g.saveState()
}

func terminalTabLabel(entry terminalEntry) string {
	prefix := ""
	if entry.Running {
		prefix = "… "
	} else if entry.Status != nil && entry.Status.Symbol != "" {
		prefix = entry.Status.Symbol + " "
	}
	title := entry.Title
	if title == "" {
		title = entry.ID
	}
	return prefix + title
}

func appendTerminalBody(body string, line string) string {
	if body == "" {
		body = line
	} else {
		body += "\n" + line
	}
	lines := strings.Split(body, "\n")
	if len(lines) > 1200 {
		body = strings.Join(lines[len(lines)-1200:], "\n")
	}
	return body
}

func (g *GioApp) streamPipeToTerminal(tabID string, pipe io.Reader, wg *sync.WaitGroup) {
	defer wg.Done()
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		g.appendTerminalLine(tabID, scanner.Text())
	}
}
