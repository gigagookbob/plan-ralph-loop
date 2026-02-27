#!/bin/bash

# Plan Ralph Loop Stop Hook
# Prevents session exit when a plan-ralph-loop is active.
# Implements a phase machine: explore → draft → critique → revise → iterate
# Each phase has distinct validation and prompts.

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
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
PHASE_INDEX=$(echo "$FRONTMATTER" | grep '^phase_index:' | sed 's/phase_index: *//')
MAX_PHASES=$(echo "$FRONTMATTER" | grep '^max_phases:' | sed 's/max_phases: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
REQUIRED_SECTIONS=$(echo "$FRONTMATTER" | grep '^required_sections:' | sed 's/required_sections: *//' | sed 's/^"\(.*\)"$/\1/')
PHASES_STR=$(echo "$FRONTMATTER" | grep '^phases:' | sed 's/phases: *//' | sed 's/^"\(.*\)"$/\1/')

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Graceful fallback for old-format state files (missing phase field)
if [[ -z "$PHASE" ]]; then
  echo "Warning: plan-ralph-loop state file uses old format. Deactivating." >&2
  sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE" 2>/dev/null || true
  exit 0
fi

# --- 4. Validate numeric fields ---
if [[ ! "$PHASE_INDEX" =~ ^[0-9]+$ ]]; then
  echo "Warning: plan-ralph-loop state file corrupted (phase_index: '$PHASE_INDEX')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_PHASES" =~ ^[0-9]+$ ]]; then
  echo "Warning: plan-ralph-loop state file corrupted (max_phases: '$MAX_PHASES')" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# --- Helper: portable sed in-place (macOS + Linux) ---
sed_inplace() {
  local pattern="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"
}

# --- Helper: advance to next phase ---
advance_phase() {
  local next_index=$((PHASE_INDEX + 1))
  IFS=',' read -ra PHASE_ARR <<< "$PHASES_STR"
  local next_phase
  if [[ $next_index -lt ${#PHASE_ARR[@]} ]]; then
    next_phase=$(echo "${PHASE_ARR[$next_index]}" | xargs)
  else
    next_phase="iterate"
  fi
  sed_inplace "s/^phase: .*/phase: $next_phase/" "$RALPH_STATE_FILE"
  sed_inplace "s/^phase_index: .*/phase_index: $next_index/" "$RALPH_STATE_FILE"
}

# --- Helper: block stop and inject prompt ---
block_with() {
  local reason="$1" system_msg="$2"
  jq -n \
    --arg reason "$reason" \
    --arg msg "$system_msg" \
    '{
      "decision": "block",
      "reason": $reason,
      "systemMessage": $msg
    }'
  exit 0
}

# --- 5. Check max phases ---
if [[ $MAX_PHASES -gt 0 ]] && [[ $PHASE_INDEX -ge $MAX_PHASES ]]; then
  echo "Plan Ralph Loop: Max phases ($MAX_PHASES) reached." >&2

  MAX_SAVE_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)
  if [[ -n "$MAX_SAVE_OUTPUT" ]]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    bash "$PLUGIN_ROOT/scripts/save-plan.sh" "." "$MAX_SAVE_OUTPUT" "max_phases_reached"
  fi

  sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE"
  exit 0
fi

# --- 6. Get last assistant message ---
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)

# Fallback: parse transcript
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

# Extract the original prompt (everything after closing ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

# --- 7. Phase machine ---

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

case "$PHASE" in

  explore)
    # NEGATIVE VALIDATION: must NOT contain plan section headings
    if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|목표|Steps|단계|Scope|범위|Non-Scope|비범위|Verification|검증|Risks|리스크|Open Questions|오픈 질문)"; then
      block_with \
        "[plan-ralph-loop] Phase 1: EXPLORE — You wrote plan section headings. Do NOT write a plan yet.

In this phase, you must ONLY report what you found in the codebase:

1. FILES READ: List every file you examined (full paths)
2. ARCHITECTURE: How the codebase is structured (entry points, modules, data flow)
3. RELEVANT PATTERNS: Existing patterns that affect the planned work
4. DEPENDENCIES: External and internal dependencies
5. CONSTRAINTS: Technical constraints discovered

Do NOT include headings like ## Goal, ## Steps, ## Scope, etc.

Original request:
$PROMPT_TEXT" \
        "Phase 1: EXPLORE | Do NOT write a plan yet. List your codebase findings only."
    fi

    # POSITIVE VALIDATION: must contain evidence of actual exploration (file paths)
    FILE_REF_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '(src/|lib/|\.ts|\.js|\.py|\.go|\.rs|\.java|\.jsx|\.tsx|package\.json|Cargo\.toml|go\.mod|requirements\.txt|\.config|\.json|\.md)' || true)
    if [[ "$FILE_REF_COUNT" -lt 2 ]]; then
      block_with \
        "[plan-ralph-loop] Phase 1: EXPLORE — Not enough codebase exploration detected.

Please read actual files using Read, Glob, and Grep tools. Then list your findings:

1. FILES READ: Full paths of files you examined
2. ARCHITECTURE: Code structure and data flow
3. RELEVANT PATTERNS: Patterns relevant to the task
4. DEPENDENCIES: What the project depends on
5. CONSTRAINTS: Technical limitations found

Original request:
$PROMPT_TEXT" \
        "Phase 1: EXPLORE | Read actual files and report findings. No plan yet."
    fi

    # Explore passed — advance to draft
    advance_phase
    block_with \
      "[plan-ralph-loop] Phase 2: DRAFT — Now write the plan.

Based on your exploration findings, write a complete plan with ALL required sections:
$REQUIRED_SECTIONS

Each step must reference specific files and functions you discovered in Phase 1.
Use English or Korean section headings (both accepted).

When the draft is complete, the next phase will ask you to self-critique it.
Do NOT output <promise>$COMPLETION_PROMISE</promise> yet — there will be a critique phase first.

Original request:
$PROMPT_TEXT" \
      "Phase 2: DRAFT | Write the complete plan with all required sections."
    ;;

  draft)
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
        "[plan-ralph-loop] Phase 2: DRAFT — Missing sections: $MISSING_LIST

Please add the missing sections and resubmit the complete plan.
Required sections: $REQUIRED_SECTIONS

Original request:
$PROMPT_TEXT" \
        "Phase 2: DRAFT | Missing sections: $MISSING_LIST"
    fi

    # Draft passed — advance to critique
    advance_phase
    block_with \
      "[plan-ralph-loop] Phase 3: CRITIQUE — Review your plan. Do NOT rewrite it.

Re-read the plan you just wrote. List SPECIFIC weaknesses as a numbered list.
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
7. Are effort estimates realistic?

DO NOT rewrite the plan. DO NOT output <promise>$COMPLETION_PROMISE</promise>. Just list the issues.

Original request:
$PROMPT_TEXT" \
      "Phase 3: CRITIQUE | List specific weaknesses. Do NOT rewrite or finalize."
    ;;

  critique)
    # NEGATIVE VALIDATION: must NOT contain promise tag
    if echo "$LAST_OUTPUT" | grep -qE '<promise>'; then
      block_with \
        "[plan-ralph-loop] Phase 3: CRITIQUE — Do NOT finalize during critique.

You included a <promise> tag. This phase is for identifying weaknesses ONLY.
List at least 3 specific, numbered weaknesses in the plan. No rewriting, no finalizing.

Original request:
$PROMPT_TEXT" \
        "Phase 3: CRITIQUE | Remove the promise tag. List weaknesses only."
    fi

    # POSITIVE VALIDATION: must contain at least 3 numbered items
    NUMBERED_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '^\s*[0-9]+\.' || true)
    if [[ "$NUMBERED_COUNT" -lt 3 ]]; then
      block_with \
        "[plan-ralph-loop] Phase 3: CRITIQUE — Not enough specific critiques.

Found $NUMBERED_COUNT numbered items, need at least 3.
List specific, numbered weaknesses (e.g., '1. The step ordering is wrong because...')

Consider: step ordering, edge cases, verification runnability, implicit assumptions,
vague language, breaking changes, effort estimates.

Original request:
$PROMPT_TEXT" \
        "Phase 3: CRITIQUE | Need at least 3 numbered weaknesses. Found $NUMBERED_COUNT."
    fi

    # Critique passed — advance to revise
    advance_phase
    block_with \
      "[plan-ralph-loop] Phase 4: REVISE — Rewrite the plan addressing every critique item.

Address EVERY numbered weakness from your critique. Rewrite the complete plan with all fixes applied.

Required sections: $REQUIRED_SECTIONS

When the plan is thorough and all critique items are addressed, output <promise>$COMPLETION_PROMISE</promise> at the very end.

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original request:
$PROMPT_TEXT" \
      "Phase 4: REVISE | Address all critique items. Output <promise>$COMPLETION_PROMISE</promise> when done."
    ;;

  revise|iterate)
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
      advance_phase
      block_with \
        "[plan-ralph-loop] Phase: ITERATE — Plan not yet finalized.

Continue improving the plan:
1. SELF-CRITIQUE: What is still weak, vague, or missing?
2. IMPROVE: Add concrete details, fix remaining issues.
3. FINALIZE: Output the complete plan with ALL sections ($REQUIRED_SECTIONS), then <promise>$COMPLETION_PROMISE</promise> at the very end.

IMPORTANT: You are in READ-ONLY planning mode. Do NOT edit, write, or create files.

Original request:
$PROMPT_TEXT" \
        "Phase: ITERATE | Output <promise>$COMPLETION_PROMISE</promise> when all sections are complete."
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
        "[plan-ralph-loop] Quality gate: Missing sections — $MISSING_LIST

You included <promise>$COMPLETION_PROMISE</promise> but these sections are missing:
$MISSING_LIST

Add the missing sections and re-output the complete plan with <promise>$COMPLETION_PROMISE</promise>.

Original request:
$PROMPT_TEXT" \
        "Quality gate FAILED | Missing sections: $MISSING_LIST"
    fi

    # ALL CHECKS PASSED — save and deactivate
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    bash "$PLUGIN_ROOT/scripts/save-plan.sh" "." "$LAST_OUTPUT" "completed"

    sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE"

    echo "Plan Ralph Loop complete! Plan saved to .claude/plan-output.local.md" >&2
    exit 0
    ;;

  *)
    echo "Warning: plan-ralph-loop unknown phase '$PHASE'. Deactivating." >&2
    sed_inplace "s/^active: true/active: false/" "$RALPH_STATE_FILE"
    exit 0
    ;;
esac

