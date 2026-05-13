//go:build windows

package runtime

import (
	"os/exec"
	"strconv"
	"syscall"
)

const windowsCreateNewProcessGroup = 0x00000200

func PrepareCommandForCancel(command *exec.Cmd) {
	if command.SysProcAttr == nil {
		command.SysProcAttr = &syscall.SysProcAttr{}
	}
	command.SysProcAttr.CreationFlags |= windowsCreateNewProcessGroup
}

func TerminateProcessTree(command *exec.Cmd) {
	if command == nil || command.Process == nil {
		return
	}
	if err := exec.Command("taskkill", "/T", "/F", "/PID", strconv.Itoa(command.Process.Pid)).Run(); err == nil {
		return
	}
	_ = command.Process.Kill()
}
