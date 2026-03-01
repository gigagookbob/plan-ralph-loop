#!/bin/bash

# Plansmith Stop Hook
# Blocks the Stop event and injects the next phase prompt while plansmith is active.
# Phase machine: understand → explore → alternatives → draft → (critique → revise) × N
# Each phase has distinct validation and prompts.

# Prevent bash.exe.stackdump on MSYS2/Git Bash (Windows)
# Virtual CWD (/dev) has no Windows handle → skips stackdump on signal kill
PROJECT_DIR=$(pwd)
cd /dev 2>/dev/null || true

set -euo pipefail

# --- 0. Dependency check ---
for cmd in jq perl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Warning: plansmith requires '$cmd' but it's not installed." >&2
    exit 0
  fi
done

# --- Load shared helper functions ---
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

# --- 1. Read hook input from stdin ---
HOOK_INPUT=$(cat)

# --- 2. Check if planning loop is active ---
STATE_FILE="$PROJECT_DIR/.claude/plansmith.local.md"

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

# --- 5. Check max phases ---
if [[ $MAX_PHASES -gt 0 ]] && [[ $PHASE_INDEX -ge $MAX_PHASES ]]; then
  echo "Plansmith: Max phases ($MAX_PHASES) reached." >&2

  MAX_SAVE_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)
  if [[ -n "$MAX_SAVE_OUTPUT" ]]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
    if ! bash "$PLUGIN_ROOT/scripts/save.sh" "$PROJECT_DIR" "$MAX_SAVE_OUTPUT" "max_phases_reached"; then
      echo "Warning: plansmith failed to save plan to disk." >&2
    fi
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
TOTAL_PHASES=$(echo "$PHASES_STR" | tr ',' '\n' | grep -c '.' || true)
PROGRESS="[$((PHASE_INDEX + 1))/$TOTAL_PHASES]"

# --- 8. Phase dispatch ---
PHASE_DIR="${CLAUDE_PLUGIN_ROOT}/hooks/phases"
if [[ ! -d "$PHASE_DIR" ]]; then
  # Fallback for direct invocation without CLAUDE_PLUGIN_ROOT
  PHASE_DIR="$(cd "$PROJECT_DIR" && cd "$(dirname "$0")" && pwd)/phases"
fi

PHASE_FILE=""
case "$PHASE" in
  understand)      PHASE_FILE="understand.sh" ;;
  explore)         PHASE_FILE="explore.sh" ;;
  alternatives)    PHASE_FILE="alternatives.sh" ;;
  draft)           PHASE_FILE="draft.sh" ;;
  critique)        PHASE_FILE="critique.sh" ;;
  revise|iterate)  PHASE_FILE="revise.sh" ;;
  *)
    echo "Warning: plansmith unknown phase '$PHASE'. Deactivating." >&2
    sed_inplace "s/^active: true/active: false/" "$STATE_FILE"
    exit 0
    ;;
esac

if [[ ! -f "$PHASE_DIR/$PHASE_FILE" ]]; then
  echo "Warning: plansmith phase file not found: $PHASE_DIR/$PHASE_FILE. Deactivating." >&2
  sed_inplace "s/^active: true/active: false/" "$STATE_FILE"
  exit 0
fi

source "$PHASE_DIR/$PHASE_FILE"

