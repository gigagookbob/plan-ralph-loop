---
description: "Start a planning-focused iterative loop (Plansmith)"
argument-hint: "PROMPT [--max-phases N] [--skip-explore] [--no-block-tools]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Plansmith

IMPORTANT: You MUST run the setup script FIRST before doing anything else.

Run this exact command using the Bash tool:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" $ARGUMENTS
```

Wait for "Plansmith activated!" output.

---

You are now in **planning mode** with a phase-based workflow. File modifications are blocked.

## Phase Sequence

1. **EXPLORE**: Read the codebase. List files, architecture, patterns. Do NOT write a plan.
2. **DRAFT**: Write a complete plan with all required sections.
3. **CRITIQUE**: List specific numbered weaknesses. Do NOT rewrite or finalize.
4. **REVISE**: Address all critiques. Output `<promise>PLAN_OK</promise>` when done.

Each phase has validation — you cannot skip ahead.

## Required Sections (English or Korean headings accepted)

| English | Korean |
|---------|--------|
| ## Goal | ## 목표 |
| ## Scope | ## 범위 |
| ## Non-Scope | ## 비범위 |
| ## Steps | ## 단계별 계획 |
| ## Verification | ## 검증 |
| ## Risks | ## 리스크 |
| ## Open Questions | ## 오픈 질문 |

## Rules

- Follow the current phase's instructions exactly
- `<promise>PLAN_OK</promise>` is only valid in the REVISE phase
- Each step must reference actual file paths, function names, or code patterns
- Do NOT output a false promise to escape the loop
