/**
 * Approval gate.
 *
 * Every mutating tool call goes through `check` before it runs. Read-only tools
 * never prompt; anything that writes to disk or executes a command does, unless
 * the mode or a remembered answer says otherwise.
 */

import { createInterface } from "node:readline/promises";

// A union of string literals rather than an enum: enums are not erasable
// syntax, and this file has to run under Node's native type stripping.
export const MODES = ["read-only", "ask", "accept-edits", "yolo"] as const;
export type Mode = (typeof MODES)[number];

export interface Decision {
  allowed: boolean;
  reason?: string;
}

export class PermissionGate {
  mode: Mode;
  interactive: boolean;
  /** Tool names the user answered "always" for -- this session only. */
  readonly remembered = new Set<string>();

  constructor(mode: Mode = "ask", interactive = process.stdin.isTTY === true) {
    this.mode = mode;
    this.interactive = interactive;
  }

  async check(toolName: string, mutating: boolean, preview: string): Promise<Decision> {
    if (!mutating) return { allowed: true };
    if (this.mode === "yolo" || this.remembered.has(toolName)) return { allowed: true };
    if (this.mode === "read-only") {
      return { allowed: false, reason: "read-only mode: mutating tools are disabled" };
    }
    if (this.mode === "accept-edits" && toolName !== "bash") return { allowed: true };
    if (!this.interactive) {
      return { allowed: false, reason: "no TTY available to approve this call" };
    }
    return this.prompt(toolName, preview);
  }

  private async prompt(toolName: string, preview: string): Promise<Decision> {
    process.stderr.write(`\n\x1b[33m┌ 승인 요청: ${toolName}\x1b[0m\n`);
    for (const line of preview.split("\n").slice(0, 40)) {
      process.stderr.write(`\x1b[33m│\x1b[0m ${line}\n`);
    }
    process.stderr.write("\x1b[33m└ [y] 허용  [a] 이 툴은 항상 허용  [n] 거부\x1b[0m\n");

    const rl = createInterface({ input: process.stdin, output: process.stderr });
    try {
      const answer = (await rl.question("  > ")).trim().toLowerCase();
      if (answer === "a" || answer === "always") {
        this.remembered.add(toolName);
        return { allowed: true };
      }
      if (answer === "" || answer === "y" || answer === "yes") return { allowed: true };
      return { allowed: false, reason: "user denied this tool call" };
    } catch {
      return { allowed: false, reason: "user aborted the approval prompt" };
    } finally {
      rl.close();
    }
  }
}
