---
description: "Show Plan Ralph Loop help"
---

# Plan Ralph Loop Help

Please explain the following to the user:

## What is Plan Ralph Loop?

A planning-focused variant of [Ralph Loop](https://ghuntley.com/ralph/). Instead of iterating on code until tests pass, it iterates on **plans** until a quality gate is satisfied.

**How it works:**
1. Claude explores the codebase (read-only) and drafts a structured plan
2. The Stop hook intercepts exit and injects a self-critique prompt
3. Claude reviews and improves the plan each iteration
4. When the quality gate passes (required sections + promise tag), the loop ends
5. The final plan is saved to `.claude/plan-output.local.md`

## Commands

### /plan-ralph PROMPT [OPTIONS]

Start a planning loop.

**Options:**
| Option | Default | Description |
|--------|---------|-------------|
| `--max-iterations N` | 20 | Maximum planning iterations |
| `--no-block-tools` | (blocking ON) | Disable tool blocking |
| `--required-sections "A,B,C"` | Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions | Required section headings |
| `--completion-promise TEXT` | PLAN_OK | Completion promise value |

**Examples:**
```
/plan-ralph Design the authentication system
/plan-ralph Design the caching layer --max-iterations 10
/plan-ralph Plan database migration --no-block-tools
/plan-ralph Refactor the API --required-sections "Goal,Steps,Risks"
```

### /cancel-plan-ralph

Cancel an active planning loop.

## Quality Gate

The loop terminates when **both** conditions are met:

1. **Promise tag**: Response ends with `<promise>PLAN_OK</promise>`
2. **Required sections**: All required section headings are present

If the promise tag is present but sections are missing, the loop continues.

**Bilingual support**: Both English and Korean section headings are recognized (e.g., `## Goal` = `## 목표`).

## Tool Blocking

By default, the following tools are blocked during planning:
- **Edit, Write, NotebookEdit**: Always blocked
- **Bash**: Read-only single commands only (no pipes, semicolons, or chains)
- **Read, Glob, Grep, WebSearch, WebFetch, Task**: Always allowed

Use `--no-block-tools` to disable.

## Files

| File | Purpose |
|------|---------|
| `.claude/plan-ralph.local.md` | Loop state (active flag, iteration, config) |
| `.claude/plan-output.local.md` | Final approved plan output |

## Monitoring

```bash
# Check current iteration
grep '^iteration:' .claude/plan-ralph.local.md

# View full state
head -10 .claude/plan-ralph.local.md
```
