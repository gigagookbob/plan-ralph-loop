# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

plansmith is a Claude Code plugin that progresses through structured planning phases (explore → draft → critique → revise) with per-phase validation. Inspired by [Ralph Loop](https://ghuntley.com/ralph/), but instead of iterating on code until tests pass, it produces a "ready-to-start" implementation plan through distinct phases.

## Architecture

Three core mechanisms:

1. **Commands** (`commands/`): Slash command definitions (YAML frontmatter + Markdown prompts)
2. **Hooks** (`hooks/`): Stop hook (phase machine) + PreToolUse hook (tool blocking)
3. **Scripts** (`scripts/`): State management, argument parsing, plan saving

### Execution Flow

```
/plansmith:plan → setup.sh (creates state file)
  → Phase 1: explore (read codebase, list findings)
  → Phase 2: draft (write complete plan)
  → Phase 3: critique (list numbered weaknesses)
  → Phase 4: revise (address critiques, finalize)
  → save.sh → .claude/plansmith-output.local.md
```

### Phase Machine (stop-hook.sh)

Each phase has distinct validation:

| Phase | Passes when | Fails when |
|-------|-------------|------------|
| explore | File paths listed, no plan headings | Plan headings found (negative validation) |
| draft | All required section headings present | Sections missing |
| critique | 3+ numbered items, no `<promise>` tag | Promise present (negative validation), <3 items |
| revise | Promise tag + all sections | Promise missing or sections missing |

Key insight: **negative validation** (checking what must NOT be in the output) prevents Claude from collapsing phases together.

### State File

`.claude/plansmith.local.md` with YAML frontmatter:
```yaml
active: true
phase: explore
phase_index: 0
max_phases: 10
phases: "explore,draft,critique,revise"
completion_promise: "PLAN_OK"
block_tools: true
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
```

Frontmatter parsed with `sed`, updated with `sed_inplace()` helper (macOS + Linux compatible).

### Tool Blocking (pretooluse-hook.sh)

- Edit/Write/NotebookEdit: always blocked
- Bash: read-only allowlist. Pipes/semicolons/redirects blocked. Plugin's own scripts exempted.
- Read/Glob/Grep/WebSearch/WebFetch/Task: always allowed

## Scripting Conventions

- `#!/bin/bash` + `set -euo pipefail`
- Portable sed: `sed_inplace()` using temp file + `mv` (not `sed -i`)
- Hook JSON output: always use `jq -n --arg` (injection-safe)
- Hook input: prefer `last_assistant_message` from stdin over transcript JSONL parsing
- Commands: explicit "Run this using the Bash tool" instruction (not ```` !` auto-execute)

## Dependencies

System tools only (no npm/pip):
- `jq`: hook I/O JSON processing (required)
- `perl`: promise tag extraction (required)
- `bash`, `sed`, `grep`, `awk`: script infrastructure

## Key Files

| File | Role |
|------|------|
| `hooks/stop-hook.sh` | Phase machine + quality gate (core logic) |
| `hooks/pretooluse-hook.sh` | Tool blocking during planning |
| `scripts/setup.sh` | CLI arg parsing + state file creation |
| `scripts/save.sh` | Final plan saving |
| `scripts/cancel.sh` | Loop cancellation |
| `templates/plan-rubric.md` | Quality rubric template |

## Known Limitations

- Prompt containing `---` on its own line breaks YAML frontmatter parsing
- Bash allowlist allows quoted special chars (e.g., `grep 'a&b'`), but unclosed quotes or complex escape patterns may still be blocked
- `--completion-promise` values with double quotes may break YAML parsing
