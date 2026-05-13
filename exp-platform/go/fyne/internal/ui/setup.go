package ui

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"fyne.io/fyne/v2"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
	gfc "github.com/theontho/gui-for-cli/apps/fyne/internal/runtime"
)

func (a *App) runSetup() {
	tabID := a.newCommandTerminal("Setup", "bundle setup")
	go func() {
		failed := false
		for _, step := range a.bundle.Manifest.Setup.Steps {
			if err := a.runSetupStep(tabID, step); err != nil {
				failed = true
				a.appendTerminalLine(tabID, fmt.Sprintf("[failed] %s: %v", step.Label, err))
				if !step.Optional {
					break
				}
			}
		}
		if failed {
			a.finishTerminal(tabID, "failed", "Setup finished with warnings or failures")
		} else {
			a.finishTerminal(tabID, "success", "Setup completed")
		}
		if err := a.model.RefreshDataSourcesForPage(a.currentPage().ID); err != nil {
			a.appendLog(fmt.Sprintf("Refresh warning: %v", err))
		}
		fyne.Do(func() { a.rebuild() })
	}()
}

func (a *App) runSetupStep(tabID string, step bundle.SetupStep) error {
	a.appendTerminalLine(tabID, "→ "+step.Label)
	switch step.Kind {
	case "pathTool":
		if _, err := exec.LookPath(step.Value); err != nil {
			if step.Optional {
				a.appendTerminalLine(tabID, "  optional tool not found: "+step.Value)
				return nil
			}
			return err
		}
		a.appendTerminalLine(tabID, "  found "+step.Value)
		return nil
	case "setupScript":
		return a.runSetupScript(tabID, step)
	default:
		a.appendTerminalLine(tabID, "  skipped unsupported setup kind "+step.Kind)
		return nil
	}
}

func (a *App) runSetupScript(tabID string, step bundle.SetupStep) error {
	executable, err := a.model.ResolveBundlePath(step.Value)
	if err != nil {
		return err
	}
	context := a.model.Context(nil)
	command := exec.Command(executable, gfc.InterpolateAll(step.Args, context)...)
	command.Dir = a.bundle.BundleRoot
	if step.WorkingDirectory != "" {
		command.Dir, err = a.model.ResolveBundlePath(step.WorkingDirectory)
		if err != nil {
			return err
		}
	}
	command.Env = append(os.Environ(), a.model.Environment(context, step.Env)...)
	gfc.PrepareCommandForCancel(command)
	output, err := command.CombinedOutput()
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		if strings.TrimSpace(line) != "" {
			a.appendTerminalLine(tabID, "  "+line)
		}
	}
	return err
}
