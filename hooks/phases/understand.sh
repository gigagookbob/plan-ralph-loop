# Phase: UNDERSTAND
# Validates problem analysis output. Advances to EXPLORE on pass.
# Injects Reflexion session memory into the explore prompt.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

# NEGATIVE VALIDATION: must NOT contain plan section headings (but file paths are OK)
if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|목표|Steps|단계|Scope|범위|Non-Scope|비범위|Verification|검증|Risks|리스크|Open Questions|오픈 질문)"; then
  block_with \
    "[plansmith] $PROGRESS Phase: UNDERSTAND — Do NOT write a plan yet.

In this phase, deeply understand the request BEFORE reading code:

1. PROBLEM: What is the problem? Why is this change needed?
2. SUCCESS CRITERIA: What does success look like concretely?
3. CONSTRAINTS: What technical/business constraints exist?
4. ASSUMPTIONS: What assumptions are you making?
5. IMPACT: Who/what is affected?

Do NOT include headings like ## Goal, ## Steps, ## Scope, etc.

Original request:
$PROMPT_TEXT" \
    "Phase: UNDERSTAND | Analyze the problem. Do NOT write a plan yet."
fi

# POSITIVE VALIDATION: structured problem understanding
NUMBERED_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '^\s*[0-9]+\.' || true)
UNDERSTAND_KEYWORDS=$(echo "$LAST_OUTPUT" | grep -ciE '(문제|problem|왜|why|목적|purpose|성공|success|제약|constraint|가정|assumption|영향|impact|요구사항|requirement)' || true)

if [[ "$NUMBERED_COUNT" -lt 3 ]] || [[ "$UNDERSTAND_KEYWORDS" -lt 2 ]]; then
  block_with \
    "[plansmith] $PROGRESS Phase: UNDERSTAND — Not enough problem analysis.

Found $NUMBERED_COUNT numbered items (need 3+) and $UNDERSTAND_KEYWORDS understanding keywords (need 2+).

Deeply analyze the request:
1. PROBLEM: What is the problem? Why is this change needed?
2. SUCCESS CRITERIA: What does success look like concretely?
3. CONSTRAINTS: What technical/business constraints exist?
4. ASSUMPTIONS: What assumptions are you making?
5. IMPACT: Who/what is affected?

Original request:
$PROMPT_TEXT" \
    "Phase: UNDERSTAND | Need 3+ numbered items and 2+ understanding keywords."
fi

# Understand passed — advance to explore
advance_phase

# Reflexion: inject session memory if available
MEMORY_INJECT=""
if [[ "$USE_MEMORY" == "true" ]] && [[ -f "$PROJECT_DIR/.claude/plansmith-memory.local.md" ]]; then
  MEMORY_CONTEXT=$(tail -30 "$PROJECT_DIR/.claude/plansmith-memory.local.md")
  if [[ -n "$MEMORY_CONTEXT" ]]; then
    MEMORY_INJECT="

LESSONS FROM PREVIOUS PLANNING SESSIONS (avoid these patterns):
$MEMORY_CONTEXT
"
  fi
fi

block_with \
  "[plansmith] $PROGRESS Phase: EXPLORE — Now read the codebase.

Based on your problem understanding above, read the codebase to find relevant files and patterns.
Reference your problem definition, success criteria, and constraints as you explore.

1. FILES READ: List every file you examined (full paths)
2. ARCHITECTURE: How the codebase is structured
3. RELEVANT PATTERNS: Existing patterns that affect the planned work
4. DEPENDENCIES: External and internal dependencies
5. CONSTRAINTS: Technical constraints discovered
$MEMORY_INJECT
Do NOT include headings like ## Goal, ## Steps, ## Scope, etc.

Original request:
$PROMPT_TEXT" \
  "Phase: EXPLORE | Read actual files and report findings. No plan yet."
