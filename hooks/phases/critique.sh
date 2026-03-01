# Phase: CRITIQUE
# Validates principle-based critique output. Advances to REVISE on pass.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

CRITIQUE_PERSPECTIVE="Evaluate the plan thoroughly: implementation correctness, edge cases, dependency ordering, error handling, maintainability, and clarity."

# NEGATIVE VALIDATION: must NOT contain promise tag
if echo "$LAST_OUTPUT" | grep -qE '<promise>'; then
  block_with \
    "[plansmith] $PROGRESS Phase: CRITIQUE — Do NOT finalize during critique.

You included a <promise> tag. This phase is for identifying weaknesses ONLY.
$CRITIQUE_PERSPECTIVE

List at least 3 specific, numbered weaknesses in the plan. No rewriting, no finalizing.

Original request:
$PROMPT_TEXT" \
    "Phase: CRITIQUE | Remove the promise tag. List weaknesses only."
fi

# POSITIVE VALIDATION: must contain at least 3 numbered items
NUMBERED_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '^\s*[0-9]+\.' || true)
if [[ "$NUMBERED_COUNT" -lt 3 ]]; then
  block_with \
    "[plansmith] $PROGRESS Phase: CRITIQUE — Not enough specific critiques.

Found $NUMBERED_COUNT numbered items, need at least 3.
$CRITIQUE_PERSPECTIVE

List specific, numbered weaknesses (e.g., '1. The step ordering is wrong because...')

Consider: step ordering, edge cases, verification runnability, implicit assumptions,
vague language, breaking changes, effort estimates.

Original request:
$PROMPT_TEXT" \
    "Phase: CRITIQUE | Need at least 3 numbered weaknesses. Found $NUMBERED_COUNT."
fi

# PRINCIPLE VALIDATION (Constitutional AI): check principle references
PRINCIPLE_REFS=$(echo "$LAST_OUTPUT" | grep -ciE '\bP[0-9]+\b' || true)
PASS_FAIL_REFS=$(echo "$LAST_OUTPUT" | grep -ciE '\b(PASS|FAIL)\b' || true)
TOTAL_PRINCIPLE_EVIDENCE=$((PRINCIPLE_REFS + PASS_FAIL_REFS))
if [[ "$TOTAL_PRINCIPLE_EVIDENCE" -lt 6 ]]; then
  block_with \
    "[plansmith] $PROGRESS Phase: CRITIQUE — Insufficient principle evaluation.

Found $PRINCIPLE_REFS principle references (P1-P12) and $PASS_FAIL_REFS PASS/FAIL judgments (need 6+ total).
$CRITIQUE_PERSPECTIVE

Evaluate each principle (P1-P12) with explicit PASS or FAIL.
You must address at least 8 principles and find at least 3 FAILs.

Original request:
$PROMPT_TEXT" \
    "Phase: CRITIQUE | Need 6+ principle references (P1-P12 + PASS/FAIL). Found $TOTAL_PRINCIPLE_EVIDENCE."
fi

# Critique passed — advance to revise
advance_phase

# Self-Refine lookahead: determine if the upcoming revise is followed by another critique.
# advance_phase (line 83) updated the STATE FILE to next phase/index, but shell var
# PHASE_INDEX still holds the pre-advance value. Therefore:
#   PHASE_INDEX+1 = revise (just advanced to)
#   PHASE_INDEX+2 = phase after revise (critique if another cycle, or end-of-list)
# Note: revise.sh uses a different pattern — it checks BEFORE calling advance_phase,
# so its lookahead uses PHASE_INDEX+1 (not +2). Both approaches are correct.
IFS=',' read -ra NEXT_CHECK <<< "$PHASES_STR"
AFTER_REVISE_IDX=$((PHASE_INDEX + 2))
AFTER_REVISE_NAME=""
if [[ $AFTER_REVISE_IDX -lt ${#NEXT_CHECK[@]} ]]; then
  AFTER_REVISE_NAME=$(echo "${NEXT_CHECK[$AFTER_REVISE_IDX]}" | xargs)
fi

if [[ "$AFTER_REVISE_NAME" == "critique" ]]; then
  # Not the final revise — another critique-revise cycle follows
  PROMISE_INSTRUCTION="Do NOT output <promise>$COMPLETION_PROMISE</promise> yet — another critique round follows."
else
  # Final revise — can finalize with promise
  PROMISE_INSTRUCTION="When the plan is thorough and all critique items are addressed, output <promise>$COMPLETION_PROMISE</promise> at the very end."
fi

block_with \
  "[plansmith] $PROGRESS Phase: REVISE — Rewrite the plan addressing every critique item.

Address EVERY numbered weakness from your critique. Rewrite the complete plan with all fixes applied.

Required sections: $REQUIRED_SECTIONS

$PROMISE_INSTRUCTION

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original request:
$PROMPT_TEXT" \
  "Phase: REVISE | Address all critique items."
