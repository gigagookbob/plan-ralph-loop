# Phase: REVISE (also handles iterate)
# Validates revised plan: promise extraction, section check, Self-Refine lookahead.
# On final pass: saves plan and deactivates state.
# Sourced by stop-hook.sh — do not execute directly.
# shellcheck disable=SC2154

# STANDARD QUALITY GATE: promise + required sections

# Check promise
PROMISE_TEXT=""
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
fi

PROMISE_MATCHED="false"
if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
  PROMISE_MATCHED="true"
fi

if [[ "$PROMISE_MATCHED" != "true" ]]; then
  # Self-Refine: check if next phase is another critique round
  NEXT_IDX=$((PHASE_INDEX + 1))
  IFS=',' read -ra PHASE_CHECK <<< "$PHASES_STR"
  NEXT_PHASE_NAME="iterate"
  if [[ $NEXT_IDX -lt ${#PHASE_CHECK[@]} ]]; then
    NEXT_PHASE_NAME=$(echo "${PHASE_CHECK[$NEXT_IDX]}" | xargs)
  fi

  advance_phase

  if [[ "$NEXT_PHASE_NAME" == "critique" ]]; then
    # Next phase is another critique round — output revised plan without promise
    block_with \
      "[plansmith] $PROGRESS Phase: REVISE complete — Moving to next CRITIQUE round.

Output the complete revised plan addressing all previous critique items.
Do NOT include <promise>$COMPLETION_PROMISE</promise> yet — another critique round follows.

Required sections: $REQUIRED_SECTIONS

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original request:
$PROMPT_TEXT" \
      "Phase: REVISE complete. Next: CRITIQUE round. Output revised plan without promise tag."
  else
    # No more critique rounds — iterate toward finalization
    block_with \
      "[plansmith] $PROGRESS Phase: ITERATE — Plan not yet finalized.

Continue improving the plan:
1. SELF-CRITIQUE: What is still weak, vague, or missing?
2. IMPROVE: Add concrete details, fix remaining issues.
3. FINALIZE: Output the complete plan with ALL sections ($REQUIRED_SECTIONS), then <promise>$COMPLETION_PROMISE</promise> at the very end.

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original request:
$PROMPT_TEXT" \
      "Phase: ITERATE | Output <promise>$COMPLETION_PROMISE</promise> when all sections are complete."
  fi
fi

# Promise matched — check required sections
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
  advance_phase
  block_with \
    "[plansmith] $PROGRESS Quality gate: Missing sections — $MISSING_LIST

You included <promise>$COMPLETION_PROMISE</promise> but these sections are missing:
$MISSING_LIST

Add the missing sections and re-output the complete plan with <promise>$COMPLETION_PROMISE</promise>.

Original request:
$PROMPT_TEXT" \
    "Quality gate FAILED | Missing sections: $MISSING_LIST"
fi

# ALL CHECKS PASSED — save and deactivate
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if ! bash "$PLUGIN_ROOT/scripts/save.sh" "$PROJECT_DIR" "$LAST_OUTPUT" "completed"; then
  echo "Warning: plansmith failed to save plan to disk." >&2
fi

sed_inplace "s/^active: true/active: false/" "$STATE_FILE"

echo "Plansmith complete! Plan saved to .claude/plansmith-output.local.md" >&2
exit 0
