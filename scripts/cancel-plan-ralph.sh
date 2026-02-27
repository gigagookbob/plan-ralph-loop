#!/bin/bash

# Cancel Plan Ralph Loop
# Deactivates the planning loop state file.

set -euo pipefail

STATE_FILE=".claude/plan-ralph.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active planning loop found."
  exit 0
fi

# Read current phase and index
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
PHASE_INDEX=$(echo "$FRONTMATTER" | grep '^phase_index:' | sed 's/phase_index: *//')

# Deactivate using portable sed (macOS + Linux compatible)
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed 's/^active: true/active: false/' "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

echo "Planning loop cancelled (was at phase: ${PHASE:-unknown}, index: ${PHASE_INDEX:-unknown})."
