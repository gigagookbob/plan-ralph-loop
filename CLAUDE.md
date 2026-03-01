# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

plansmith is a Claude Code plugin that progresses through structured planning phases with per-phase validation. Inspired by [Ralph Loop](https://ghuntley.com/ralph/), but instead of iterating on code until tests pass, it produces a "ready-to-start" implementation plan through distinct phases.

**Ideas borrowed from:**
- [Self-Refine](https://arxiv.org/abs/2303.17651) (NeurIPS 2023) — multi-iteration critique-revise (default: 2 cycles)
- [Constitutional AI](https://arxiv.org/abs/2212.08073) (Anthropic) — principle-based structured critique (12 principles, PASS/FAIL)
- [Reflexion](https://arxiv.org/abs/2303.11366) (NeurIPS 2023) — persistent session memory across planning runs
- [Least-to-Most](https://arxiv.org/abs/2205.10625) (ICLR 2023) — progressive step decomposition in draft phase
- [LLMs Can Plan Only If We Tell Them](https://arxiv.org/abs/2501.13545) (ICLR 2025) — structured prompting activates latent planning
- [Scaling Test-Time Compute](https://arxiv.org/abs/2408.03314) (ICLR 2025 Oral) — multi-phase inference > larger models
- [SCoRe](https://arxiv.org/abs/2409.12917) (ICLR 2025 Oral) — structured self-correction via RL

## Architecture

Three core mechanisms:

1. **Commands** (`commands/`): Slash command definitions (YAML frontmatter + Markdown prompts)
2. **Hooks** (`hooks/`): Stop hook (phase machine) + PreToolUse hook (tool blocking)
3. **Scripts** (`scripts/`): State management, argument parsing, plan saving

### Execution Flow

```
/plansmith:plan → setup.sh (creates state file)
  → Phase 1: understand (analyze problem, define success criteria)
  → Phase 2: explore (read codebase, list findings + Reflexion memory injection)
  → Phase 3: alternatives (compare approaches, choose one)
  → Phase 4: draft (write complete plan with Least-to-Most step ordering)
  → Phase 5: critique (principle-based P1-P12 PASS/FAIL, technical perspective)
  → Phase 6: revise (address critiques)
  → Phase 7: critique (round 2, maintainability perspective)
  → Phase 8: revise (finalize with promise tag)
  → save.sh → .claude/plansmith-output.local.md + memory extraction
```

### Phase Machine (stop-hook.sh + phases/)

The phase machine is split into a dispatcher (`stop-hook.sh`) and per-phase validation files (`hooks/phases/*.sh`). The dispatcher handles common setup (state file parsing, frontmatter extraction, helper functions) and `source`s the appropriate phase file based on the current phase. Phase files run in the same process — all dispatcher variables and functions are available without `export`.

Each phase has distinct validation:

| Phase | Passes when | Fails when |
|-------|-------------|------------|
| understand | 3+ numbered items, 2+ understanding keywords, no plan headings | Plan headings found, insufficient analysis |
| explore | 2+ file path references, no plan headings | Plan headings found (negative validation) |
| alternatives | 2+ options, recommendation keyword, pros/cons keyword, no promise tag, no plan headings | Missing options, recommendation, or trade-offs |
| draft | All required section headings present | Sections missing |
| critique | 3+ numbered items, no `<promise>` tag, 6+ principle evidence (P-refs + PASS/FAIL combined, principles mode) | Promise present (negative validation), <3 items, insufficient principle evaluation |
| revise | Promise tag + all sections (final round only) | Promise missing or sections missing |

Key insights:
- **Negative validation** (checking what must NOT be in the output) prevents Claude from collapsing phases together
- **Perspective rotation** for repeated critique phases (technical → maintainability; devil's advocate only in round 3+, requires `--refine-iterations 3+`)
- **Principle-based critique** (Constitutional AI): 12 enumerable principles with PASS/FAIL evaluation
- **Aspirational prompts vs. minimum validators**: Prompts aim high (e.g., "8 of 12 principles, 3 FAILs") while validators enforce a minimum floor (e.g., 6 evidence points). This intentional gap avoids over-strict gating while encouraging thorough output.
- **Multi-iteration** (Self-Refine): critique-revise cycles repeated 2× by default (configurable 1-4 via `--refine-iterations`). Phase sequence built dynamically: `understand,explore,alternatives,draft` + `(critique,revise)×N`. Overridden when `--phases` is explicit.
- **Session memory** (Reflexion): FAIL items from past sessions stored in `.claude/plansmith-memory.local.md` and injected into explore phase. Controlled by `--no-memory` / `--clear-memory`.

### State File

`.claude/plansmith.local.md` with YAML frontmatter:
```yaml
active: true
phase: understand
phase_index: 0
max_phases: 10
phases: "understand,explore,alternatives,draft,critique,revise,critique,revise"
refine_iterations: 2
critique_mode: "principles"
use_memory: true
completion_promise: "PLAN_OK"
block_tools: true
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
started_at: "2025-01-01T00:00:00Z"
```

State file은 3-layer hybrid 구조:

1. **YAML frontmatter** — 설정 (위 예시). `sed`로 파싱, `sed_inplace()`로 업데이트.
2. **Body** — 각 phase 출력이 축적됨 (understand → explore → ... 순서대로 append)
3. **HTML comments** — critique 결과 구분자. `save.sh`가 여기서 FAIL 항목을 추출하여 Reflexion memory에 저장.

```
<!-- CRITIQUE_ROUND_1 -->
[critique output]
<!-- /CRITIQUE_ROUND_1 -->
```

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
| `hooks/stop-hook.sh` | Phase machine dispatcher (common setup + `source` dispatch) |
| `hooks/lib/common.sh` | Shared helpers (sed_inplace, advance_phase, block_with, get_section_pattern) |
| `hooks/phases/*.sh` | Per-phase validation and prompt logic (sourced by stop-hook.sh) |
| `hooks/pretooluse-hook.sh` | Tool blocking during planning |
| `scripts/setup.sh` | CLI arg parsing + state file creation |
| `scripts/save.sh` | Final plan saving |
| `scripts/cancel.sh` | Loop cancellation |
| `templates/plan-rubric.md` | Quality rubric template |
| `templates/critique-principles.md` | 12 critique principles (Constitutional AI) |

## Known Limitations

- Prompt containing `---` on its own line breaks YAML frontmatter parsing
- Bash allowlist allows quoted special chars (e.g., `grep 'a&b'`), but unclosed quotes or complex escape patterns may still be blocked
- `--completion-promise` values with double quotes may break YAML parsing
- Bash allowlist includes `git branch/remote/tag` which can mutate state with arguments (e.g., `git branch new-name`). In practice, Claude does not create branches during planning, but the check is command-level not argument-level.
