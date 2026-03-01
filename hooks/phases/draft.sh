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

# Build critique prompt based on mode (Constitutional AI vs open-ended)
if [[ "$CRITIQUE_MODE" == "principles" ]]; then
  # Read critique principles from state file body
  CRITIQUE_PRINCIPLES=$(awk '/^## Critique Principles/,0' "$STATE_FILE")
  CRITIQUE_INSTRUCTIONS="Re-read the plan you just wrote. Evaluate it against EACH principle below.
For each principle, state PASS or FAIL with a specific explanation.
You MUST address at least 8 of the 12 principles explicitly.
You MUST find at least 3 genuine FAIL items.

$CRITIQUE_PRINCIPLES"
else
  CRITIQUE_INSTRUCTIONS="Re-read the plan you just wrote. List SPECIFIC weaknesses as a numbered list.
For each weakness, explain:
- What is wrong or missing
- Why it matters
- What the fix should be

You MUST find at least 3 genuine issues. Consider:
1. Are steps ordered correctly? Are dependencies between steps explicit?
2. Are there edge cases, error paths, or failure modes not addressed?
3. Are verification steps actually runnable? Would copy-pasting them work?
4. Are there implicit assumptions that should be explicit?
5. Is anything vague where it should be specific (file paths, function names, exact commands)?
6. Are breaking changes identified? Migration path clear?
7. Are effort estimates realistic?"
fi

block_with \
  "[plansmith] $PROGRESS Phase: CRITIQUE — Review your plan. Do NOT rewrite it.

$CRITIQUE_INSTRUCTIONS

DO NOT rewrite the plan. DO NOT output <promise>$COMPLETION_PROMISE</promise>. Just list the issues.

Original request:
$PROMPT_TEXT" \
  "Phase: CRITIQUE | List specific weaknesses. Do NOT rewrite or finalize."
