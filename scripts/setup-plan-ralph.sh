#!/bin/bash

# Plan Ralph Loop Setup Script
# Parses CLI arguments and creates the state file for in-session planning loop.
# Uses a phase machine: explore → draft → critique → revise

set -euo pipefail

# --- Dependency check ---
for cmd in jq perl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: plan-ralph-loop requires '$cmd'. Please install it." >&2
    exit 1
  fi
done

# --- Default values ---
PROMPT_PARTS=()
MAX_PHASES=10
BLOCK_TOOLS="true"
REQUIRED_SECTIONS="Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
COMPLETION_PROMISE="PLAN_OK"
PHASES="explore,draft,critique,revise"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Plan Ralph Loop - Planning-focused iterative loop with phase machine

USAGE:
  /plan-ralph PROMPT [OPTIONS]

ARGUMENTS:
  PROMPT    Description of what to plan (can be multiple words)

OPTIONS:
  --max-phases <n>               Maximum phase transitions (default: 10)
  --max-iterations <n>           Alias for --max-phases
  --phases "a,b,c,d"             Custom phase sequence
                                 (default: explore,draft,critique,revise)
  --skip-explore                 Skip explore phase (start with draft)
  --no-block-tools               Disable tool blocking (default: blocking ON)
  --required-sections "A,B,C"    Required sections, comma-separated
                                 (default: Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions)
  --completion-promise <text>    Completion promise (default: PLAN_OK)
  -h, --help                     Show this help

PHASES:
  explore   Read codebase, list findings (no plan writing allowed)
  draft     Write complete plan with all required sections
  critique  Self-critique: list numbered weaknesses (no rewriting)
  revise    Rewrite plan addressing critique items, can finalize
  iterate   Further critique+revision cycles if needed

EXAMPLES:
  /plan-ralph Design the authentication system --max-phases 10
  /plan-ralph Plan API refactor --skip-explore
  /plan-ralph Design caching --phases "draft,critique,revise"
  /plan-ralph Plan DB migration --no-block-tools

STOPPING:
  /cancel-plan-ralph to cancel the loop.
HELP_EOF
      exit 0
      ;;
    --max-phases|--max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: $1 requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: $1 must be a positive integer, got: $2" >&2
        exit 1
      fi
      MAX_PHASES="$2"
      shift 2
      ;;
    --phases)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --phases requires a comma-separated list" >&2
        exit 1
      fi
      PHASES="$2"
      shift 2
      ;;
    --skip-explore)
      PHASES="draft,critique,revise"
      shift
      ;;
    --no-block-tools)
      BLOCK_TOOLS="false"
      shift
      ;;
    --required-sections)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --required-sections requires a comma-separated list" >&2
        exit 1
      fi
      REQUIRED_SECTIONS="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
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
  echo "  Usage: /plan-ralph PROMPT [OPTIONS]" >&2
  echo "  Example: /plan-ralph Design auth system --max-phases 10" >&2
  echo "" >&2
  echo "  For help: /plan-ralph --help" >&2
  exit 1
fi

# Ensure .claude directory exists
mkdir -p .claude

# Check for existing active loop
STATE_FILE=".claude/plan-ralph.local.md"
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_ACTIVE=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" | grep '^active:' | awk '{print $2}')
  if [[ "$EXISTING_ACTIVE" == "true" ]]; then
    echo "Error: A planning loop is already active. Use /cancel-plan-ralph first." >&2
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

# Create state file
cat > "$STATE_FILE" <<EOF
---
active: true
phase: $FIRST_PHASE
phase_index: 0
max_phases: $MAX_PHASES
completion_promise: "$COMPLETION_PROMISE"
block_tools: $BLOCK_TOOLS
required_sections: "$REQUIRED_SECTIONS"
phases: "$PHASES"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT

$TEMPLATE
EOF

# Output setup message
cat <<EOF
Plan Ralph Loop activated!

  Prompt: $PROMPT
  Phases: $PHASES
  Max phase transitions: $MAX_PHASES
  Tool blocking: $(if [[ "$BLOCK_TOOLS" == "true" ]]; then echo "ON (Edit/Write/Bash blocked)"; else echo "OFF"; fi)
  Required sections: $REQUIRED_SECTIONS
  Starting phase: $FIRST_PHASE

The loop will progress through: $PHASES
Each phase has distinct validation — you cannot skip phases.

===================================================================
PHASE SEQUENCE
===================================================================
  explore  → Read codebase, list findings (no plan yet)
  draft    → Write complete plan with all required sections
  critique → List numbered weaknesses (no rewriting, no finalizing)
  revise   → Address all critiques, output <promise>${COMPLETION_PROMISE}</promise>
===================================================================
EOF

echo ""
echo "$PROMPT"
