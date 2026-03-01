#!/bin/bash

# Save Plan Script
# Extracts the final plan from the assistant's last message and saves it.

set -euo pipefail

CWD="${1:-.}"
LAST_MSG="${2:-}"
EXIT_REASON="${3:-completed}"

if [[ -z "$LAST_MSG" ]]; then
  echo "Warning: plansmith save has no message to save" >&2
  exit 0
fi

OUTPUT_FILE="${CWD}/.claude/plansmith-output.local.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Strip <promise>...</promise> tags from the output (multiline-safe)
CLEAN_PLAN=$(echo "$LAST_MSG" | perl -0777 -pe 's/<promise>.*?<\/promise>//gs')

cat > "$OUTPUT_FILE" <<EOF
---
generated_at: "$TIMESTAMP"
exit_reason: "$EXIT_REASON"
---

$CLEAN_PLAN
EOF

echo "Plan saved to: $OUTPUT_FILE" >&2

# --- Reflexion: extract critique learnings to persistent memory ---
STATE_FILE="${CWD}/.claude/plansmith.local.md"
MEMORY_FILE="${CWD}/.claude/plansmith-memory.local.md"

# Check if memory is enabled (default: true)
USE_MEMORY="true"
if [[ -f "$STATE_FILE" ]]; then
  STATE_FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
  USE_MEMORY_VAL=$(echo "$STATE_FM" | grep '^use_memory:' | sed 's/use_memory: *//')
  if [[ "$USE_MEMORY_VAL" == "false" ]]; then
    USE_MEMORY="false"
  fi
fi

if [[ "$EXIT_REASON" == "completed" ]] && [[ "$USE_MEMORY" == "true" ]] && [[ -f "$STATE_FILE" ]]; then
  # Extract critique rounds stored in state file
  CRITIQUES=$(sed -n '/<!-- CRITIQUE_ROUND/,/<!-- \/CRITIQUE_ROUND/p' "$STATE_FILE" | grep -vE '<!-- /?CRITIQUE_ROUND' || true)

  if [[ -n "$CRITIQUES" ]]; then
    # Tier 1: principle-based critique lines (P1 FAIL, P3 FAIL, etc.)
    # Preserves P-number context for actionable memory.
    FAIL_ITEMS=$(echo "$CRITIQUES" | grep -E '^\s*[0-9]+\.\s+P[0-9]+.*FAIL' | head -10 || true)

    if [[ -z "$FAIL_ITEMS" ]]; then
      # Tier 2: open-ended critique fallback (tighter pattern).
      # Word boundary for FAIL, colon after keywords to reduce false positives.
      FAIL_ITEMS=$(echo "$CRITIQUES" | grep -iE '\bFAIL\b|weakness:|issue:|problem:' | head -10 || true)
    fi

    if [[ -n "$FAIL_ITEMS" ]]; then
      # Get original prompt (first non-empty line after second ---)
      ORIGINAL_TASK=$(awk '/^---$/{i++; next} i>=2 && NF{print; exit}' "$STATE_FILE")

      # Get critique mode for context
      CRITIQUE_MODE_VAL=$(echo "$STATE_FM" | grep '^critique_mode:' | sed 's/critique_mode: *//' | sed 's/^"\(.*\)"$/\1/')
      CRITIQUE_MODE_VAL="${CRITIQUE_MODE_VAL:-principles}"

      cat >> "$MEMORY_FILE" <<MEMORY_EOF

---
### $TIMESTAMP
**Task**: $ORIGINAL_TASK
**Mode**: $CRITIQUE_MODE_VAL
**Issues found**:
$FAIL_ITEMS
MEMORY_EOF
      echo "Session learnings saved to: $MEMORY_FILE" >&2

      # Cap memory file to prevent unbounded growth.
      # Each session ≈ 6-10 lines. 100 lines ≈ 10-16 sessions.
      # Read side (understand.sh) uses tail -50, so 100 is more than sufficient.
      MAX_MEMORY_LINES=100
      CURRENT_LINES=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
      if [[ "$CURRENT_LINES" -gt "$MAX_MEMORY_LINES" ]]; then
        TRIMMED=$(tail -"$MAX_MEMORY_LINES" "$MEMORY_FILE")
        printf '%s\n' "$TRIMMED" > "$MEMORY_FILE"
      fi
    fi
  fi
fi
