package ui

import (
	"os/exec"
	"strings"
	"testing"

	"gioui.org/widget"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestTerminalCreatesCommandTabsAndKeepsMain(t *testing.T) {
	app := testTerminalApp(t)
	app.ensureMainTerminal()
	tabID := app.startCommandTerminal("Run analysis", "echo hello")
	app.appendTerminalLineDirect(tabID, "hello")
	if len(app.terminalEntries) != 2 {
		t.Fatalf("terminalEntries = %d, want 2", len(app.terminalEntries))
	}
	if app.terminalEntries[0].ID != "main" {
		t.Fatalf("first tab = %q, want main", app.terminalEntries[0].ID)
	}
	if app.activeTerminal().ID != tabID {
		t.Fatalf("active tab = %q, want %q", app.activeTerminal().ID, tabID)
	}
	if !strings.Contains(app.activeTerminal().Body, "hello") {
		t.Fatalf("active body = %q, want command output", app.activeTerminal().Body)
	}
	if app.state.TerminalVisible == nil || !*app.state.TerminalVisible {
		t.Fatal("starting a command should show the terminal")
	}
}

func TestTerminalCloseRemovesFinishedCommandTab(t *testing.T) {
	app := testTerminalApp(t)
	tabID := app.startCommandTerminal("Run analysis", "echo hello")
	app.applyTerminalEvent(terminalEvent{TabID: tabID, Running: boolPtr(false)})
	app.closeTerminalTab(1)
	if len(app.terminalEntries) != 1 || app.terminalEntries[0].ID != "main" {
		t.Fatalf("terminalEntries = %#v, want only main", app.terminalEntries)
	}
}

func TestTerminalEditorSyncMovesCaretToEnd(t *testing.T) {
	app := testTerminalApp(t)
	body := "hello\nworld"
	app.syncTerminalEditorText(body)
	if app.terminalEditor.Text() != body {
		t.Fatalf("terminal text = %q, want %q", app.terminalEditor.Text(), body)
	}
	app.terminalEditor.Insert("!")
	if app.terminalEditor.Text() != "hello\nworld!" {
		t.Fatalf("terminal insert text = %q, want append at end", app.terminalEditor.Text())
	}
}

func TestLocaleCodeIsRTL(t *testing.T) {
	cases := map[string]bool{
		"ar":    true,
		"ar-EG": true,
		"fa_IR": true,
		"en":    false,
		"de-DE": false,
		"":      false,
	}
	for code, want := range cases {
		if got := localeCodeIsRTL(code); got != want {
			t.Fatalf("localeCodeIsRTL(%q) = %v, want %v", code, got, want)
		}
	}
}

func TestPreferenceNormalization(t *testing.T) {
	app := testTerminalApp(t)
	app.state.IconSet = "unknown"
	app.state.ColorTheme = "dark"
	app.state.WebUIFont = "sfPro"
	app.normalizePreferences()
	if app.state.IconSet != "platform" {
		t.Fatalf("IconSet = %q, want platform", app.state.IconSet)
	}
	if app.state.ColorTheme != "dark" {
		t.Fatalf("ColorTheme = %q, want dark", app.state.ColorTheme)
	}
	if app.state.WebUIFont != "sfPro" {
		t.Fatalf("WebUIFont = %q, want sfPro", app.state.WebUIFont)
	}
}

func TestTerminateAllRunningCommandsClearsRegistry(t *testing.T) {
	app := testTerminalApp(t)
	app.runningCommands["tab-1"] = &runningCommand{command: &exec.Cmd{}}
	app.runningCommands["tab-2"] = &runningCommand{}

	app.terminateAllRunningCommands()

	if len(app.runningCommands) != 0 {
		t.Fatalf("runningCommands = %#v, want empty after app shutdown cleanup", app.runningCommands)
	}
}

func testTerminalApp(t *testing.T) *GioApp {
	t.Helper()
	return &GioApp{
		bundle: &bundle.AppBundle{
			BundleWorkspaceRoot: t.TempDir(),
			Strings:             map[string]string{},
		},
		terminalTabButtons:   map[string]*widget.Clickable{},
		terminalCloseButtons: map[string]*widget.Clickable{},
		runningCommands:      map[string]*runningCommand{},
		terminalEvents:       make(chan terminalEvent, 16),
	}
}

func boolPtr(value bool) *bool {
	return &value
}
