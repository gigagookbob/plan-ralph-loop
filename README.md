# plansmith

A planning-focused iterative loop plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Progresses through structured phases — explore, draft, critique, revise — with validation at each step to produce high-quality implementation plans.

Based on the [Ralph Loop](https://ghuntley.com/ralph/) technique — but instead of iterating on code until tests pass, it progresses through **distinct planning phases** until a quality gate is satisfied.

## Why?

Working with Claude Code on complex tasks, there's a common pattern: jump straight into writing code, lose direction halfway, revert, start over. "Just plan first" sounds obvious — but AI rarely produces a genuinely good plan on the first attempt.

The problem is deeper than "iterate more." If you ask an LLM to "keep improving your plan," it produces the same quality of output each time — it always tries to write a complete answer. Simply repeating the same prompt doesn't help.

The solution: **force fundamentally different work at each stage.** Explore the code before planning. Draft before critiquing. Critique before revising. Each phase has **negative validation** — the explore phase rejects plan headings, the critique phase rejects finalization attempts. This makes it structurally impossible to skip ahead.

## How It Works

```
/plansmith:plan Design auth system --max-phases 10
```

| Phase | What Claude does | What's validated |
|-------|-----------------|-----------------|
| **Explore** | Reads codebase, lists files/architecture/patterns | Must NOT contain plan headings (`## Goal`, etc.) |
| **Draft** | Writes complete plan with all 7 required sections | All section headings must be present |
| **Critique** | Lists specific numbered weaknesses (3+ required) | Must NOT contain `<promise>` tag |
| **Revise** | Rewrites plan addressing every critique item | Promise tag + all sections = done |

Each phase produces genuinely different output because the validation prevents collapsing phases together.

## Quick Start

```bash
# Load the plugin
claude --plugin-dir /path/to/plansmith

# Start a planning loop
/plansmith:plan Design the authentication system --max-phases 10

# Skip explore phase for small codebases
/plansmith:plan Plan the refactor --skip-explore

# Cancel if needed
/plansmith:cancel
```

## How It Differs from Ralph Loop

| | ralph-loop | plansmith |
|--|-----------|-----------------|
| **Structure** | Same prompt repeated | Distinct phases with different prompts |
| **Validation** | Single promise tag | Per-phase validation (positive + negative) |
| **Tool blocking** | None (full access) | Edit/Write/Bash blocked during planning |
| **Self-critique** | Optional | Dedicated critique phase (cannot skip) |
| **Output** | Modified files | Saved plan file (`.claude/plansmith-output.local.md`) |

## Commands

### `/plansmith:plan <PROMPT> [OPTIONS]`

| Option | Default | Description |
|--------|---------|-------------|
| `--max-phases <n>` | 10 | Maximum phase transitions before auto-stop |
| `--skip-explore` | (explore ON) | Skip the explore phase |
| `--phases "a,b,c"` | explore,draft,critique,revise | Custom phase sequence |
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
2. **Required Sections**: All section headings must exist (English or Korean)

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

```bash
git clone https://github.com/gigagookbob/plansmith.git
claude --plugin-dir /path/to/plansmith
```

## License

MIT License. See [LICENSE](LICENSE) for details.
