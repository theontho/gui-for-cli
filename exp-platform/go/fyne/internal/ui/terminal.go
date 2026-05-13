package ui

import (
	"fmt"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

type terminalEntry struct {
	id          string
	title       string
	commandLine string
	status      string
	lines       []string
	entry       *widget.Entry
	tabItem     *container.TabItem
	closable    bool
}

func (a *App) buildTerminal() fyne.CanvasObject {
	if a.terminal == nil {
		a.terminal = container.NewAppTabs()
		a.logEntry = newTerminalEntry()
		main := &terminalEntry{id: "main", title: "General", status: "ready", entry: a.logEntry}
		a.terminalEntries[main.id] = main
		main.tabItem = container.NewTabItem(main.title, container.NewBorder(nil, nil, nil, nil, main.entry))
		a.terminal.Append(main.tabItem)
	}
	return container.NewBorder(widget.NewLabelWithStyle("Terminal", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}), nil, nil, nil, a.terminal)
}

func (a *App) appendLog(line string) {
	if strings.TrimSpace(line) == "" {
		return
	}
	fyne.Do(func() {
		if a.logEntry == nil {
			a.logEntry = newTerminalEntry()
		}
		text := a.logEntry.Text
		if text != "" {
			text += "\n"
		}
		a.logEntry.SetText(text + timestamp() + " " + line)
	})
}

func (a *App) newCommandTerminal(title string, commandLine string) string {
	id := fmt.Sprintf("cmd-%d", time.Now().UnixNano())
	entry := newTerminalEntry()
	entry.SetText("$ " + commandLine)
	terminal := &terminalEntry{id: id, title: title, commandLine: commandLine, status: "running", entry: entry, closable: true}
	a.terminalEntries[id] = terminal
	cancel := widget.NewButton("Cancel", func() { a.cancelCommand(id) })
	closeButton := widget.NewButton("Close", func() { a.closeTerminal(id) })
	header := container.NewBorder(nil, nil, widget.NewLabel(commandLine), container.NewHBox(cancel, closeButton))
	item := container.NewTabItem("⏳ "+title, container.NewBorder(header, nil, nil, nil, entry))
	terminal.tabItem = item
	if a.terminal == nil {
		a.buildTerminal()
	}
	a.terminal.Append(item)
	a.terminal.Select(item)
	return id
}

func (a *App) appendTerminalLine(tabID string, line string) {
	fyne.Do(func() {
		terminal := a.terminalEntries[tabID]
		if terminal == nil {
			return
		}
		terminal.lines = append(terminal.lines, line)
		text := terminal.entry.Text
		if text != "" {
			text += "\n"
		}
		terminal.entry.SetText(text + line)
	})
}

func (a *App) finishTerminal(tabID string, status string, detail string) {
	fyne.Do(func() {
		terminal := a.terminalEntries[tabID]
		if terminal == nil {
			return
		}
		terminal.status = status
		if detail != "" {
			a.appendTerminalLine(tabID, "["+status+"] "+detail)
		}
		if a.terminal != nil && terminal.tabItem != nil {
			terminal.tabItem.Text = statusIcon(status) + " " + terminal.title
			a.terminal.Refresh()
		}
	})
}

func (a *App) closeTerminal(tabID string) {
	a.cancelCommand(tabID)
	if a.terminal == nil || tabID == "main" {
		return
	}
	terminal := a.terminalEntries[tabID]
	if terminal == nil || terminal.tabItem == nil {
		return
	}
	for index, item := range a.terminal.Items {
		if item == terminal.tabItem {
			a.terminal.RemoveIndex(index)
			delete(a.terminalEntries, tabID)
			return
		}
	}
}

func newTerminalEntry() *widget.Entry {
	entry := widget.NewMultiLineEntry()
	entry.Wrapping = fyne.TextWrapOff
	entry.Disable()
	return entry
}

func statusIcon(status string) string {
	switch status {
	case "success":
		return "✓"
	case "failed", "error":
		return "⚠"
	default:
		return "•"
	}
}

func timestamp() string {
	return time.Now().Format("15:04:05")
}
