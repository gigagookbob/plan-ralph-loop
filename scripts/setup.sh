#!/bin/bash

# Plansmith Setup Script
# Parses CLI arguments and creates the state file for in-session planning loop.
# Phase machine: understand → explore → alternatives → draft → (critique → revise) × N

set -euo pipefail

# --- Dependency check ---
for cmd in jq perl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: plansmith requires '$cmd'. Please install it." >&2
    exit 1
  fi
done

# --- Default values ---
PROMPT_PARTS=()
MAX_PHASES=10
BLOCK_TOOLS="true"
REFINE_ITERATIONS=2

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Plansmith - Planning-focused iterative loop with phase machine

USAGE:
  /plansmith:plan PROMPT [OPTIONS]

ARGUMENTS:
  PROMPT    Description of what to plan (can be multiple words)

OPTIONS:
  --max-phases <n>               Maximum phase transitions (default: 10)
  --max-iterations <n>           Alias for --max-phases
  --refine-iterations <n>        Number of critique-revise cycles, 1-4 (default: 2)
  --no-block-tools               Disable tool blocking (default: blocking ON)
  -h, --help                     Show this help

PHASES:
  understand   Analyze the problem before reading code
  explore      Read codebase, list findings (no plan writing allowed)
  alternatives Compare 2-3 approaches, choose one with justification
  draft        Write complete plan with all required sections
  critique     Self-critique: evaluate against 12 principles (no rewriting)
  revise       Rewrite plan addressing critique items, can finalize
  iterate      (fallback) Further revision if no more critique rounds remain

EXAMPLES:
  /plansmith:plan Design the authentication system --max-phases 12
  /plansmith:plan Design caching layer --refine-iterations 3
  /plansmith:plan Plan DB migration --no-block-tools

STOPPING:
  /plansmith:cancel to cancel the loop.
HELP_EOF
      exit 0
      ;;
    --max-phases|--max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: $1 must be a non-negative integer (0 = unlimited), got: $2" >&2
        exit 1
      fi
      MAX_PHASES="$2"
      shift 2
      ;;
    --refine-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --refine-iterations requires a number (1-4)" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[1-4]$ ]]; then
        echo "Error: --refine-iterations must be 1-4, got: $2" >&2
        exit 1
      fi
      REFINE_ITERATIONS="$2"
      shift 2
      ;;
    --no-block-tools)
      BLOCK_TOOLS="false"
      shift
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# Join prompt parts
PROMPT="${PROMPT_PARTS[*]}"

# Validate
if [[ -z "$PROMPT" ]]; then
  echo "Error: No planning prompt provided." >&2
  echo "" >&2
  echo "  Usage: /plansmith:plan PROMPT [OPTIONS]" >&2
  echo "  Example: /plansmith:plan Design auth system --max-phases 10" >&2
  echo "" >&2
  echo "  For help: /plansmith:plan --help" >&2
  exit 1
fi

# Build dynamic phase sequence (Self-Refine: multiple critique-revise cycles)
PHASES="understand,explore,alternatives,draft"
for ((i=1; i<=REFINE_ITERATIONS; i++)); do
  PHASES="${PHASES},critique,revise"
done

# Ensure .claude directory exists
mkdir -p .claude

# Check for existing active loop
STATE_FILE=".claude/plansmith.local.md"
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_ACTIVE=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep '^active:' | awk '{print $2}')
  if [[ "$EXISTING_ACTIVE" == "true" ]]; then
    echo "Error: A planning loop is already active. Use /plansmith:cancel first." >&2
    exit 1
  fi
fi

# Determine first phase
IFS=',' read -ra PHASE_ARR <<< "$PHASES"
FIRST_PHASE=$(echo "${PHASE_ARR[0]}" | xargs)

# Read rubric template
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TEMPLATE_FILE="${PLUGIN_ROOT}/templates/plan-rubric.md"
TEMPLATE=""
if [[ -f "$TEMPLATE_FILE" ]]; then
  TEMPLATE=$(cat "$TEMPLATE_FILE")
fi

# Read critique principles template (Constitutional AI)
CRITIQUE_TEMPLATE=""
CRITIQUE_TEMPLATE_FILE="${PLUGIN_ROOT}/templates/critique-principles.md"
if [[ -f "$CRITIQUE_TEMPLATE_FILE" ]]; then
  CRITIQUE_TEMPLATE=$(cat "$CRITIQUE_TEMPLATE_FILE")
fi

# Create state file
cat > "$STATE_FILE" <<EOF
---
active: true
phase: $FIRST_PHASE
phase_index: 0
max_phases: $MAX_PHASES
completion_promise: "PLAN_OK"
block_tools: $BLOCK_TOOLS
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
phases: "$PHASES"
refine_iterations: $REFINE_ITERATIONS
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

<!-- PROMPT -->
$PROMPT
<!-- /PROMPT -->

$TEMPLATE

$CRITIQUE_TEMPLATE
EOF

# Output setup message
cat <<EOF
Plansmith activated!

  Prompt: $PROMPT
  Phases: $PHASES
  Max phase transitions: $MAX_PHASES
  Refine iterations: $REFINE_ITERATIONS (Self-Refine)
  Tool blocking: $(if [[ "$BLOCK_TOOLS" == "true" ]]; then echo "ON (Edit/Write/Bash blocked)"; else echo "OFF"; fi)
  Starting phase: $FIRST_PHASE

The loop will progress through: $PHASES
Each phase has distinct validation — you cannot skip phases.

===================================================================
PHASE SEQUENCE
===================================================================
  understand    → Analyze the problem before reading code
  explore       → Read codebase, list findings (no plan yet)
  alternatives  → Compare 2-3 approaches, choose one
  draft         → Write complete plan with all required sections
  critique      → Evaluate against 12 principles with PASS/FAIL (×${REFINE_ITERATIONS})
  revise        → Address critiques, output <promise>PLAN_OK</promise> (×${REFINE_ITERATIONS})
===================================================================
EOF

echo ""
echo "$PROMPT"
