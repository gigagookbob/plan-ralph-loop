---
description: "Show Plansmith help"
---

# Plansmith Help

Please explain the following to the user:

## What is Plansmith?

A planning-focused variant of [Ralph Loop](https://ghuntley.com/ralph/). Instead of iterating on code until tests pass, it progresses through **structured phases** to produce a high-quality plan.

**Phase sequence** (default: 8 phases with 2 critique-revise cycles):
1. **UNDERSTAND** — Analyze the problem. Define success criteria, constraints, assumptions.
2. **EXPLORE** — Read the codebase, list findings. No plan writing allowed. Session memory injected (Reflexion).
3. **ALTERNATIVES** — Compare 2-3 approaches with pros/cons. Choose one.
4. **DRAFT** — Write a complete plan with Least-to-Most step ordering.
5. **CRITIQUE (round 1)** — Evaluate against 12 principles (P1-P12) with PASS/FAIL. Technical perspective.
6. **REVISE (round 1)** — Address all critique items. Do not finalize yet.
7. **CRITIQUE (round 2)** — Re-evaluate from user/maintainability perspective.
8. **REVISE (round 2)** — Final revision, output `<promise>PLAN_OK</promise>` to finalize.

Each phase has validation that prevents skipping ahead. The final plan is saved to `.claude/plansmith-output.local.md`.

**Ideas borrowed from:**
- Self-Refine (Madaan et al., NeurIPS 2023) — multi-iteration critique-revise
- Constitutional AI (Bai et al., Anthropic) — principle-based structured critique
- Reflexion (Shinn et al., NeurIPS 2023) — persistent session memory
- Least-to-Most (Zhou et al., ICLR 2023) — progressive step decomposition

## Commands

### /plansmith:plan PROMPT [OPTIONS]

Start a planning loop.

**Options:**
| Option | Default | Description |
|--------|---------|-------------|
| `--max-phases N` | 10 | Maximum phase transitions |
| `--max-iterations N` | 10 | Alias for `--max-phases` |
| `--refine-iterations N` | 2 | Critique-revise cycles, 1-4 (Self-Refine) |
| `--skip-understand` | (understand ON) | Skip the understand phase |
| `--skip-explore` | (explore ON) | Skip the explore phase |
| `--skip-alternatives` | (alternatives ON) | Skip the alternatives phase |
| `--phases "a,b,c"` | (dynamic) | Custom phase sequence (overrides --refine-iterations) |
| `--open-critique` | (principles ON) | Use open-ended critique instead of principle-based |
| `--no-memory` | (memory ON) | Disable session memory (Reflexion) |
| `--clear-memory` | N/A | Clear accumulated session memories |
| `--no-block-tools` | (blocking ON) | Disable tool blocking |
| `--required-sections "A,B,C"` | Goal,Scope,... | Required section headings |
| `--completion-promise TEXT` | PLAN_OK | Completion promise value |

**Examples:**
```
/plansmith:plan Design the authentication system
/plansmith:plan Plan API refactor --skip-understand --skip-explore
/plansmith:plan Design caching layer --refine-iterations 3
/plansmith:plan Quick plan --refine-iterations 1 --open-critique
```

### /plansmith:cancel

Cancel an active planning loop.

## Phase Validation

| Phase | Passes when... | Fails when... |
|-------|----------------|---------------|
| understand | 3+ numbered items, 2+ understanding keywords, no plan headings | Plan headings found, or insufficient analysis |
| explore | 2+ file path references, no plan headings | Plan headings found, or no file references |
| alternatives | 2+ options, recommendation keyword, pros/cons keyword, no promise/plan headings | Missing options, recommendation, or trade-off analysis |
| draft | All required section headings present | Sections missing |
| critique | 3+ numbered items, no `<promise>` tag, 6+ principle refs (principles mode) | Fewer than 3 items, promise present, or insufficient principle evaluation |
| revise | Promise tag + all sections (final round only) | Promise missing or sections missing |

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
| `.claude/plansmith-memory.local.md` | Session memory for Reflexion (persists across sessions) |
