package ui

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

type setupRunState struct {
	Status        string        `json:"status"`
	Results       []setupResult `json:"results"`
	CurrentStepID string        `json:"currentStepID"`
	Error         string        `json:"error"`
	CompletedAt   string        `json:"completedAt"`
}

type setupResult struct {
	ID       string `json:"id"`
	Label    string `json:"label"`
	Kind     string `json:"kind"`
	Command  string `json:"command"`
	Status   string `json:"status"`
	ExitCode int    `json:"exitCode"`
}

func (g *GioApp) layoutSetupStatus(gtx layout.Context) layout.Dimensions {
	for g.setupButton.Clicked(gtx) {
		g.runSetup()
	}
	for g.workspaceButton.Clicked(gtx) {
		g.openWorkspace()
	}
	status := g.setupStatusSummary()
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		children := []layout.FlexChild{
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return material.H6(g.theme, g.stringLabel("app.setup.status.title", "Setup")).Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return mutedText(g.theme, status).Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(
					gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return material.Button(g.theme, &g.workspaceButton, g.stringLabel("app.setup.openWorkspaceButton.title", "Open Bundle Workspace")).Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						label := g.stringLabel("app.setup.runButton.title", "Run Setup")
						if g.setupRun != nil && g.setupRun.Status == "ok" {
							label = g.stringLabel("app.setup.rerunButton.title", "Rerun Setup")
						}
						if g.runningSetup {
							label = g.stringLabel("app.setup.status.running", "Running setup...")
						}
						return material.Button(g.theme, &g.setupButton, label).Layout(gtx)
					}),
				)
			}),
		}
		results := map[string]setupResult{}
		if g.setupRun != nil {
			for _, result := range g.setupRun.Results {
				results[result.ID] = result
			}
		}
		for _, step := range g.bundle.Manifest.Setup.Steps {
			step := step
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				result := results[step.ID]
				status := "pending"
				if result.Status != "" {
					status = result.Status
				}
				if g.setupRun != nil && g.setupRun.CurrentStepID == step.ID {
					status = "running"
				}
				return material.Body2(g.theme, fmt.Sprintf("%s [%s] %s", setupGlyph(status), g.setupStepStatusLabel(status), step.Label)).Layout(gtx)
			}))
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(20)}.Layout(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}

func (g *GioApp) setupStatusSummary() string {
	if len(g.bundle.Manifest.Setup.Steps) == 0 {
		return g.stringLabel("app.setup.status.none", "No setup steps are defined for this bundle.")
	}
	if g.runningSetup || g.setupRun != nil && g.setupRun.Status == "running" {
		return g.stringLabel("app.setup.status.running", "Running setup...")
	}
	if g.setupRun == nil || g.setupRun.Status == "" {
		return g.stringLabel("app.setup.status.ready", "Review and run this bundle's setup steps.")
	}
	if g.setupRun.Status == "ok" {
		return g.stringLabel("app.setup.status.ok", "Setup completed successfully.")
	}
	return g.stringLabel("app.setup.status.failed", "Setup failed. Review command output for details.")
}

func (g *GioApp) runSetup() {
	g.setupMu.Lock()
	if g.runningSetup {
		g.setupMu.Unlock()
		return
	}
	g.runningSetup = true
	g.setupRun = &setupRunState{Status: "running", Results: []setupResult{}}
	tabID := g.startSetupTerminal()
	g.setupMu.Unlock()
	g.appendTerminalLine(tabID, "==> "+g.stringLabel("app.setup.status.running", "Running setup..."))

	go func() {
		defer func() {
			g.setupMu.Lock()
			g.runningSetup = false
			g.setupMu.Unlock()
			g.saveState()
			g.window.Invalidate()
		}()
		results := []setupResult{}
		status := "ok"
		for _, step := range g.bundle.Manifest.Setup.Steps {
			g.setupRun.CurrentStepID = step.ID
			g.window.Invalidate()
			result := g.executeSetupStep(tabID, step)
			results = append(results, result)
			g.setupRun.Results = results
			g.setupRun.CurrentStepID = ""
			if result.Status == "failed" {
				status = "failed"
				if !step.Optional {
					break
				}
			}
		}
		g.setupRun.Status = status
		g.setupRun.CompletedAt = time.Now().Format(time.RFC3339)
		g.appendTerminalLine(tabID, g.stringFormat("app.setup.finished.format", "Setup finished: %{status}", map[string]string{"status": g.setupStepStatusLabel(status)}))
		terminalKind := "success"
		symbol := "✓"
		if status != "ok" {
			terminalKind = "error"
			symbol = "✕"
		}
		g.finishTerminal(tabID, terminalKind, &terminalStatus{
			Severity: terminalKind,
			Symbol:   symbol,
			Title:    g.stringLabel("app.setup.finished.title", "Setup finished"),
			Summary:  g.setupStepStatusLabel(status),
			Detail:   g.stringLabel("app.setup.status.title", "Setup"),
		})
	}()
}

func (g *GioApp) executeSetupStep(tabID string, step bundle.SetupStep) setupResult {
	commandLine := ""
	result := setupResult{ID: step.ID, Label: step.Label, Kind: step.Kind, Status: "ok"}
	g.appendTerminalLine(tabID, "==> "+step.Label)
	command, err := g.setupCommand(step)
	if err != nil {
		result.Status = setupFailureStatus(step)
		result.Command = err.Error()
		g.appendTerminalLine(tabID, g.stringFormat("app.setup.stepFailed.format", "Setup step failed: %{error}", map[string]string{"error": err.Error()}))
		return result
	}
	commandLine = displayCommand(command.Path, command.Args[1:])
	result.Command = commandLine
	g.appendTerminalLine(tabID, "$ "+commandLine)
	prepareCommandForCancel(command)
	stdout, err := command.StdoutPipe()
	if err != nil {
		result.Status = setupFailureStatus(step)
		result.ExitCode = 1
		g.appendTerminalLine(tabID, g.stringFormat("app.setup.stdoutFailed.format", "Setup stdout failed: %{error}", map[string]string{"error": err.Error()}))
		return result
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		result.Status = setupFailureStatus(step)
		result.ExitCode = 1
		g.appendTerminalLine(tabID, g.stringFormat("app.setup.stderrFailed.format", "Setup stderr failed: %{error}", map[string]string{"error": err.Error()}))
		return result
	}
	if err := command.Start(); err != nil {
		result.Status = setupFailureStatus(step)
		result.ExitCode = 1
		g.appendTerminalLine(tabID, g.stringFormat("app.setup.startFailed.format", "Setup start failed: %{error}", map[string]string{"error": err.Error()}))
		return result
	}
	g.registerRunningCommand(tabID, command)
	defer g.unregisterRunningCommand(tabID)
	var wg sync.WaitGroup
	wg.Add(2)
	go g.streamPipeToTerminal(tabID, stdout, &wg)
	go g.streamPipeToTerminal(tabID, stderr, &wg)
	wg.Wait()
	if err := command.Wait(); err != nil {
		result.Status = setupFailureStatus(step)
		if exitError, ok := err.(*exec.ExitError); ok {
			result.ExitCode = exitError.ExitCode()
		} else {
			result.ExitCode = 1
		}
	} else {
		result.ExitCode = 0
	}
	if result.Status == "ok" && result.ExitCode != 0 {
		result.Status = setupFailureStatus(step)
	}
	g.appendTerminalLine(tabID, fmt.Sprintf("[%s] %s", result.Status, step.Label))
	return result
}

func (g *GioApp) setupCommand(step bundle.SetupStep) (*exec.Cmd, error) {
	ctx := g.contextValues(nil)
	value := interpolate(step.Value, ctx)
	args := interpolateAll(step.Args, ctx)
	var command *exec.Cmd
	switch step.Kind {
	case "pathTool":
		path, err := exec.LookPath(value)
		if err != nil {
			return nil, err
		}
		if runtime.GOOS == "windows" {
			command = exec.Command("cmd", "/C", "echo", path)
		} else {
			command = exec.Command("/usr/bin/env", "printf", "%s\n", path)
		}
	case "homebrewPackage":
		command = exec.Command("/usr/bin/env", "brew", "list", value)
	case "bundledScript", "setupScript":
		script, err := g.resolveBundlePath(value)
		if err != nil {
			return nil, err
		}
		command, err = shellCommand(script, args)
		if err != nil {
			return nil, err
		}
	case "pixiInstall":
		command = exec.Command("/usr/bin/env", append([]string{"pixi", "install"}, args...)...)
	case "pixiRun":
		command = exec.Command("/usr/bin/env", append([]string{"pixi", "run", value}, args...)...)
	default:
		return nil, fmt.Errorf("unsupported setup step kind: %s", step.Kind)
	}
	command.Dir = g.bundle.BundleRoot
	if step.WorkingDirectory != "" {
		workingDirectory, err := g.resolveBundlePath(step.WorkingDirectory)
		if err != nil {
			return nil, err
		}
		command.Dir = workingDirectory
	}
	command.Env = append(os.Environ(), g.environment(ctx, step.Env)...)
	return command, nil
}

func setupFailureStatus(step bundle.SetupStep) string {
	if step.Optional {
		return "warning"
	}
	return "failed"
}

func (g *GioApp) openWorkspace() {
	path := g.bundle.BundleWorkspaceRoot
	var command *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		command = exec.Command("open", path)
	case "windows":
		command = exec.Command("explorer", path)
	default:
		command = exec.Command("xdg-open", path)
	}
	if err := command.Start(); err != nil {
		g.appendLog("Open workspace failed: " + err.Error())
		return
	}
	g.appendLog("Opened workspace: " + path)
}

func setupGlyph(status string) string {
	switch status {
	case "running":
		return "…"
	case "ok":
		return "✓"
	case "warning":
		return "!"
	case "failed":
		return "×"
	default:
		return "○"
	}
}
