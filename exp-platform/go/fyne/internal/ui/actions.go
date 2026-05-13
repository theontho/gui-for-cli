package ui

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
	gfc "github.com/theontho/gui-for-cli/apps/fyne/internal/runtime"
)

func (a *App) renderActions(actions []bundle.Action, rowValues map[string]string, keyPrefix string) []fyne.CanvasObject {
	return a.renderActionsWithContext(actions, rowValues, keyPrefix, a.model.Context(rowValues))
}

func (a *App) renderActionsWithContext(actions []bundle.Action, rowValues map[string]string, keyPrefix string, context map[string]string) []fyne.CanvasObject {
	objects := []fyne.CanvasObject{}
	for _, action := range actions {
		action := action
		if !gfc.ActionVisible(action, context) {
			continue
		}
		key := keyPrefix + ":" + action.ID
		button, note := a.actionButton(action, rowValues, key, context)
		objects = append(objects, container.NewVBox(button, note))
	}
	return objects
}

func (a *App) actionButton(action bundle.Action, rowValues map[string]string, key string, context map[string]string) (*widget.Button, fyne.CanvasObject) {
	label := action.Title
	if action.IconOnly && action.TextIcon != "" {
		label = action.TextIcon
	} else if action.TextIcon != "" {
		label = action.TextIcon + " " + label
	}
	if a.isActionRunning(key) {
		label = "⏳ " + label
	}
	button := widget.NewButton(label, func() { a.confirmAndRun(action, rowValues, key) })
	if action.Role == "destructive" {
		button.Importance = widget.DangerImportance
	}
	missing := gfc.MissingPlaceholders(action.Command, context)
	reason := ""
	if len(missing) > 0 {
		reason = "Missing required inputs: " + strings.Join(missing, ", ")
	} else if disabled := gfc.DisabledReason(action, context, "This action is not available."); disabled != "" {
		reason = disabled
	}
	if a.isActionRunning(key) {
		reason = "This action is already running."
	}
	if reason != "" {
		button.Disable()
		return button, helpLabel(reason)
	}
	if action.Precheck != nil && action.Precheck.WarningMessage != "" {
		return button, helpLabel(gfc.Interpolate(action.Precheck.WarningMessage, context))
	}
	return button, helpLabel(action.Tooltip)
}

func (a *App) confirmAndRun(action bundle.Action, rowValues map[string]string, key string) {
	if action.Confirm == nil {
		a.runAction(action, rowValues, key)
		return
	}
	confirm := action.Confirm
	dialog.ShowConfirm(confirm.Title, confirm.Message, func(ok bool) {
		if ok {
			a.runAction(action, rowValues, key)
		}
	}, a.window)
}

func (a *App) runAction(action bundle.Action, rowValues map[string]string, key string) {
	context := a.model.Context(rowValues)
	executable, args, missing := gfc.RenderCommand(action.Command, context)
	if len(missing) > 0 {
		a.appendLog("Action blocked: missing " + strings.Join(missing, ", "))
		return
	}
	commandLine := gfc.DisplayCommand(executable, args)
	tabID := a.newCommandTerminal(action.Title, commandLine)
	a.setActionRunning(key, true)
	a.rebuild()
	go a.runCommand(tabID, key, executable, args, context)
}

func (a *App) runCommand(tabID string, actionKey string, executable string, args []string, context map[string]string) {
	defer func() {
		a.setActionRunning(actionKey, false)
		if err := a.model.RefreshDataSourcesForPage(a.currentPage().ID); err != nil {
			a.appendLog(fmt.Sprintf("Refresh warning: %v", err))
		}
		fyne.Do(func() { a.rebuild() })
	}()
	command := exec.Command(executable, args...)
	command.Dir = a.bundle.BundleRoot
	command.Env = append(os.Environ(), a.model.Environment(context, nil)...)
	gfc.PrepareCommandForCancel(command)
	stdout, err := command.StdoutPipe()
	if err != nil {
		a.finishTerminal(tabID, "error", err.Error())
		return
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		a.finishTerminal(tabID, "error", err.Error())
		return
	}
	if err := command.Start(); err != nil {
		a.finishTerminal(tabID, "error", err.Error())
		return
	}
	a.registerCommand(tabID, command)
	defer a.unregisterCommand(tabID)
	var wg sync.WaitGroup
	wg.Add(2)
	go streamOutput(stdout, func(line string) { a.appendTerminalLine(tabID, line) }, &wg)
	go streamOutput(stderr, func(line string) { a.appendTerminalLine(tabID, line) }, &wg)
	wg.Wait()
	if err := command.Wait(); err != nil {
		a.appendTerminalLine(tabID, "Command failed: "+err.Error())
		a.finishTerminal(tabID, "failed", err.Error())
		return
	}
	a.appendTerminalLine(tabID, "Command completed successfully.")
	a.finishTerminal(tabID, "success", "Command completed")
}

func streamOutput(reader io.Reader, appendLine func(string), wg *sync.WaitGroup) {
	defer wg.Done()
	scanner := bufio.NewScanner(reader)
	buffer := make([]byte, 0, 64*1024)
	scanner.Buffer(buffer, 1024*1024)
	for scanner.Scan() {
		appendLine(scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		appendLine("Output read warning: " + err.Error())
	}
}

func (a *App) setActionRunning(key string, running bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if running {
		a.runningActions[key] = true
	} else {
		delete(a.runningActions, key)
	}
}

func (a *App) isActionRunning(key string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.runningActions[key]
}

func (a *App) registerCommand(tabID string, command *exec.Cmd) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.runningCommands[tabID] = command
}

func (a *App) unregisterCommand(tabID string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	delete(a.runningCommands, tabID)
}

func (a *App) cancelCommand(tabID string) {
	a.mu.Lock()
	command := a.runningCommands[tabID]
	a.mu.Unlock()
	if command != nil {
		gfc.TerminateProcessTree(command)
		a.appendTerminalLine(tabID, "Cancellation requested.")
	}
}

func (a *App) terminateAllCommands() {
	a.mu.Lock()
	commands := make([]*exec.Cmd, 0, len(a.runningCommands))
	for _, command := range a.runningCommands {
		commands = append(commands, command)
	}
	a.mu.Unlock()
	for _, command := range commands {
		gfc.TerminateProcessTree(command)
	}
}
