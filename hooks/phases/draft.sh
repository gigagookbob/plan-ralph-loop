# Phase: DRAFT
# Validates plan draft for required sections. Advances to CRITIQUE on pass.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

# POSITIVE VALIDATION: all required section headings must exist
IFS=',' read -ra SECTIONS <<< "$REQUIRED_SECTIONS"
MISSING=()
for s in "${SECTIONS[@]}"; do
  s=$(echo "$s" | xargs)
  PATTERN=$(get_section_pattern "$s")
  if ! echo "$LAST_OUTPUT" | grep -qiE "^#+ +${PATTERN}"; then
    MISSING+=("$s")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  MISSING_LIST=$(printf ", %s" "${MISSING[@]}")
  MISSING_LIST=${MISSING_LIST:2}
  block_with \
    "[plansmith] $PROGRESS Phase: DRAFT — Missing sections: $MISSING_LIST

Please add the missing sections and resubmit the complete plan.
Required sections: $REQUIRED_SECTIONS

Original request:
$PROMPT_TEXT" \
    "Phase: DRAFT | Missing sections: $MISSING_LIST"
fi

# Draft passed — advance to critique
advance_phase

# Build critique prompt (Constitutional AI: principle-based evaluation)
CRITIQUE_PRINCIPLES=$(awk '/^## Critique Principles/,0' "$STATE_FILE")
CRITIQUE_INSTRUCTIONS="Re-read the plan you just wrote. Evaluate it against EACH principle below.
For each principle, state PASS or FAIL with a specific explanation.
You MUST address at least 8 of the 12 principles explicitly.
You MUST find at least 3 genuine FAIL items.

$CRITIQUE_PRINCIPLES"

block_with \
  "[plansmith] $PROGRESS Phase: CRITIQUE — Review your plan. Do NOT rewrite it.

$CRITIQUE_INSTRUCTIONS

DO NOT rewrite the plan. DO NOT output <promise>$COMPLETION_PROMISE</promise>. Just list the issues.

Original request:
$PROMPT_TEXT" \
  "Phase: CRITIQUE | List specific weaknesses. Do NOT rewrite or finalize."
