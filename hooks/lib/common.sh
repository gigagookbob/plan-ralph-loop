#!/bin/bash

# Shared helper functions for stop-hook.sh and phase files.
# Sourced (not executed directly) — do not add set -euo pipefail here.

# --- Portable sed in-place (macOS + Linux) ---
sed_inplace() {
  local pattern="$1" file="$2"
  local tmp="${file}.tmp.$$"
  sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"
}

# --- Advance to next phase ---
# Requires: PHASE_INDEX, PHASES_STR, STATE_FILE (set by caller)
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

# --- Block stop and inject prompt ---
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

# --- Bilingual section heading patterns (English + Korean) ---
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
