//go:build !windows

package runtime

import (
	"os/exec"
	"syscall"
	"testing"
)

func TestPrepareCommandForCancelPreservesExistingSysProcAttr(t *testing.T) {
	command := exec.Command("echo", "hello")
	command.SysProcAttr = &syscall.SysProcAttr{Foreground: true}

	PrepareCommandForCancel(command)

	if command.SysProcAttr == nil {
		t.Fatal("SysProcAttr = nil")
	}
	if !command.SysProcAttr.Foreground {
		t.Fatal("Foreground was not preserved")
	}
	if !command.SysProcAttr.Setpgid {
		t.Fatal("Setpgid was not enabled")
	}
}
