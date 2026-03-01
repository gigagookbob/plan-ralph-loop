# Phase: EXPLORE
# Validates codebase exploration output. Advances to next phase on pass.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

# NEGATIVE VALIDATION: must NOT contain plan section headings
if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|Steps|Scope|Non-Scope|Verification|Risks|Risk|Open Questions|Open Question)"; then
  block_with \
    "[plansmith] $PROGRESS Phase: EXPLORE — You wrote plan section headings. Do NOT write a plan yet.

In this phase, you must ONLY report what you found in the codebase:

1. FILES READ: List every file you examined (full paths)
2. ARCHITECTURE: How the codebase is structured (entry points, modules, data flow)
3. RELEVANT PATTERNS: Existing patterns that affect the planned work
4. DEPENDENCIES: External and internal dependencies
5. CONSTRAINTS: Technical constraints discovered

Do NOT include headings like ## Goal, ## Steps, ## Scope, etc.

Original request:
$PROMPT_TEXT" \
    "Phase: EXPLORE | Do NOT write a plan yet. List your codebase findings only."
fi

# POSITIVE VALIDATION: must contain evidence of actual exploration (file paths)
# Path-based detection (high confidence): patterns with directory separator
PATH_REF_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\.[a-zA-Z]+' || true)
# Extension-based detection (broader): known source file extensions
SOURCE_EXTENSIONS=(ts js py go rs java jsx tsx sh md yaml yml toml cfg rb c cpp h hpp css scss html xml sql php)
EXT_PATTERN=$(IFS='|'; echo "${SOURCE_EXTENSIONS[*]}")
EXT_REF_COUNT=$(echo "$LAST_OUTPUT" | grep -cE "\.(${EXT_PATTERN})(\s|$|[,;:)])" || true)
FILE_REF_COUNT=$((PATH_REF_COUNT > EXT_REF_COUNT ? PATH_REF_COUNT : EXT_REF_COUNT))
if [[ "$FILE_REF_COUNT" -lt 2 ]]; then
  block_with \
    "[plansmith] $PROGRESS Phase: EXPLORE — Not enough codebase exploration detected.

Please read actual files using Read, Glob, and Grep tools. Then list your findings:

1. FILES READ: Full paths of files you examined
2. ARCHITECTURE: Code structure and data flow
3. RELEVANT PATTERNS: Patterns relevant to the task
4. DEPENDENCIES: What the project depends on
5. CONSTRAINTS: Technical limitations found

Original request:
$PROMPT_TEXT" \
    "Phase: EXPLORE | Read actual files and report findings. No plan yet."
fi

# Explore passed — advance to next phase
advance_phase
NEXT_PHASE=$(grep '^phase: ' "$STATE_FILE" | sed 's/phase: *//')

case "$NEXT_PHASE" in
  alternatives)
    block_with \
      "[plansmith] $PROGRESS Phase: ALTERNATIVES — Compare approaches before planning.

Based on your exploration findings, compare 2-3 possible approaches:
For each approach:
- Core idea
- Pros and cons (implementation complexity, maintainability, compatibility with existing code)

At the end, choose one approach and explain why.
Do NOT write a plan yet — only compare approaches.

Original request:
$PROMPT_TEXT" \
      "Phase: ALTERNATIVES | Compare 2-3 approaches. Do NOT write a plan yet."
    ;;
  draft)
    block_with \
      "[plansmith] $PROGRESS Phase: DRAFT — Now write the plan.

Based on your exploration findings, write a complete plan with ALL required sections:
$REQUIRED_SECTIONS

STEP ORDERING (Least-to-Most decomposition):
- Order steps from simplest/most independent to most complex/most dependent
- Each step should build on the foundation of previous steps
- For each step, explicitly state which previous steps it depends on
- If two steps are independent, note that they can be parallelized

Each step must reference specific files and functions you discovered during exploration.
Use the required section headings (Goal, Scope, Non-Scope, Steps, Verification, Risks, Open Questions).

Do NOT output <promise>$COMPLETION_PROMISE</promise> yet — there will be a critique phase first.

Original request:
$PROMPT_TEXT" \
      "Phase: DRAFT | Write the complete plan with all required sections."
    ;;
  *)
    block_with \
      "[plansmith] $PROGRESS Proceeding to next phase.

Original request:
$PROMPT_TEXT" \
      "Proceeding to next phase."
    ;;
esac
