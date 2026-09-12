//go:build !unix

package dsagent

import "os/exec"

// configureProcessGroup is a no-op where process groups are not available;
// exec's default cancellation (killing the child alone) applies, and WaitDelay
// still bounds how long Run waits on inherited pipes.
func configureProcessGroup(cmd *exec.Cmd) {}
