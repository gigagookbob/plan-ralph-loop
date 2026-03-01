[한국어](README.ko.md)

# plansmith

A structured planning plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Progresses through phases — understand, explore, alternatives, draft, critique, revise — with validation at each step to produce high-quality implementation plans. Default: 8 phases with 2 critique-revise cycles.

Based on the [Ralph Loop](https://ghuntley.com/ralph/) technique — but instead of iterating on code until tests pass, it progresses through **distinct planning phases** until a quality gate is satisfied.

## Why?

Working with Claude Code on complex tasks, there's a common pattern: jump straight into writing code, lose direction halfway, revert, start over. Using plan mode helps for simple tasks — but for complex ones, even a carefully written plan has gaps.

In my experience, asking the AI to "review your plan again" does surface issues — missing edge cases, wrong step ordering, overlooked dependencies. The problem is that **these issues keep coming up no matter how many times you ask**. Each review pass catches some problems but introduces or misses others. A single prompt that says "plan and critique and revise" tends to produce a plan that *looks* thorough but hasn't actually been stress-tested.

This matches what [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023) found: an explicit generate → feedback → refine loop improves output by ~20% over single-shot generation — but only when each step has a distinct role. [Prompt repetition](https://arxiv.org/abs/2512.14982) can help marginally, but role separation is what actually matters. [LLMs Can Plan Only If We Tell Them](https://arxiv.org/abs/2501.13545) (ICLR 2025) showed the same thing from a different angle — LLMs can plan well, but only when you tell them *how* to plan.

The fix: **force different work at each stage.** Explore the code before planning. Draft before critiquing. Critique before revising. Each phase has **negative validation** — the explore phase rejects plan headings, the critique phase rejects finalization attempts. You can't collapse everything into one pass. This is also a form of [test-time compute scaling](https://arxiv.org/abs/2408.03314) (ICLR 2025 Oral) — more structured inference beats a bigger model.

### Ideas Borrowed From

| Technique | Paper | How it's applied |
|-----------|-------|-----------------|
| **Multi-iteration refinement** | [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023) | Default 2 critique-revise cycles (`--refine-iterations`) |
| **Principle-based critique** | [Constitutional AI](https://arxiv.org/abs/2212.08073) (Anthropic) | 12 principles (P1-P12) with PASS/FAIL evaluation |
| **Session memory** | [Reflexion](https://arxiv.org/abs/2303.11366) (NeurIPS 2023) | FAIL items persist across planning sessions |
| **Step decomposition** | [Least-to-Most](https://arxiv.org/abs/2205.10625) (ICLR 2023) | Steps ordered simple → complex with explicit dependencies |
| **Structured planning activation** | [LLMs Can Plan Only If We Tell Them](https://arxiv.org/abs/2501.13545) (ICLR 2025) | Phase-based prompting activates latent planning capabilities |
| **Test-time compute scaling** | [Scaling Test-Time Compute](https://arxiv.org/abs/2408.03314) (ICLR 2025 Oral) | Multi-phase inference outperforms larger single-shot models |
| **Structured self-correction** | [SCoRe](https://arxiv.org/abs/2409.12917) (ICLR 2025 Oral) | Multi-turn self-correction yields 15.6% improvement on MATH |

## How It Works

```
/plansmith:plan Design auth system
```

Default flow: 8 phases with 2 critique-revise cycles.

| Phase | What Claude does | What's validated |
|-------|-----------------|-----------------|
| **Understand** | Analyzes the problem, defines success criteria/constraints/assumptions | 3+ numbered items, 2+ understanding keywords, no plan headings |
| **Explore** | Reads codebase, lists files/architecture/patterns. Past session learnings injected (Reflexion). | 2+ file path references. Must NOT contain plan headings. |
| **Alternatives** | Compares 2-3 approaches with pros/cons, chooses one | 2+ options, recommendation keyword, pros/cons keyword |
| **Draft** | Writes complete plan with all 7 required sections. Steps ordered simple → complex (Least-to-Most). | All section headings must be present |
| **Critique (×2)** | Evaluates plan against 12 principles (P1-P12) with PASS/FAIL. Perspective rotates per round: technical → maintainability. | Must NOT contain `<promise>` tag. 3+ numbered items, 6+ principle evidence (P-refs + PASS/FAIL combined). |
| **Revise (×2)** | Rewrites plan addressing every critique item | Promise tag + all sections = done (final round only) |

Each phase produces different output because the validation prevents collapsing phases together.

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

## Plansmith vs Plan Mode — Real-World Comparison

Same task — *"Implement offline mode with local card data caching, offline deck editing, and background sync"* — on a real Flutter/Supabase project ([Grandline](https://github.com/gigagookbob/grandline)). One run with Plansmith, one with Claude Code's built-in plan mode.

### At a Glance

| | Plansmith v3.0.0 | Plan Mode |
|---|-----------------|-----------|
| **Time** | ~24 min | ~5 min |
| **Output** | 727 lines | 331 lines |
| **Self-critique rounds** | 2 rounds (5 FAILs → fix → 2 FAILs → fix) | 0 |
| **Issues caught before coding** | 7 | 0 |

### The Critical Difference: Technology Choice

| | Plansmith | Plan Mode |
|---|-----------|-----------|
| **Local DB** | **sqflite** (raw SQL) | **drift** (ORM + codegen) |
| **Reasoning** | Explored 3 options (sqflite, drift, Hive). Rejected drift because project's CLAUDE.md says "codegen not used — analyzer_plugin compatibility issues." drift uses analyzer_plugin. | "Fits existing build_runner pipeline" |
| **Project policy compliance** | Yes | **No — violates stated policy** |

In practice, this would mean hitting an analyzer_plugin conflict mid-implementation, then rolling back to re-plan with a different DB. The alternatives phase caught it before any code was written.

### What Self-Critique Found

The two critique-revise rounds found 7 issues that plan mode missed entirely:

1. **Step ordering bug**: A freezed field addition was placed after the step that needed it
2. **Offline userId problem**: No strategy for getting userId when Supabase session might be expired
3. **Provider recreation storm**: `ref.watch(isOnlineProvider)` would recreate the repository on every network change
4. **SQLite boolean mismatch**: INTEGER(0/1) vs Dart bool — no conversion helper planned
5. **Duplicate sync triggers**: Rapid network toggles would fire multiple concurrent syncs
6. **Partial failure gap**: Server deck creation succeeds but card upload fails → orphaned empty deck
7. **toJson key mapping**: Unverified assumption that Freezed's toJson() keys match SQLite column names

### Plan Quality Comparison

| Criterion | Plansmith | Plan Mode |
|-----------|-----------|-----------|
| **Effort estimates** | Every step with line counts (e.g., "Step 5 [L — 10 filter conditions + 5 methods, ~280 lines]") | None |
| **Step dependencies** | Explicit (e.g., "Depends on: Step 2, Step 3") | Implicit (phase ordering only) |
| **Edge cases** | 3+ per component (DB corruption, disk full, captive portal WiFi, FK conflicts...) | Minimal |
| **Breaking changes** | Per-step analysis with affected call sites | Brief mentions |
| **Error handling** | `_withFallback<T>` pattern, transaction rollback, sync failure isolation, debounce + guard | retry count (max 3) |
| **Test plan** | 3 unit test files + setUp code + 8 test cases + mocktail + manual scenarios + curl commands | 5 manual scenarios |
| **Risk analysis** | 8 risks with severity + mitigation | None |

### Where Plan Mode Wins

- **5x faster** (~5 min vs ~24 min)
- **SyncQueue table**: Separate queue table for sync operations — more flexible than Plansmith's sync_status field approach
- **Cleaner structure**: `lib/core/offline/` directory groups all offline code together

### When to Use Which

| Situation | Recommendation |
|-----------|---------------|
| Complex architecture changes, strict project constraints, high cost of mistakes | **Plansmith** |
| Quick prototyping, simple features, exploratory work | **Plan Mode** |
| Team projects where the plan needs to be reviewed by others | **Plansmith** (self-documented quality) |

### Cost Considerations

Plansmith uses significantly more tokens than single-shot planning — the 8-phase loop with validation retries generates 10-20+ API round-trips per session. In the test above, ~24 minutes vs ~5 minutes for plan mode. Worth it for complex tasks; overkill for simple ones.

## Commands

### `/plansmith:plan <PROMPT> [OPTIONS]`

| Option | Default | Description |
|--------|---------|-------------|
| `--max-phases <n>` | 10 | Maximum phase transitions before auto-stop |
| `--max-iterations <n>` | 10 | Alias for `--max-phases` |
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

## Project Structure

```
plansmith/
├── commands/           # Slash command definitions (plan, cancel, help)
├── hooks/
│   ├── hooks.json      # Hook registration (stop, pretooluse)
│   ├── stop-hook.sh    # Phase machine dispatcher
│   ├── pretooluse-hook.sh  # Tool blocking during planning
│   ├── lib/common.sh   # Shared helper functions
│   └── phases/         # Per-phase validation (understand, explore, ...)
├── scripts/            # Setup, save, cancel scripts
├── templates/          # Plan rubric + 12 critique principles
└── tests/              # Phase validation tests (36 unit + 32 integration)
```

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
