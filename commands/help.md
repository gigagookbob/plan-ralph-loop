---
description: "Show Plansmith help"
---

# Plansmith Help

Please explain the following to the user:

## What is Plansmith?

A planning-focused variant of [Ralph Loop](https://ghuntley.com/ralph/). Instead of iterating on code until tests pass, it progresses through **structured phases** to produce a high-quality plan.

**Phase sequence:**
1. **EXPLORE** — Read the codebase, list findings. No plan writing allowed.
2. **DRAFT** — Write a complete plan with all required sections.
3. **CRITIQUE** — List specific numbered weaknesses. No rewriting or finalizing.
4. **REVISE** — Address all critiques, output `<promise>PLAN_OK</promise>` to finalize.

Each phase has validation that prevents skipping ahead. The final plan is saved to `.claude/plansmith-output.local.md`.

## Commands

### /plansmith:plan PROMPT [OPTIONS]

Start a planning loop.

**Options:**
| Option | Default | Description |
|--------|---------|-------------|
| `--max-phases N` | 10 | Maximum phase transitions |
| `--skip-explore` | (explore ON) | Skip the explore phase |
| `--phases "a,b,c"` | explore,draft,critique,revise | Custom phase sequence |
| `--no-block-tools` | (blocking ON) | Disable tool blocking |
| `--required-sections "A,B,C"` | Goal,Scope,... | Required section headings |
| `--completion-promise TEXT` | PLAN_OK | Completion promise value |

**Examples:**
```
/plansmith:plan Design the authentication system
/plansmith:plan Plan API refactor --skip-explore
/plansmith:plan Design caching layer --max-phases 8
```

### /plansmith:cancel

Cancel an active planning loop.

## Phase Validation

| Phase | Passes when... | Fails when... |
|-------|----------------|---------------|
| explore | File paths listed, no plan headings | Plan headings found, or no file references |
| draft | All required section headings present | Sections missing |
| critique | 3+ numbered items, no `<promise>` tag | Fewer than 3 items, or promise present |
| revise | Promise tag + all sections present | Promise missing or sections missing |

## Tool Blocking

By default, the following tools are blocked during planning:
- **Edit, Write, NotebookEdit**: Always blocked
- **Bash**: Read-only single commands only (no pipes, semicolons, redirects)
- **Read, Glob, Grep, WebSearch, WebFetch, Task**: Always allowed

Use `--no-block-tools` to disable.

## Files

| File | Purpose |
|------|---------|
| `.claude/plansmith.local.md` | Loop state (phase, config) |
| `.claude/plansmith-output.local.md` | Final approved plan |
