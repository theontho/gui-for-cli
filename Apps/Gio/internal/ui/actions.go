package ui

import (
	"fmt"
	"image/color"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

var placeholderPattern = regexp.MustCompile(`\{\{([^{}]+)\}\}`)

type precheckResult struct {
	severity string
	title    string
	message  string
}

func (g *GioApp) layoutActions(gtx layout.Context, actions []bundle.Action, rowValues map[string]string, keyPrefix string) layout.Dimensions {
	context := g.contextValues(rowValues)
	visible := make([]bundle.Action, 0, len(actions))
	for _, action := range actions {
		if g.actionVisible(action, context) {
			visible = append(visible, action)
		}
	}
	if len(visible) == 0 {
		return layout.Dimensions{}
	}
	children := make([]layout.FlexChild, 0, len(visible)*2)
	for _, action := range visible {
		action := action
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutAction(gtx, action, rowValues, keyPrefix+":"+action.ID, false)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
			}),
		)
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutAction(gtx layout.Context, action bundle.Action, rowValues map[string]string, key string, compact bool) layout.Dimensions {
	button := g.clickableForAction(key)
	if strings.HasPrefix(key, "row:") {
		button = g.clickableForRowAction(key)
	}
	context := g.contextValues(rowValues)
	disabledText, precheck := g.disabledActionText(action, context)
	running := g.actionRunning(key)
	if disabledText == "" && !running {
		for button.Clicked(gtx) {
			if action.Confirm != nil {
				g.pendingConfirm = &pendingConfirmation{action: action, actionKey: key, rowValues: cloneMap(rowValues)}
				g.confirmInput.SetText("")
				g.window.Invalidate()
				continue
			}
			g.runAction(action, rowValues, key)
		}
	}

	label := action.Title
	if action.IconOnly && action.IconEmoji != "" {
		label = action.IconEmoji
	}
	if action.IconEmoji != "" && !strings.HasPrefix(label, action.IconEmoji) {
		label = g.iconPrefix(action.IconEmoji, action.IconName, "") + label
	}
	if disabledText != "" {
		label = "○ " + label
	}
	if running {
		label = "⏳ " + label
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			style := g.actionButtonStyle(button, action, label, disabledText != "" || running)
			if disabledText != "" || running {
				return style.Layout(gtx.Disabled())
			}
			return style.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			note := action.Tooltip
			if disabledText != "" {
				note = disabledText
			} else if precheck != nil {
				note = precheck.message
			}
			if strings.TrimSpace(note) == "" || compact {
				return layout.Dimensions{}
			}
			return mutedText(g.theme, note).Layout(gtx)
		}),
	)
}

func (g *GioApp) disabledActionText(action bundle.Action, context map[string]string) (string, *precheckResult) {
	missing := missingPlaceholders(append([]string{action.Command.Executable}, action.Command.Arguments...), context)
	if len(missing) > 0 {
		return g.stringFormat("app.action.missingInputs.format", "Missing: %{inputs}", map[string]string{
			"inputs": strings.Join(missing, ", "),
		}), nil
	}
	if reason := g.disabledReason(action, context); reason != "" {
		return reason, nil
	}
	precheck := g.evaluatePrecheck(action.Precheck, context)
	if precheck != nil && precheck.severity == "warning" {
		return precheck.message, precheck
	}
	return "", precheck
}

func (g *GioApp) actionVisible(action bundle.Action, context map[string]string) bool {
	for _, condition := range action.VisibleWhen {
		if !conditionMatches(condition, context) {
			return false
		}
	}
	return true
}

func (g *GioApp) disabledReason(action bundle.Action, context map[string]string) string {
	for _, condition := range action.DisabledWhen {
		if conditionMatches(condition, context) {
			if action.DisabledTooltip != "" {
				return interpolate(action.DisabledTooltip, context)
			}
			return g.stringLabel("app.action.unavailable.title", "This action is not available.")
		}
	}
	return ""
}

func conditionMatches(condition bundle.ActionCondition, context map[string]string) bool {
	value := strings.TrimSpace(context[condition.Placeholder])
	if condition.Exists != nil && *condition.Exists != (value != "") {
		return false
	}
	if condition.Equals != "" && value != interpolate(condition.Equals, context) {
		return false
	}
	if condition.NotEquals != "" && value == interpolate(condition.NotEquals, context) {
		return false
	}
	if len(condition.In) > 0 && !stringIn(value, interpolateAll(condition.In, context)) {
		return false
	}
	if len(condition.NotIn) > 0 && stringIn(value, interpolateAll(condition.NotIn, context)) {
		return false
	}
	if condition.LessThan != "" && !compareNumeric(value, interpolate(condition.LessThan, context), func(left, right float64) bool { return left < right }) {
		return false
	}
	if condition.LessThanOrEqual != "" && !compareNumeric(value, interpolate(condition.LessThanOrEqual, context), func(left, right float64) bool { return left <= right }) {
		return false
	}
	if condition.GreaterThan != "" && !compareNumeric(value, interpolate(condition.GreaterThan, context), func(left, right float64) bool { return left > right }) {
		return false
	}
	if condition.GreaterThanOrEqual != "" && !compareNumeric(value, interpolate(condition.GreaterThanOrEqual, context), func(left, right float64) bool { return left >= right }) {
		return false
	}
	return true
}

func (g *GioApp) runAction(action bundle.Action, rowValues map[string]string, key string) {
	g.persistFormState()
	context := g.contextValues(rowValues)
	executable, arguments, missing := renderCommand(action.Command, context)
	if len(missing) > 0 {
		g.status = g.stringLabel("app.status.actionBlocked", "Action blocked")
		g.appendLog(g.stringFormat("app.action.skippedMissing.format", "Skipped %{action}: missing %{inputs}", map[string]string{
			"action": action.Title,
			"inputs": strings.Join(missing, ", "),
		}))
		return
	}

	commandLine := displayCommand(executable, arguments)
	g.status = g.stringFormat("app.status.runningAction.format", "Running %{action}", map[string]string{"action": action.Title})
	tabID := g.startCommandTerminal(action.Title, commandLine)
	g.setActionRunning(key, true)

	go func() {
		defer g.setActionRunning(key, false)
		command, err := shellCommand(executable, arguments)
		if err != nil {
			g.appendTerminalLine(tabID, g.stringFormat("app.terminal.commandSetupFailed.format", "Command setup failed: %{error}", map[string]string{"error": err.Error()}))
			g.finishTerminal(tabID, "error", g.terminalProcessErrorStatus(commandLine, err.Error()))
			return
		}
		command.Dir = g.bundle.BundleRoot
		command.Env = append(os.Environ(), g.environment(context, nil)...)
		prepareCommandForCancel(command)

		stdout, err := command.StdoutPipe()
		if err != nil {
			g.appendTerminalLine(tabID, g.stringFormat("app.terminal.captureStdoutFailed.format", "Could not capture stdout: %{error}", map[string]string{"error": err.Error()}))
			g.finishTerminal(tabID, "error", g.terminalProcessErrorStatus(commandLine, err.Error()))
			return
		}
		stderr, err := command.StderrPipe()
		if err != nil {
			g.appendTerminalLine(tabID, g.stringFormat("app.terminal.captureStderrFailed.format", "Could not capture stderr: %{error}", map[string]string{"error": err.Error()}))
			g.finishTerminal(tabID, "error", g.terminalProcessErrorStatus(commandLine, err.Error()))
			return
		}

		if err := command.Start(); err != nil {
			g.appendTerminalLine(tabID, g.stringFormat("app.terminal.commandStartFailed.format", "Command start failed: %{error}", map[string]string{"error": err.Error()}))
			g.finishTerminal(tabID, "error", g.terminalProcessErrorStatus(commandLine, err.Error()))
			g.status = g.processErrorTitle()
			g.window.Invalidate()
			return
		}
		g.registerRunningCommand(tabID, command)
		defer g.unregisterRunningCommand(tabID)

		var wg sync.WaitGroup
		wg.Add(2)
		go g.streamPipeToTerminal(tabID, stdout, &wg)
		go g.streamPipeToTerminal(tabID, stderr, &wg)
		wg.Wait()

		if err := command.Wait(); err != nil {
			g.appendTerminalLine(tabID, g.stringFormat("app.terminal.commandFailed.format", "Command failed: %{error}", map[string]string{"error": err.Error()}))
			g.status = g.processErrorTitle()
			status := g.terminalStatusForError(commandLine, err, tabID)
			g.finishTerminal(tabID, status.Severity, status)
		} else {
			g.appendTerminalLine(tabID, g.stringLabel("app.terminal.commandCompleted.summary", "Command completed successfully."))
			g.status = g.readyStatus()
			g.finishTerminal(tabID, "success", &terminalStatus{
				Severity: "success",
				Symbol:   "✓",
				Title:    g.stringLabel("app.terminal.commandCompleted.title", "Command completed"),
				Summary:  action.Title,
				Detail:   commandLine,
			})
		}
		if err := g.refreshDataSources(); err != nil {
			g.appendLog(g.stringFormat("app.refresh.warning.format", "Refresh warning: %{error}", map[string]string{"error": err.Error()}))
		}
		g.window.Invalidate()
	}()
}

func (g *GioApp) actionButtonStyle(button *widget.Clickable, action bundle.Action, label string, disabled bool) material.ButtonStyle {
	style := material.Button(g.theme, button, label)
	if disabled {
		style.Background = disabledButtonBackground(g.theme.Palette.Bg)
		style.Color = color.NRGBA{R: 113, G: 113, B: 122, A: 255}
		return style
	}
	if strings.EqualFold(action.Role, "destructive") {
		style.Background = destructiveButtonBackground()
		style.Color = color.NRGBA{R: 255, G: 255, B: 255, A: 255}
	}
	return style
}

func destructiveButtonBackground() color.NRGBA {
	return color.NRGBA{R: 220, G: 38, B: 38, A: 255}
}

func disabledButtonBackground(bg color.NRGBA) color.NRGBA {
	if bg.R < 80 && bg.G < 80 && bg.B < 80 {
		return color.NRGBA{R: 63, G: 63, B: 70, A: 255}
	}
	return color.NRGBA{R: 228, G: 228, B: 231, A: 255}
}

func (g *GioApp) actionRunning(key string) bool {
	g.actionMu.Lock()
	defer g.actionMu.Unlock()
	return g.runningActionKeys[key]
}

func (g *GioApp) setActionRunning(key string, running bool) {
	g.actionMu.Lock()
	if running {
		g.runningActionKeys[key] = true
	} else {
		delete(g.runningActionKeys, key)
	}
	g.actionMu.Unlock()
	if g.window != nil {
		g.window.Invalidate()
	}
}

func (g *GioApp) terminalStatusForError(commandLine string, err error, tabID string) *terminalStatus {
	if g.terminalCancelRequested(tabID) {
		return &terminalStatus{
			Severity: "warning",
			Symbol:   "!",
			Title:    g.stringLabel("exitCodes.default.130.title", "Command cancelled"),
			Summary:  g.stringLabel("exitCodes.default.130.summary", "The command was interrupted by the user."),
			Detail:   commandLine,
		}
	}
	exitCode := 1
	if exitError, ok := err.(*exec.ExitError); ok {
		exitCode = exitError.ExitCode()
	}
	reference := g.exitCodeReference(exitCode)
	severity := reference.Severity
	if severity != "warning" {
		severity = "error"
	}
	symbol := "✕"
	if severity == "warning" {
		symbol = "!"
	}
	title := reference.Title
	if title == "" {
		title = g.stringFormat("app.terminal.exitCode.titleFormat", "Exit code %{code}", map[string]string{"code": fmt.Sprintf("%d", exitCode)})
	}
	summary := reference.Summary
	if summary == "" {
		summary = g.stringLabel("app.terminal.nonzeroExit.summary", "The command exited with a non-zero status. Check the command output for details.")
	}
	return &terminalStatus{
		Severity: severity,
		Symbol:   symbol,
		Title:    title,
		Summary:  summary,
		Detail:   fmt.Sprintf("%s\nexit code: %d", commandLine, exitCode),
	}
}

func (g *GioApp) terminalProcessErrorStatus(commandLine string, message string) *terminalStatus {
	return &terminalStatus{
		Severity: "error",
		Symbol:   "✕",
		Title:    g.processErrorTitle(),
		Summary:  message,
		Detail:   commandLine,
	}
}

func (g *GioApp) exitCodeReference(code int) bundle.ExitCodeReference {
	for _, reference := range g.bundle.Manifest.ExitCodeReference {
		if reference.Code == code {
			return reference
		}
	}
	switch code {
	case 1:
		return bundle.ExitCodeReference{Code: code, Title: g.stringLabel("exitCodes.default.1.title", "General command failure"), Summary: g.stringLabel("exitCodes.default.1.summary", "The command reported a generic failure."), Severity: "error"}
	case 2:
		return bundle.ExitCodeReference{Code: code, Title: g.stringLabel("exitCodes.default.2.title", "Command-line usage error"), Summary: g.stringLabel("exitCodes.default.2.summary", "The command arguments were not accepted."), Severity: "error"}
	case 126:
		return bundle.ExitCodeReference{Code: code, Title: g.stringLabel("exitCodes.default.126.title", "Command found but not executable"), Summary: g.stringLabel("exitCodes.default.126.summary", "The command or script could not be executed."), Severity: "error"}
	case 127:
		return bundle.ExitCodeReference{Code: code, Title: g.stringLabel("exitCodes.default.127.title", "Command not found"), Summary: g.stringLabel("exitCodes.default.127.summary", "The runner could not find the executable."), Severity: "error"}
	case 130:
		return bundle.ExitCodeReference{Code: code, Title: g.stringLabel("exitCodes.default.130.title", "Command cancelled"), Summary: g.stringLabel("exitCodes.default.130.summary", "The command was interrupted by the user."), Severity: "warning"}
	default:
		return bundle.ExitCodeReference{Code: code, Severity: "error"}
	}
}

func shellCommand(executable string, arguments []string) (*exec.Cmd, error) {
	if runtime.GOOS == "windows" && strings.HasSuffix(strings.ToLower(executable), ".sh") {
		if bashPath, err := exec.LookPath("bash"); err == nil {
			return exec.Command(bashPath, append([]string{executable}, arguments...)...), nil
		}
		if shPath, err := exec.LookPath("sh"); err == nil {
			return exec.Command(shPath, append([]string{executable}, arguments...)...), nil
		}
		return nil, fmt.Errorf("no shell found to run %s", executable)
	}
	return exec.Command(executable, arguments...), nil
}

func renderCommand(command bundle.Command, context map[string]string) (string, []string, []string) {
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

func displayCommand(executable string, arguments []string) string {
	values := append([]string{executable}, arguments...)
	for index, value := range values {
		values[index] = shellQuote(value)
	}
	return strings.Join(values, " ")
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	for _, r := range value {
		if !(r == '_' || r == '-' || r == '.' || r == '/' || r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9') {
			return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
		}
	}
	return value
}
