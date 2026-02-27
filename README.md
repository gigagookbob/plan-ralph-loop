[한국어](README.ko.md)

# plansmith

A research-backed planning plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Progresses through structured phases — understand, explore, alternatives, draft, critique, revise — with validation at each step to produce high-quality implementation plans. Default: 8 phases with 2 critique-revise cycles.

Based on the [Ralph Loop](https://ghuntley.com/ralph/) technique — but instead of iterating on code until tests pass, it progresses through **distinct planning phases** until a quality gate is satisfied.

## Why?

Working with Claude Code on complex tasks, there's a common pattern: jump straight into writing code, lose direction halfway, revert, start over. "Just plan first" sounds obvious — but AI rarely produces a genuinely good plan on the first attempt.

The problem is deeper than "iterate more." If you ask an LLM to "keep improving your plan," it produces the same quality of output each time — it always tries to write a complete answer. Simply repeating the same prompt doesn't help.

The solution: **force fundamentally different work at each stage.** Explore the code before planning. Draft before critiquing. Critique before revising. Each phase has **negative validation** — the explore phase rejects plan headings, the critique phase rejects finalization attempts. This makes it structurally impossible to skip ahead.

### Research Foundations

Plansmith's phase architecture is grounded in peer-reviewed research:

| Technique | Paper | How it's applied |
|-----------|-------|-----------------|
| **Multi-iteration refinement** | [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023) | Default 2 critique-revise cycles (`--refine-iterations`) |
| **Principle-based critique** | [Constitutional AI](https://arxiv.org/abs/2212.08073) (Anthropic) | 12 principles (P1-P12) with PASS/FAIL evaluation |
| **Session memory** | [Reflexion](https://arxiv.org/abs/2303.11366) (NeurIPS 2023) | FAIL items persist across planning sessions |
| **Step decomposition** | [Least-to-Most](https://arxiv.org/abs/2205.10625) (ICLR 2023) | Steps ordered simple → complex with explicit dependencies |

## How It Works

```
/plansmith:plan Design auth system
```

Default flow: 8 phases with 2 critique-revise cycles.

| Phase | What Claude does | What's validated |
|-------|-----------------|-----------------|
| **Understand** | Analyzes the problem, defines success criteria/constraints/assumptions | 3+ numbered items, 2+ understanding keywords, no plan headings |
| **Explore** | Reads codebase, lists files/architecture/patterns. Past session learnings injected (Reflexion). | Must NOT contain plan headings (`## Goal`, etc.) |
| **Alternatives** | Compares 2-3 approaches with pros/cons, chooses one | 2+ options, recommendation keyword, pros/cons keyword |
| **Draft** | Writes complete plan with all 7 required sections. Steps ordered simple → complex (Least-to-Most). | All section headings must be present |
| **Critique (×2)** | Evaluates plan against 12 principles (P1-P12) with PASS/FAIL. Perspective rotates per round: technical → maintainability. | Must NOT contain `<promise>` tag. 3+ numbered items, 6+ principle references. |
| **Revise (×2)** | Rewrites plan addressing every critique item | Promise tag + all sections = done (final round only) |

Each phase produces genuinely different output because the validation prevents collapsing phases together.

```
/plansmith:plan ─→ understand ─→ explore ─→ alternatives ─→ draft ─→ critique ─→ revise ─→ critique ─→ revise ─→ saved!
                      │            │            │              │          │          │          │          │
                   (fail?)      (fail?)      (fail?)        (fail?)    (fail?)    (fail?)    (fail?)    (fail?)
                      ↓            ↓            ↓              ↓          ↓          ↓          ↓          ↓
                   retry        retry        retry          retry      retry      retry      retry      iterate
```

When complete, the final plan is saved to `.claude/plansmith-output.local.md`.

## Quick Start

```bash
# Start a planning loop (default: 8 phases, 2 critique-revise cycles)
/plansmith:plan Design the authentication system

# Fewer iterations for simpler tasks
/plansmith:plan Fix the bug --refine-iterations 1

# Skip understand+explore when problem and code are known
/plansmith:plan Plan the refactor --skip-understand --skip-explore

# Use open-ended critique instead of principle-based
/plansmith:plan Design caching --open-critique

# Cancel if needed
/plansmith:cancel
```

Once you run `/plansmith:plan`, the loop runs automatically — no manual intervention needed. The Stop hook intercepts each response, validates it against the current phase's rules, and injects the next phase's prompt. If validation fails, Claude automatically retries with feedback.

## How It Differs from Ralph Loop

| | ralph-loop | plansmith |
|--|-----------|-----------------|
| **Structure** | Same prompt repeated | Distinct phases with different prompts |
| **Validation** | Single promise tag | Per-phase validation (positive + negative) |
| **Tool blocking** | None (full access) | Edit/Write/Bash blocked during planning |
| **Self-critique** | Optional | Dedicated critique phase with 12 principles (cannot skip) |
| **Iteration** | Until tests pass | Configurable critique-revise cycles (Self-Refine) |
| **Memory** | None | Session memory across runs (Reflexion) |
| **Output** | Modified files | Saved plan file (`.claude/plansmith-output.local.md`) |

## Commands

### `/plansmith:plan <PROMPT> [OPTIONS]`

| Option | Default | Description |
|--------|---------|-------------|
| `--max-phases <n>` | 10 | Maximum phase transitions before auto-stop |
| `--refine-iterations <n>` | 2 | Critique-revise cycles, 1-4 (Self-Refine) |
| `--skip-understand` | (understand ON) | Skip the understand phase |
| `--skip-explore` | (explore ON) | Skip the explore phase |
| `--skip-alternatives` | (alternatives ON) | Skip the alternatives phase |
| `--open-critique` | (principles ON) | Open-ended critique instead of principle-based |
| `--no-memory` | (memory ON) | Disable session memory (Reflexion) |
| `--clear-memory` | — | Clear accumulated session memories |
| `--phases "a,b,c"` | (dynamic) | Custom phase sequence (overrides --refine-iterations) |
| `--no-block-tools` | (blocking ON) | Disable tool blocking |
| `--required-sections "A,B,C"` | Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions | Required section headings |
| `--completion-promise <text>` | PLAN_OK | Promise tag value |

### `/plansmith:cancel`

Cancel an active planning loop.

### `/plansmith:help`

Show detailed help.

## Quality Gate

The **revise** phase uses a 2-phase quality gate:

1. **Promise Tag**: `<promise>PLAN_OK</promise>` must be present
2. **Required Sections**: All section headings must exist

### Default Required Sections

Section headings are accepted in **both English and Korean** — you can write your entire plan in Korean if you prefer.

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

When enabled (default):

| Tool | Policy |
|------|--------|
| **Edit, Write, NotebookEdit** | Always blocked |
| **Bash** | Read-only single commands only. Pipes, semicolons, redirects blocked. |
| **Read, Glob, Grep, WebSearch, WebFetch, Task** | Always allowed |

Use `--no-block-tools` to disable.

## When to Use

**Good for:**
- Complex tasks requiring architectural planning before coding
- Multi-file changes that need dependency analysis
- When you want Claude to explore the codebase before making changes
- Tasks where "plan first, execute later" reduces rework

**Not good for:**
- Simple, well-defined tasks (just do them directly)
- Tasks with no codebase to explore (use `--skip-explore`)
- When you already have a clear plan

## Output

When the loop completes, the final plan is saved with `<promise>` tags stripped:

```
.claude/plansmith-output.local.md        — final plan
.claude/plansmith-memory.local.md        — session memory (Reflexion, persists across runs)
```

The plan file includes YAML frontmatter with metadata:

```yaml
---
generated_at: "2026-02-27T12:00:00Z"
exit_reason: "completed"        # or "max_phases_reached"
---
```

If the loop hits `--max-phases` before completion, the current output is still saved with `exit_reason: "max_phases_reached"`.

## Known Limitations

- **Prompt containing `---`**: May break YAML frontmatter parsing. Avoid `---` on its own line in prompts.
- **Tool blocking is conservative**: `&`, `>`, `|`, `;` in Bash arguments are blocked. Use `--no-block-tools` if needed.
- **Completion promise with quotes**: Avoid `"` in `--completion-promise` values.

## Compatibility

Uses a separate state file (`.claude/plansmith.local.md`) from the official `ralph-loop` plugin. Both can be installed simultaneously.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` (JSON processing)
- `perl` (promise tag extraction)

## Installation

Add the marketplace and install:

```shell
/plugin marketplace add gigagookbob/plansmith
/plugin install plansmith@plansmith-local
```

To enable for a team project, add to your project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "plansmith-local": {
      "source": {
        "source": "github",
        "repo": "gigagookbob/plansmith"
      }
    }
  },
  "enabledPlugins": {
    "plansmith@plansmith-local": true
  }
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
