// Command dsagent is a DeepSeek-driven coding agent CLI.
package main

import (
	"os"

	"dsagent"
)

func main() {
	os.Exit(dsagent.Main(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
