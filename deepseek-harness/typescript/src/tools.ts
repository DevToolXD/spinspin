/**
 * Tool registry: JSON schemas the model sees, plus the code behind them.
 *
 * Every path argument is resolved against the workspace root and rejected if it
 * escapes -- the model is not trusted to stay inside on its own.
 */

import { exec } from "node:child_process";
import { promises as fs } from "node:fs";
import * as path from "node:path";
import { promisify } from "node:util";

const execAsync = promisify(exec);

const MAX_OUTPUT_CHARS = 30_000;
const IGNORED_DIRS = new Set([".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", ".next"]);

/** A failure the model should see and be able to recover from. */
export class ToolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ToolError";
  }
}

export interface Tool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  mutating: boolean;
  handler: (args: any) => Promise<string>;
  /** One-line summary shown in the approval prompt. */
  preview?: (args: any) => string;
}

export function toSchema(tool: Tool): Record<string, unknown> {
  return {
    type: "function",
    function: { name: tool.name, description: tool.description, parameters: tool.parameters },
  };
}

/**
 * Split text into lines the way a person counts them: a single trailing
 * newline terminates the last line rather than starting an empty one.
 * Mirrors Python's str.splitlines(), so all three ports agree.
 */
export function splitLines(text: string): string[] {
  if (text === "") return [];
  return text.replace(/\n$/, "").split("\n");
}

function truncate(text: string): string {
  if (text.length <= MAX_OUTPUT_CHARS) return text;
  const half = Math.floor(MAX_OUTPUT_CHARS / 2);
  const dropped = text.length - MAX_OUTPUT_CHARS;
  return `${text.slice(0, half)}\n\n... [${dropped} characters truncated] ...\n\n${text.slice(-half)}`;
}

/** Filesystem access confined to one root directory. */
export class Workspace {
  readonly root: string;

  constructor(root: string) {
    this.root = path.resolve(root);
  }

  resolve(candidate: string): string {
    const full = path.resolve(this.root, candidate);
    const relative = path.relative(this.root, full);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new ToolError(`path escapes the workspace root (${this.root}): ${candidate}`);
    }
    return full;
  }

  rel(full: string): string {
    return path.relative(this.root, full) || ".";
  }
}

async function walk(dir: string, depth: number, out: string[], indent = ""): Promise<void> {
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  const dirs = entries.filter((e) => e.isDirectory() && !IGNORED_DIRS.has(e.name) && !e.name.startsWith("."));
  const files = entries.filter((e) => e.isFile());

  for (const file of files.slice(0, 200).sort((a, b) => a.name.localeCompare(b.name))) {
    out.push(`${indent}${file.name}`);
  }
  if (depth <= 0) return;
  for (const sub of dirs.sort((a, b) => a.name.localeCompare(b.name))) {
    out.push(`${indent}${sub.name}/`);
    await walk(path.join(dir, sub.name), depth - 1, out, `${indent}  `);
  }
}

async function collectFiles(dir: string, acc: string[]): Promise<void> {
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!IGNORED_DIRS.has(entry.name)) await collectFiles(full, acc);
    } else if (entry.isFile()) {
      acc.push(full);
    }
  }
}

/** Translate a shell-style glob (`*.ts`) into an anchored regular expression. */
function globToRegExp(glob: string): RegExp {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".");
  return new RegExp(`^${escaped}$`);
}

export function buildTools(ws: Workspace): Map<string, Tool> {
  const tools: Tool[] = [
    {
      name: "read_file",
      description: "Read a UTF-8 text file from the workspace, returned with line numbers.",
      mutating: false,
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path, relative to the workspace root." },
          offset: { type: "integer", description: "1-based first line to read. Default 1." },
          limit: { type: "integer", description: "Maximum lines to return. Default 2000." },
        },
        required: ["path"],
      },
      async handler({ path: p, offset = 1, limit = 2000 }) {
        const full = ws.resolve(p);
        let text: string;
        try {
          text = await fs.readFile(full, "utf8");
        } catch (err: any) {
          throw new ToolError(`cannot read ${p}: ${err.code ?? err.message}`);
        }
        const lines = splitLines(text);
        const start = Math.max(1, offset);
        const window = lines.slice(start - 1, start - 1 + Math.max(1, limit));
        if (window.length === 0) {
          return `(file has ${lines.length} lines; offset ${start} is past the end)`;
        }
        let body = window.map((line, i) => `${String(start + i).padStart(6)}\t${line}`).join("\n");
        const shown = start - 1 + window.length;
        if (shown < lines.length) body += `\n... [${lines.length - shown} more lines]`;
        return truncate(body);
      },
    },
    {
      name: "write_file",
      description:
        "Create a file or replace its entire contents. Prefer edit_file when changing part of an existing file.",
      mutating: true,
      parameters: {
        type: "object",
        properties: {
          path: { type: "string" },
          content: { type: "string", description: "Full contents to write." },
        },
        required: ["path", "content"],
      },
      preview: ({ path: p, content }) => `write ${p} (${splitLines(String(content ?? "")).length} lines)`,
      async handler({ path: p, content }) {
        const full = ws.resolve(p);
        await fs.mkdir(path.dirname(full), { recursive: true });
        const existed = await fs.access(full).then(() => true, () => false);
        await fs.writeFile(full, content, "utf8");
        return `${existed ? "overwrote" : "created"} ${ws.rel(full)} (${splitLines(content).length} lines)`;
      },
    },
    {
      name: "edit_file",
      description:
        "Replace an exact string in a file. old_string must appear exactly once unless replace_all is true. " +
        "Read the file first so the match is exact.",
      mutating: true,
      parameters: {
        type: "object",
        properties: {
          path: { type: "string" },
          old_string: { type: "string", description: "Exact text to replace, including indentation." },
          new_string: { type: "string", description: "Replacement text." },
          replace_all: { type: "boolean", description: "Replace every occurrence. Default false." },
        },
        required: ["path", "old_string", "new_string"],
      },
      preview: ({ path: p, old_string, new_string }) =>
        `edit ${p}\n- ${String(old_string).split("\n")[0].slice(0, 100)}\n+ ${String(new_string).split("\n")[0].slice(0, 100)}`,
      async handler({ path: p, old_string, new_string, replace_all = false }) {
        const full = ws.resolve(p);
        let original: string;
        try {
          original = await fs.readFile(full, "utf8");
        } catch (err: any) {
          throw new ToolError(`cannot read ${p}: ${err.code ?? err.message}`);
        }
        const count = original.split(old_string).length - 1;
        if (count === 0) {
          throw new ToolError("old_string not found in the file; read it again and match exactly");
        }
        if (count > 1 && !replace_all) {
          throw new ToolError(
            `old_string appears ${count} times; add surrounding context to make it unique or pass replace_all=true`,
          );
        }
        const updated = replace_all
          ? original.split(old_string).join(new_string)
          : original.replace(old_string, new_string);
        await fs.writeFile(full, updated, "utf8");
        return `edited ${ws.rel(full)} (${replace_all ? count : 1} replacement(s))`;
      },
    },
    {
      name: "list_files",
      description: "List the directory tree under a path, skipping VCS and dependency directories.",
      mutating: false,
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Directory to list. Default '.'." },
          depth: { type: "integer", description: "How many levels to descend. Default 2." },
        },
      },
      async handler({ path: p = ".", depth = 2 }) {
        const full = ws.resolve(p);
        const out: string[] = [`${ws.rel(full)}/`];
        await walk(full, depth, out, "  ");
        return truncate(out.join("\n"));
      },
    },
    {
      name: "grep",
      description: "Search file contents with a JavaScript regular expression.",
      mutating: false,
      parameters: {
        type: "object",
        properties: {
          pattern: { type: "string", description: "Regular expression." },
          path: { type: "string", description: "File or directory to search. Default '.'." },
          glob: { type: "string", description: "Filename filter, e.g. '*.ts'. Default '*'." },
          max_results: { type: "integer", description: "Default 100." },
        },
        required: ["pattern"],
      },
      async handler({ pattern, path: p = ".", glob = "*", max_results = 100 }) {
        const full = ws.resolve(p);
        let regex: RegExp;
        try {
          regex = new RegExp(pattern);
        } catch (err: any) {
          throw new ToolError(`invalid regex: ${err.message}`);
        }
        const nameFilter = globToRegExp(glob);
        const stat = await fs.stat(full).catch(() => null);
        if (!stat) throw new ToolError(`no such path: ${p}`);

        const candidates: string[] = [];
        if (stat.isFile()) candidates.push(full);
        else await collectFiles(full, candidates);

        const hits: string[] = [];
        for (const file of candidates.sort()) {
          if (hits.length >= max_results) break;
          if (!nameFilter.test(path.basename(file))) continue;
          const text = await fs.readFile(file, "utf8").catch(() => null);
          if (text === null) continue;
          const lines = splitLines(text);
          for (let i = 0; i < lines.length && hits.length < max_results; i++) {
            if (regex.test(lines[i])) {
              hits.push(`${ws.rel(file)}:${i + 1}: ${lines[i].trim().slice(0, 300)}`);
            }
          }
        }
        return truncate(hits.join("\n") || `no matches for /${pattern}/`);
      },
    },
    {
      name: "bash",
      description:
        "Run a shell command in the workspace root and return its output. Use for builds, tests and git. " +
        "Not for reading or editing files -- those have dedicated tools.",
      mutating: true,
      parameters: {
        type: "object",
        properties: {
          command: { type: "string" },
          timeout: { type: "integer", description: "Seconds, max 600. Default 120." },
        },
        required: ["command"],
      },
      preview: ({ command }) => `$ ${command}`,
      async handler({ command, timeout = 120 }) {
        const timeoutMs = Math.min(Math.max(timeout, 1), 600) * 1000;
        try {
          const { stdout, stderr } = await execAsync(command, {
            cwd: ws.root,
            timeout: timeoutMs,
            maxBuffer: 10 * 1024 * 1024,
          });
          const parts = [stdout.trimEnd()];
          if (stderr.trim()) parts.push(`[stderr]\n${stderr.trimEnd()}`);
          return truncate(parts.filter(Boolean).join("\n") || "(no output)");
        } catch (err: any) {
          if (err.killed || err.signal === "SIGTERM") {
            throw new ToolError(`command timed out after ${timeout}s`);
          }
          // A non-zero exit is information for the model, not a harness failure.
          const parts = [];
          if (err.stdout?.trim()) parts.push(err.stdout.trimEnd());
          if (err.stderr?.trim()) parts.push(`[stderr]\n${err.stderr.trimEnd()}`);
          parts.push(`[exit code ${err.code ?? "unknown"}]`);
          return truncate(parts.join("\n"));
        }
      },
    },
  ];

  return new Map(tools.map((tool) => [tool.name, tool]));
}
