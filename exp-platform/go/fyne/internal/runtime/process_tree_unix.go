//go:build !windows

package runtime

import (
	"os/exec"
	"syscall"
	"time"
)

func PrepareCommandForCancel(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

func TerminateProcessTree(command *exec.Cmd) {
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
