#!/bin/bash

# Plan Ralph Loop Setup Script
# Parses CLI arguments and creates the state file for in-session planning loop.

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
MAX_ITERATIONS=20
BLOCK_TOOLS="true"
REQUIRED_SECTIONS="Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
COMPLETION_PROMISE="PLAN_OK"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Plan Ralph Loop - Planning-focused iterative loop

USAGE:
  /plan-ralph PROMPT [OPTIONS]

ARGUMENTS:
  PROMPT    Description of what to plan (can be multiple words)

OPTIONS:
  --max-iterations <n>           Maximum iterations (default: 20)
  --no-block-tools               Disable tool blocking (default: blocking ON)
  --required-sections "A,B,C"    Required sections, comma-separated
                                 (default: Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions)
  --completion-promise <text>    Completion promise (default: PLAN_OK)
  -h, --help                     Show this help

DESCRIPTION:
  Forces Claude into read-only planning mode. Each iteration, Claude
  self-critiques and refines the plan. The loop only ends when all
  required sections are present and the quality gate is satisfied.

EXAMPLES:
  /plan-ralph Design the authentication system --max-iterations 10
  /plan-ralph Design the caching layer --no-block-tools
  /plan-ralph Plan DB migration --required-sections "Goal,Steps,Risks"

STOPPING:
  /cancel-plan-ralph to cancel the loop.
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --max-iterations requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations must be a positive integer, got: $2" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
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
  echo "  Example: /plan-ralph Design auth system --max-iterations 10" >&2
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
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
block_tools: $BLOCK_TOOLS
required_sections: "$REQUIRED_SECTIONS"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT

$TEMPLATE
EOF

# Output setup message
cat <<EOF
Plan Ralph Loop activated!

  Prompt: $PROMPT
  Max iterations: $MAX_ITERATIONS
  Tool blocking: $(if [[ "$BLOCK_TOOLS" == "true" ]]; then echo "ON (Edit/Write/Bash blocked)"; else echo "OFF"; fi)
  Required sections: $REQUIRED_SECTIONS
  State file: $STATE_FILE

The stop hook is now active. The loop will repeat until the quality gate is satisfied.

===================================================================
COMPLETION REQUIREMENTS
===================================================================

To complete the planning loop:
  1. All required sections ($REQUIRED_SECTIONS) must be present
  2. Output <promise>${COMPLETION_PROMISE}</promise> at the end

Rules:
  - Only output the promise when the plan is thorough and actionable
  - Self-critique and improve the plan each iteration
  - READ-ONLY mode: explore the codebase, do not modify files
===================================================================
EOF

# Echo the prompt for Claude to start working
echo ""
echo "$PROMPT"
