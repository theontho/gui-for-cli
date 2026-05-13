//go:build !windows

package ui

import (
	"os/exec"
	"syscall"
	"time"
)

func prepareCommandForCancel(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

func terminateProcessTree(command *exec.Cmd) {
	if command == nil || command.Process == nil {
		return
	}
	if pgid, err := syscall.Getpgid(command.Process.Pid); err == nil {
		_ = syscall.Kill(-pgid, syscall.SIGTERM)
		time.Sleep(200 * time.Millisecond)
		_ = syscall.Kill(-pgid, syscall.SIGKILL)
		return
	}
	_ = command.Process.Kill()
}
