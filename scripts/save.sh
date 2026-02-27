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
