---
description: "Start a planning-focused iterative loop (Plan Ralph Loop)"
argument-hint: "PROMPT [--max-iterations N] [--no-block-tools] [--required-sections 'A,B,C']"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-plan-ralph.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Plan Ralph Loop

IMPORTANT: You MUST run the setup script FIRST before doing anything else. This is mandatory — the planning loop will not work without it.

Run this exact command using the Bash tool:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-plan-ralph.sh" $ARGUMENTS
```

Wait for the script output. It will display "Plan Ralph Loop activated!" and the completion requirements.

ONLY AFTER the setup script has run successfully, begin the planning process below.

---

You are now in **planning mode**. File modifications are blocked. You may only read and explore the codebase.

## Workflow

1. Explore the codebase to understand the current architecture
2. Draft a structured plan following the template below
3. Each iteration: self-critique the previous plan, then improve it
4. When all required sections are complete, output `<promise>PLAN_OK</promise>`

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

- Only output `<promise>PLAN_OK</promise>` when the plan is thorough and actionable
- Each step must reference actual file paths, function names, or code patterns
- No vague language ("improve", "optimize") without specific details
- Do NOT output a false promise to escape the loop
- You MUST wrap the completion signal in XML tags: `<promise>PLAN_OK</promise>` — writing just "PLAN_OK" will NOT work
