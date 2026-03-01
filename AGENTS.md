# Repository Guidelines

## Project Structure & Module Organization
- `commands/`: Slash command definitions (`plan.md`, `cancel.md`, `help.md`).
- `hooks/`: Runtime hook logic.
- `hooks/stop-hook.sh`: phase dispatcher.
- `hooks/pretooluse-hook.sh`: tool-blocking policy.
- `hooks/phases/`: per-phase validators/prompts (`understand`, `explore`, `alternatives`, `draft`, `critique`, `revise`).
- `hooks/lib/common.sh`: shared helpers used by phase scripts.
- `scripts/`: lifecycle scripts (`setup.sh`, `save.sh`, `cancel.sh`).
- `templates/`: reusable prompt templates (`plan-rubric.md`, `critique-principles.md`).
- `tests/`: shell test suites (`test-phases.sh`, `test-integration.sh`).

## Build, Test, and Development Commands
This repo has no compile/build step; it is Bash + Markdown.

- `bash tests/test-phases.sh`: unit-style phase validation tests.
- `bash tests/test-integration.sh`: black-box integration tests for scripts/hooks.
- `CLAUDE_PLUGIN_ROOT=$(pwd) bash scripts/setup.sh "Design auth system"`: local setup smoke test.
- `bash scripts/cancel.sh`: deactivate an active local loop in `.claude/plansmith.local.md`.

Prerequisites: `bash`, `jq`, and `perl` must be installed.

## Coding Style & Naming Conventions
- Use Bash with `#!/bin/bash` and `set -euo pipefail` for executable scripts.
- Do not add `set -euo pipefail` to sourced helper files (for example `hooks/lib/common.sh`).
- Prefer portable patterns: temp-file `sed` updates instead of `sed -i`.
- Use `jq -n --arg ...` for JSON output to avoid escaping issues.
- Naming:
- Functions: `snake_case` (`advance_phase`, `sed_inplace`).
- Constants/environment-like vars: `UPPER_SNAKE_CASE`.
- Tests: `tests/test-*.sh` with `test_*` function names.

## Testing Guidelines
- Run both test suites before opening a PR.
- For behavior changes in any phase, add:
- unit coverage in `tests/test-phases.sh` (validator logic),
- integration coverage in `tests/test-integration.sh` (hook/script I/O and side effects).
- Keep tests deterministic (`mktemp`, isolated `.claude` state, explicit assertions).

## Commit & Pull Request Guidelines
- Follow Conventional Commit style seen in history: `fix: ...`, `chore: ...`, `docs: ...`, `refactor: ...`.
- Keep commits focused and imperative; separate refactors from behavior changes.
- PRs should include:
- purpose and scope,
- affected files/phases,
- test commands run and results,
- sample output snippets when prompt/hook messaging changes.
