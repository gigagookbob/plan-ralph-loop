# Phase: ALTERNATIVES
# Validates approach comparison output. Advances to DRAFT on pass.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

# NEGATIVE VALIDATION: must NOT contain promise tag or plan headings
if echo "$LAST_OUTPUT" | grep -qE '<promise>'; then
  block_with \
    "[plansmith] $PROGRESS Phase: ALTERNATIVES — Do NOT finalize during alternatives comparison.

Compare 2-3 approaches with pros/cons, then choose one. No plan writing, no promise tags.

Original request:
$PROMPT_TEXT" \
    "Phase: ALTERNATIVES | Remove the promise tag. Compare approaches only."
fi
if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|Steps|Scope|Non-Scope|Verification|Risks|Risk|Open Questions|Open Question)"; then
  block_with \
    "[plansmith] $PROGRESS Phase: ALTERNATIVES — Do NOT write a plan yet.

Compare 2-3 approaches with pros/cons, then choose one. No plan headings allowed.

Original request:
$PROMPT_TEXT" \
    "Phase: ALTERNATIVES | Compare approaches only. No plan headings."
fi

# POSITIVE VALIDATION: alternatives comparison with recommendation
ALT_NUMBERED=$(echo "$LAST_OUTPUT" | grep -cE '^\s*[0-9]+\.' || true)
ALT_RECOMMEND=$(echo "$LAST_OUTPUT" | grep -ciE '(추천|선택|recommend|choose|prefer|선정|selected|chose)' || true)
ALT_TRADEOFF=$(echo "$LAST_OUTPUT" | grep -ciE '(장점|단점|pros|cons|advantage|disadvantage|trade-off|트레이드|tradeoff)' || true)

if [[ "$ALT_NUMBERED" -lt 2 ]] || [[ "$ALT_RECOMMEND" -lt 1 ]] || [[ "$ALT_TRADEOFF" -lt 1 ]]; then
  block_with \
    "[plansmith] $PROGRESS Phase: ALTERNATIVES — Incomplete alternatives comparison.

Found $ALT_NUMBERED numbered items (need 2+), $ALT_RECOMMEND recommendation keywords (need 1+), $ALT_TRADEOFF trade-off keywords (need 1+).

Compare 2-3 approaches. For each:
- Core idea
- Pros and cons (implementation complexity, maintainability, compatibility)

Then choose one approach and explain why.

Original request:
$PROMPT_TEXT" \
    "Phase: ALTERNATIVES | Need 2+ options, recommendation, and pros/cons analysis."
fi

# Alternatives passed — advance to next phase
advance_phase
NEXT_PHASE=$(grep '^phase: ' "$STATE_FILE" | sed 's/phase: *//')

case "$NEXT_PHASE" in
  draft)
    block_with \
      "[plansmith] $PROGRESS Phase: DRAFT — Now write the plan.

Based on the approach you selected, write a complete plan with ALL required sections:
$REQUIRED_SECTIONS

STEP ORDERING (Least-to-Most decomposition):
- Order steps from simplest/most independent to most complex/most dependent
- Each step should build on the foundation of previous steps
- For each step, explicitly state which previous steps it depends on (e.g., 'Depends on: Step 2')
- If two steps are independent, note that they can be parallelized

Each step must reference specific files and functions you discovered during exploration.
Use the required section headings (Goal, Scope, Non-Scope, Steps, Verification, Risks, Open Questions).

When the draft is complete, the next phase will ask you to self-critique it.
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
