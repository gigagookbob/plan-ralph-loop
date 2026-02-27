# plan-ralph-loop

A planning-focused iterative loop plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Forces Claude into read-only planning mode with structured self-critique, quality gates, and tool blocking until the plan meets a rubric.

Based on the [Ralph Loop](https://ghuntley.com/ralph/) technique — but instead of iterating on code until tests pass, it iterates on **plans** until all required sections are present and the quality gate is satisfied.

## How It Differs from Ralph Loop

| | ralph-loop | plan-ralph-loop |
|--|-----------|-----------------|
| **Purpose** | Iterate on code until task complete | Iterate on *plans* until quality gate passes |
| **Tool blocking** | None (full access) | Edit/Write/Bash blocked during planning |
| **Completion** | Single promise tag | Promise tag + required section verification |
| **Self-critique** | Optional | Built-in every iteration |
| **Output** | Modified files | Saved plan file (`.claude/plan-output.local.md`) |

## Quick Start

```bash
# Load the plugin
claude --plugin-dir /path/to/plan-ralph-loop

# Start a planning loop (note: use the full command name)
/plan-ralph-loop:plan-ralph Design the authentication system --max-iterations 10

# Cancel if needed
/plan-ralph-loop:cancel-plan-ralph
```

Claude will:
1. Run the setup script (creates `.claude/plan-ralph.local.md` state file)
2. Explore the codebase in read-only mode
3. Draft a structured plan with all required sections
4. **Iteration 1 always forces self-critique** — even if the draft looks complete
5. On iteration 2+, if `<promise>PLAN_OK</promise>` is present and all sections exist, the loop ends
6. Final plan is saved to `.claude/plan-output.local.md`

## Features

- **Minimum 2 Iterations**: First iteration is always a draft — self-critique is forced even if the plan looks complete
- **2-Phase Quality Gate**: Checks both the `<promise>` tag AND required section headings
- **Tool Blocking**: Prevents file modifications during planning (Edit, Write, NotebookEdit, dangerous Bash)
- **Self-Critique Loop**: Each iteration injects instructions to review and improve the previous plan
- **Bilingual Section Support**: Recognizes both English and Korean section headings (e.g., `## Goal` = `## 목표`)
- **Auto-Save**: Final approved plan is saved to `.claude/plan-output.local.md`
- **Configurable**: Custom sections, iteration limits, tool blocking toggle

## Commands

### `/plan-ralph <PROMPT> [OPTIONS]`

Start a planning loop.

| Option | Default | Description |
|--------|---------|-------------|
| `--max-iterations <n>` | 20 | Maximum planning iterations before auto-stop |
| `--no-block-tools` | (blocking ON) | Disable tool blocking during planning |
| `--required-sections "A,B,C"` | Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions | Comma-separated required section headings |
| `--completion-promise <text>` | PLAN_OK | Promise tag value to signal completion |

### `/cancel-plan-ralph`

Cancel an active planning loop.

### `/help` (or `/plan-ralph-loop:help`)

Show detailed help and usage examples.

## Quality Gate

The loop only terminates when **both** conditions are met:

1. **Promise Tag**: Claude outputs `<promise>PLAN_OK</promise>` at the end of its response
2. **Required Sections**: All required section headings are present in the plan

If Claude outputs the promise tag but sections are missing, the loop continues with a message listing the missing sections.

### Default Required Sections

| English | Korean |
|---------|--------|
| `## Goal` | `## 목표` |
| `## Scope` | `## 범위` |
| `## Non-Scope` | `## 비범위` |
| `## Steps` | `## 단계별 계획` |
| `## Verification` | `## 검증` |
| `## Risks` | `## 리스크` |
| `## Open Questions` | `## 오픈 질문` |

## Tool Blocking

When enabled (default), the following tools are blocked during planning:

| Tool | Policy |
|------|--------|
| **Edit, Write, NotebookEdit** | Always blocked |
| **Bash** | Read-only commands only (`ls`, `cat`, `grep`, `git log`, `find`, etc.). Compound commands with pipes/semicolons are blocked. |
| **Read, Glob, Grep, WebSearch, WebFetch, Task** | Always allowed |

Use `--no-block-tools` to disable tool blocking for a lighter-weight planning loop.

## Files

| File | Purpose |
|------|---------|
| `.claude/plan-ralph.local.md` | Loop state (active flag, iteration count, config) |
| `.claude/plan-output.local.md` | Final approved plan output |

## When to Use

**Good for:**
- Complex tasks requiring architectural planning before coding
- Tasks where "plan first, execute later" reduces rework
- Multi-file changes that need dependency analysis
- When you want Claude to explore the codebase before making changes

**Not good for:**
- Simple, well-defined tasks (just do them directly)
- Tasks with no codebase to explore
- When you already have a clear plan

## Real-World Example

Tested on a simple Express TODO API project. Task: *"Add JWT authentication"*

```
/plan-ralph-loop:plan-ralph Add JWT auth to this TODO API --max-iterations 5
```

**Iteration 1** (draft — 6,855 chars): Claude explored `src/index.js`, `src/middleware.js`, `package.json`, then produced a structured plan with all 7 sections. The stop hook forced self-critique regardless.

**Iteration 2** (improved — 13,523 chars): Claude self-critiqued and found 8 issues in its own draft:
- Step ordering was wrong (`config.js` was created last but imported by earlier steps)
- No effort estimates (S/M/L) — rubric requires them
- Missing edge cases (`NaN` from `parseInt`, password length validation)
- Breaking change not called out (existing clients would get 401)
- Verification curl commands weren't copy-pasteable
- Architecture improved: changed from `userId` field on flat array to `todosByUser` per-user store

Quality gate passed: all 7 sections present + `<promise>PLAN_OK</promise>` → plan saved to `.claude/plan-output.local.md`.

**Result**: The self-critique loop produced a meaningfully better plan — not just longer, but structurally improved with concrete fixes the first draft missed.

## Known Limitations

- **Prompt containing `---`**: If your planning prompt contains `---` on a line by itself, it may break the YAML frontmatter parsing in the state file. Avoid using `---` as a separator in your prompt text.
- **Tool blocking is conservative**: Bash commands containing `&`, `>`, `|`, or `;` anywhere (even in arguments like `grep 'a&b'`) are blocked during planning. Use `--no-block-tools` if this is too restrictive for your workflow.
- **Completion promise with quotes**: Avoid double quotes inside `--completion-promise` values as they may break YAML parsing in the state file.

## Compatibility

This plugin uses a separate state file (`.claude/plan-ralph.local.md`) from the official `ralph-loop` plugin (`.claude/ralph-loop.local.md`). Both can be installed simultaneously without conflict.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (JSON processing)
- `perl` (promise tag extraction)

## Installation

```bash
# Clone the repository
git clone https://github.com/gigagookbob/plan-ralph-loop.git

# Use with Claude Code
claude --plugin-dir /path/to/plan-ralph-loop
```

## License

MIT License. See [LICENSE](LICENSE) for details.
