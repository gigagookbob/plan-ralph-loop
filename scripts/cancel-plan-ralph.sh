#!/bin/bash

# Cancel Plan Ralph Loop
# Deactivates the planning loop state file.

set -euo pipefail

STATE_FILE=".claude/plan-ralph.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active planning loop found."
  exit 0
fi

# Read current iteration
ITERATION=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep '^iteration:' | sed 's/iteration: *//')

# Deactivate using portable sed (macOS + Linux compatible)
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed 's/^active: true/active: false/' "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

echo "Planning loop cancelled (was at iteration ${ITERATION:-unknown})."
