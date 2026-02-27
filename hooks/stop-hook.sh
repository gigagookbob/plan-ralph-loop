#!/bin/bash

# Plan Ralph Loop Stop Hook
# Prevents session exit when a plan-ralph-loop is active.
# Implements a 2-phase quality gate: promise tag + required sections check.
# Enforces minimum 2 iterations (first iteration is always a draft).

set -euo pipefail

# --- 0. Dependency check ---
for cmd in jq perl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Warning: plan-ralph-loop requires '$cmd' but it's not installed." >&2
    exit 0
  fi
done

# --- 1. Read hook input from stdin ---
HOOK_INPUT=$(cat)

# --- 2. Check if planning loop is active ---
RALPH_STATE_FILE=".claude/plan-ralph.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# --- 3. Parse YAML frontmatter ---
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")

ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | awk '{print $2}')
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
REQUIRED_SECTIONS=$(echo "$FRONTMATTER" | grep '^required_sections:' | sed 's/required_sections: *//' | sed 's/^"\(.*\)"$/\1/')

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# --- 4. Validate numeric fields ---
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Warning: plan-ralph-loop state file corrupted (iteration: '$ITERATION')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Warning: plan-ralph-loop state file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# --- Helper: portable sed in-place (macOS + Linux) ---
sed_inplace() {
  local pattern="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"
}

# --- 5. Check max iterations ---
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Plan Ralph Loop: Max iterations ($MAX_ITERATIONS) reached." >&2

  # Try to save whatever plan we have
  MAX_SAVE_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)
  if [[ -n "$MAX_SAVE_OUTPUT" ]]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    bash "$PLUGIN_ROOT/scripts/save-plan.sh" "." "$MAX_SAVE_OUTPUT" "max_iterations_reached"
  fi

  sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE"
  exit 0
fi

# --- 6. Get last assistant message ---
# Use last_assistant_message from hook input (more reliable than transcript parsing)
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)

# Fallback: parse transcript if last_assistant_message is empty
if [[ -z "$LAST_OUTPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
  if [[ -f "$TRANSCRIPT_PATH" ]] && grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
    LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1 || true)
    LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
      .message.content |
      map(select(.type == "text")) |
      map(.text) |
      join("\n")
    ' 2>/dev/null || true)
  fi
fi

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "Warning: plan-ralph-loop could not extract assistant message" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# --- 7. Check for completion promise ---
PROMISE_TEXT=""
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
fi

# Extract the original prompt (everything after closing ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

PROMISE_MATCHED="false"
if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
  # Enforce minimum 2 iterations: first iteration is always a draft
  if [[ $ITERATION -le 1 ]]; then
    PROMISE_MATCHED="false"
  else
    PROMISE_MATCHED="true"
  fi
fi

if [[ "$PROMISE_MATCHED" != "true" ]]; then
  # Promise not found, doesn't match, or first iteration — continue loop with self-critique
  NEXT_ITERATION=$((ITERATION + 1))

  sed_inplace "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE"

  if [[ $ITERATION -le 1 ]]; then
    SYSTEM_MSG="Plan Ralph iteration $NEXT_ITERATION/$MAX_ITERATIONS | First draft received. Now self-critique and improve before finalizing."
    REASON="[plan-ralph-loop] Iteration $NEXT_ITERATION/$MAX_ITERATIONS — Self-critique required

Your first draft is complete. Now you MUST:
1. SELF-CRITIQUE: Re-read your plan above. What is weak, vague, incomplete, or overly optimistic?
2. IMPROVE: Make the plan more concrete. Add specific file paths, function signatures, error handling details, edge cases.
3. VERIFY: Check each step — would a developer be able to implement it without asking clarifying questions?
4. FINALIZE: Output the improved plan with ALL sections ($REQUIRED_SECTIONS), then <promise>$COMPLETION_PROMISE</promise> at the very end.

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original planning request:
$PROMPT_TEXT"
  else
    SYSTEM_MSG="Plan Ralph iteration $NEXT_ITERATION/$MAX_ITERATIONS | To complete: output <promise>$COMPLETION_PROMISE</promise> (only when all required sections are present)"
    REASON="[plan-ralph-loop] Iteration $NEXT_ITERATION/$MAX_ITERATIONS

Instructions:
1. SELF-CRITIQUE: Review your previous plan. What is weak, vague, or missing?
2. IMPROVE: Address each weakness. Add concrete details, risk mitigations, verification steps.
3. STRUCTURE: Your plan MUST include ALL of these sections: $REQUIRED_SECTIONS
4. COMPLETENESS: Only when you are confident the plan is thorough, concrete, and actionable, output <promise>$COMPLETION_PROMISE</promise> at the very end.

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files. Only read and explore the codebase.

Original planning request:
$PROMPT_TEXT"
  fi

  jq -n \
    --arg reason "$REASON" \
    --arg msg "$SYSTEM_MSG" \
    '{
      "decision": "block",
      "reason": $reason,
      "systemMessage": $msg
    }'
  exit 0
fi

# --- 8. Promise matched — verify quality gate (required sections) ---

# Bilingual section heading patterns (English + Korean)
get_section_pattern() {
  local section="$1"
  case "$section" in
    Goal)             echo "(Goal|목표)" ;;
    Scope)            echo "(Scope|범위)" ;;
    Non-Scope)        echo "(Non-Scope|Non Scope|비범위)" ;;
    Steps)            echo "(Steps|단계별 계획|단계별|단계)" ;;
    Verification)     echo "(Verification|검증)" ;;
    Risks)            echo "(Risks|Risk|리스크)" ;;
    "Open Questions") echo "(Open Questions|Open Question|오픈 질문)" ;;
    *)                echo "(${section})" ;;
  esac
}

IFS=',' read -ra SECTIONS <<< "$REQUIRED_SECTIONS"
MISSING_SECTIONS=()

for section in "${SECTIONS[@]}"; do
  section=$(echo "$section" | xargs)  # trim whitespace
  PATTERN=$(get_section_pattern "$section")
  if ! echo "$LAST_OUTPUT" | grep -qiE "^#+ +${PATTERN}"; then
    MISSING_SECTIONS+=("$section")
  fi
done

if [[ ${#MISSING_SECTIONS[@]} -gt 0 ]]; then
  # Quality gate failed — missing sections
  MISSING_LIST=$(printf ", %s" "${MISSING_SECTIONS[@]}")
  MISSING_LIST=${MISSING_LIST:2}

  NEXT_ITERATION=$((ITERATION + 1))

  sed_inplace "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE"

  SYSTEM_MSG="Quality gate FAILED (iteration $NEXT_ITERATION/$MAX_ITERATIONS) | Missing sections: $MISSING_LIST"

  REASON="[plan-ralph-loop] Quality gate failed (iteration $NEXT_ITERATION/$MAX_ITERATIONS)

You included <promise>$COMPLETION_PROMISE</promise> but the following required sections are MISSING from your plan:
$MISSING_LIST

Please add the missing sections and re-output the complete plan with <promise>$COMPLETION_PROMISE</promise> at the end.

Original planning request:
$PROMPT_TEXT"

  jq -n \
    --arg reason "$REASON" \
    --arg msg "$SYSTEM_MSG" \
    '{
      "decision": "block",
      "reason": $reason,
      "systemMessage": $msg
    }'
  exit 0
fi

# --- 9. All checks passed — save plan and deactivate ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
bash "$PLUGIN_ROOT/scripts/save-plan.sh" "." "$LAST_OUTPUT" "completed"

sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE"

echo "Plan Ralph Loop complete! Plan saved to .claude/plan-output.local.md" >&2
exit 0
