//go:build windows

package ui

import "os/exec"

func prepareCommandForCancel(command *exec.Cmd) {}

func terminateProcessTree(command *exec.Cmd) {
	if command != nil && command.Process != nil {
		_ = command.Process.Kill()
	}
}
