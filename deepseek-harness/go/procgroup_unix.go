//go:build unix

package dsagent

import (
	"os/exec"
	"syscall"
)

// configureProcessGroup puts the command in its own process group and kills the
// whole group on cancellation.
//
// Killing only the shell is not enough: `sh -c` may fork, and a surviving
// grandchild keeps the stdout pipe open, so cmd.Run blocks until that child
// exits -- long past the timeout the caller asked for.
func configureProcessGroup(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		// The negative pid targets the group, not just the leader.
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
}
