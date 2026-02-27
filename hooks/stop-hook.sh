#!/bin/bash

# Plansmith Stop Hook
# Prevents session exit when a plansmith is active.
# Implements a phase machine: explore → draft → critique → revise → iterate
# Each phase has distinct validation and prompts.

set -euo pipefail

# --- 0. Dependency check ---
for cmd in jq perl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Warning: plansmith requires '$cmd' but it's not installed." >&2
    exit 0
  fi
done

# --- Helper: portable sed in-place (macOS + Linux) ---
sed_inplace() {
  local pattern="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"
}

# --- 1. Read hook input from stdin ---
HOOK_INPUT=$(cat)

# --- 2. Check if planning loop is active ---
STATE_FILE=".claude/plansmith.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# --- 3. Parse YAML frontmatter ---
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

if [[ -z "$FRONTMATTER" ]]; then
  echo "Warning: plansmith state file has no valid YAML frontmatter. Deactivating." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE" 2>/dev/null || rm -f "$STATE_FILE"
  exit 0
fi

ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | awk '{print $2}')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
PHASE_INDEX=$(echo "$FRONTMATTER" | grep '^phase_index:' | sed 's/phase_index: *//')
MAX_PHASES=$(echo "$FRONTMATTER" | grep '^max_phases:' | sed 's/max_phases: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
REQUIRED_SECTIONS=$(echo "$FRONTMATTER" | grep '^required_sections:' | sed 's/required_sections: *//' | sed 's/^"\(.*\)"$/\1/')
PHASES_STR=$(echo "$FRONTMATTER" | grep '^phases:' | sed 's/phases: *//' | sed 's/^"\(.*\)"$/\1/')
CRITIQUE_MODE=$(echo "$FRONTMATTER" | grep '^critique_mode:' | sed 's/critique_mode: *//' | sed 's/^"\(.*\)"$/\1/')
USE_MEMORY=$(echo "$FRONTMATTER" | grep '^use_memory:' | sed 's/use_memory: *//')
CRITIQUE_MODE="${CRITIQUE_MODE:-principles}"
USE_MEMORY="${USE_MEMORY:-true}"

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Graceful fallback for old-format state files (missing phase field)
if [[ -z "$PHASE" ]]; then
  echo "Warning: plansmith state file uses old format. Deactivating." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

# --- 4. Validate numeric fields ---
if [[ ! "$PHASE_INDEX" =~ ^[0-9]+$ ]]; then
  echo "Warning: plansmith state file corrupted (phase_index: '$PHASE_INDEX'). Deactivating (file preserved for inspection)." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

if [[ ! "$MAX_PHASES" =~ ^[0-9]+$ ]]; then
  echo "Warning: plansmith state file corrupted (max_phases: '$MAX_PHASES'). Deactivating (file preserved for inspection)." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

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
  sed_inplace "s/^phase: .*/phase: $next_phase/" "$STATE_FILE"
  sed_inplace "s/^phase_index: .*/phase_index: $next_index/" "$STATE_FILE"
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
  echo "Plansmith: Max phases ($MAX_PHASES) reached." >&2

  MAX_SAVE_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)
  if [[ -n "$MAX_SAVE_OUTPUT" ]]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    bash "$PLUGIN_ROOT/scripts/save.sh" "." "$MAX_SAVE_OUTPUT" "max_phases_reached"
  fi

  sed_inplace "s/^active: true/active: false/" "$STATE_FILE"
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
  echo "Warning: plansmith could not extract assistant message. Deactivating (file preserved for inspection)." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

# Extract the original prompt (everything after closing ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

# --- 7. Progress indicator ---
TOTAL_PHASES=$(echo "$PHASES_STR" | tr ',' '\n' | wc -l | tr -d ' ')
PROGRESS="[$((PHASE_INDEX + 1))/$TOTAL_PHASES]"

# --- 8. Phase machine ---

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

  understand)
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
    if [[ "$USE_MEMORY" == "true" ]] && [[ -f ".claude/plansmith-memory.local.md" ]]; then
      MEMORY_CONTEXT=$(tail -30 ".claude/plansmith-memory.local.md")
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
    ;;

  explore)
    # NEGATIVE VALIDATION: must NOT contain plan section headings
    if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|목표|Steps|단계|Scope|범위|Non-Scope|비범위|Verification|검증|Risks|리스크|Open Questions|오픈 질문)"; then
      block_with \
        "[plansmith] $PROGRESS Phase 1: EXPLORE — You wrote plan section headings. Do NOT write a plan yet.

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
    # Path-based detection (high confidence): patterns with directory separator
    PATH_REF_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\.[a-zA-Z]+' || true)
    # Extension-based detection (broader): known file extensions
    EXT_REF_COUNT=$(echo "$LAST_OUTPUT" | grep -cE '\.(ts|js|py|go|rs|java|jsx|tsx|sh|md|yaml|yml|toml|cfg|rb|c|cpp|h|hpp|css|scss|html|xml|sql|php)(\s|$|[,;:)])' || true)
    FILE_REF_COUNT=$((PATH_REF_COUNT > EXT_REF_COUNT ? PATH_REF_COUNT : EXT_REF_COUNT))
    if [[ "$FILE_REF_COUNT" -lt 2 ]]; then
      block_with \
        "[plansmith] $PROGRESS Phase 1: EXPLORE — Not enough codebase exploration detected.

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

    # Explore passed — advance to alternatives
    advance_phase
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

  alternatives)
    # NEGATIVE VALIDATION: must NOT contain promise tag or plan headings
    if echo "$LAST_OUTPUT" | grep -qE '<promise>'; then
      block_with \
        "[plansmith] $PROGRESS Phase: ALTERNATIVES — Do NOT finalize during alternatives comparison.

Compare 2-3 approaches with pros/cons, then choose one. No plan writing, no promise tags.

Original request:
$PROMPT_TEXT" \
        "Phase: ALTERNATIVES | Remove the promise tag. Compare approaches only."
    fi
    if echo "$LAST_OUTPUT" | grep -qiE "^#+ +(Goal|목표|Steps|단계|Scope|범위|Non-Scope|비범위|Verification|검증|Risks|리스크|Open Questions|오픈 질문)"; then
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

    # Alternatives passed — advance to draft
    advance_phase
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
Use English or Korean section headings (both accepted).

When the draft is complete, the next phase will ask you to self-critique it.
Do NOT output <promise>$COMPLETION_PROMISE</promise> yet — there will be a critique phase first.

Original request:
$PROMPT_TEXT" \
      "Phase: DRAFT | Write the complete plan with all required sections."
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
        "[plansmith] $PROGRESS Phase 2: DRAFT — Missing sections: $MISSING_LIST

Please add the missing sections and resubmit the complete plan.
Required sections: $REQUIRED_SECTIONS

Original request:
$PROMPT_TEXT" \
        "Phase 2: DRAFT | Missing sections: $MISSING_LIST"
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
    ;;

  critique)
    # --- Perspective rotation for repeated critique phases ---
    # CRITIQUE_NUM counts how many times "critique" appears in phases[0..PHASE_INDEX].
    # PHASE_INDEX is the value BEFORE advance_phase() is called (advance happens after validation).
    # Example: phases="...,draft(3),critique(4),revise(5),critique(6),..."
    #   At PHASE_INDEX=4: head -n 5 -> counts 1 critique (first round)
    #   At PHASE_INDEX=6: head -n 7 -> counts 2 critiques (second round)
    CRITIQUE_NUM=$(echo "$PHASES_STR" | tr ',' '\n' | head -n $((PHASE_INDEX + 1)) | grep -c '^critique$' || echo 0)

    case "$CRITIQUE_NUM" in
      1) CRITIQUE_PERSPECTIVE="Critique from a TECHNICAL perspective: implementation correctness, edge cases, dependency ordering, error handling, performance implications." ;;
      2) CRITIQUE_PERSPECTIVE="Critique from a USER/MAINTAINABILITY perspective: Would a new developer understand this? Is documentation sufficient? What is the long-term maintenance cost?" ;;
      *) CRITIQUE_PERSPECTIVE="Critique as DEVIL'S ADVOCATE: What scenarios would make this plan fail? What are the most optimistic assumptions? What hidden complexity exists?" ;;
    esac

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

    # PRINCIPLE VALIDATION (Constitutional AI): check principle references in principles mode
    if [[ "$CRITIQUE_MODE" == "principles" ]]; then
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
    fi

    # Store critique output for Reflexion memory extraction
    echo "" >> "$STATE_FILE"
    echo "<!-- CRITIQUE_ROUND_${CRITIQUE_NUM} -->" >> "$STATE_FILE"
    echo "$LAST_OUTPUT" >> "$STATE_FILE"
    echo "<!-- /CRITIQUE_ROUND_${CRITIQUE_NUM} -->" >> "$STATE_FILE"

    # Critique passed — advance to revise
    advance_phase

    # Self-Refine: check if this revise is followed by another critique round
    IFS=',' read -ra NEXT_CHECK <<< "$PHASES_STR"
    # advance_phase increments in the state file but PHASE_INDEX shell var is still the old value
    # So the revise phase is at PHASE_INDEX+1 (just advanced), and the phase AFTER revise is PHASE_INDEX+2
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
    bash "$PLUGIN_ROOT/scripts/save.sh" "." "$LAST_OUTPUT" "completed"

    sed_inplace "s/^active: true/active: false/" "$STATE_FILE"

    echo "Plansmith complete! Plan saved to .claude/plansmith-output.local.md" >&2
    exit 0
    ;;

  *)
    echo "Warning: plansmith unknown phase '$PHASE'. Deactivating." >&2
    sed_inplace "s/^active: true/active: false/" "$STATE_FILE"
    exit 0
    ;;
esac

