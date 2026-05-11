//go:build windows

package ui

import (
	"os/exec"
	"strconv"
	"syscall"
)

const windowsCreateNewProcessGroup = 0x00000200

func prepareCommandForCancel(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{CreationFlags: windowsCreateNewProcessGroup}
}

func terminateProcessTree(command *exec.Cmd) {
	if command == nil || command.Process == nil {
		return
	}
	if err := exec.Command("taskkill", "/T", "/F", "/PID", strconv.Itoa(command.Process.Pid)).Run(); err == nil {
		return
	}
	_ = command.Process.Kill()
}
