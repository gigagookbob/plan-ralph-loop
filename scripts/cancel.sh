#!/bin/bash

# Cancel Plansmith
# Deactivates the planning loop state file.

set -euo pipefail

# Load shared helpers (sed_inplace)
source "$(cd "$(dirname "$0")/../hooks/lib" && pwd)/common.sh"

STATE_FILE=".claude/plansmith.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active planning loop found."
  exit 0
fi

# Read current phase and index
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')
PHASE_INDEX=$(echo "$FRONTMATTER" | grep '^phase_index:' | sed 's/phase_index: *//')

# Check current state before deactivating
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | awk '{print $2}')

if [[ "$ACTIVE" == "true" ]]; then
  sed_inplace 's/^active: true/active: false/' "$STATE_FILE"
  echo "Planning loop cancelled (was at phase: ${PHASE:-unknown}, index: ${PHASE_INDEX:-unknown})."
else
  echo "No active planning loop (last phase: ${PHASE:-unknown}, index: ${PHASE_INDEX:-unknown})."
fi
