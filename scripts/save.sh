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
    # Extract FAIL items from principle-based critiques
    FAIL_ITEMS=$(echo "$CRITIQUES" | grep -iE '(FAIL|weakness|issue|problem|missing)' | head -10 || true)

    if [[ -n "$FAIL_ITEMS" ]]; then
      # Get original prompt (first non-empty line after second ---)
      ORIGINAL_TASK=$(awk '/^---$/{i++; next} i>=2 && NF{print; exit}' "$STATE_FILE")

      cat >> "$MEMORY_FILE" <<MEMORY_EOF

---
### $TIMESTAMP
**Task**: $ORIGINAL_TASK
**Issues found**:
$FAIL_ITEMS
MEMORY_EOF
      echo "Session learnings saved to: $MEMORY_FILE" >&2
    fi
  fi
fi
