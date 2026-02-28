#!/bin/bash

# Plansmith Setup Script
# Parses CLI arguments and creates the state file for in-session planning loop.
# Uses a phase machine: explore → draft → critique → revise

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
REQUIRED_SECTIONS="Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
COMPLETION_PROMISE="PLAN_OK"
PHASES="understand,explore,alternatives,draft,critique,revise"
PHASES_EXPLICIT="false"
REFINE_ITERATIONS=2
CRITIQUE_MODE="principles"
USE_MEMORY="true"

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
  --phases "a,b,c,d"             Custom phase sequence
                                 (default: understand,explore,alternatives,draft,critique,revise)
  --refine-iterations <n>        Number of critique-revise cycles, 1-4 (default: 2)
                                 Based on Self-Refine (Madaan et al., NeurIPS 2023)
  --skip-understand              Skip understand phase
  --skip-explore                 Skip explore phase
  --skip-alternatives            Skip alternatives phase
  --open-critique                Use open-ended critique instead of principle-based
                                 (default: principle-based, per Constitutional AI)
  --no-memory                    Disable session memory injection (Reflexion)
  --clear-memory                 Clear accumulated session memories
  --no-block-tools               Disable tool blocking (default: blocking ON)
  --required-sections "A,B,C"    Required sections, comma-separated
                                 (default: Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions)
  --completion-promise <text>    Completion promise (default: PLAN_OK)
  -h, --help                     Show this help

PHASES:
  understand   Analyze the problem before reading code
  explore      Read codebase, list findings (no plan writing allowed)
  alternatives Compare 2-3 approaches, choose one with justification
  draft        Write complete plan with all required sections
  critique     Self-critique: list numbered weaknesses (no rewriting)
  revise       Rewrite plan addressing critique items, can finalize
  iterate      Further critique+revision cycles if needed

EXAMPLES:
  /plansmith:plan Design the authentication system --max-phases 12
  /plansmith:plan Plan API refactor --skip-understand --skip-explore
  /plansmith:plan Design caching --phases "draft,critique,revise"
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
      PHASES_EXPLICIT="true"
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
    --open-critique)
      CRITIQUE_MODE="open"
      shift
      ;;
    --no-memory)
      USE_MEMORY="false"
      shift
      ;;
    --clear-memory)
      rm -f ".claude/plansmith-memory.local.md"
      echo "Plansmith memory cleared."
      shift
      ;;
    --skip-understand)
      PHASES=$(echo "$PHASES" | sed 's/understand,\?//' | sed 's/^,//')
      shift
      ;;
    --skip-explore)
      PHASES=$(echo "$PHASES" | sed 's/explore,\?//' | sed 's/^,//')
      shift
      ;;
    --skip-alternatives)
      PHASES=$(echo "$PHASES" | sed 's/alternatives,\?//' | sed 's/^,//')
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
  echo "  Usage: /plansmith:plan PROMPT [OPTIONS]" >&2
  echo "  Example: /plansmith:plan Design auth system --max-phases 10" >&2
  echo "" >&2
  echo "  For help: /plansmith:plan --help" >&2
  exit 1
fi

# Build dynamic phase sequence (Self-Refine: multiple critique-revise cycles)
if [[ "$PHASES_EXPLICIT" != "true" ]]; then
  PHASES="understand,explore,alternatives,draft"
  for ((i=1; i<=REFINE_ITERATIONS; i++)); do
    PHASES="${PHASES},critique,revise"
  done
fi

# Strip leading/trailing commas (defensive)
PHASES=$(echo "$PHASES" | sed 's/^,//; s/,$//')

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
if [[ "$CRITIQUE_MODE" == "principles" ]]; then
  CRITIQUE_TEMPLATE_FILE="${PLUGIN_ROOT}/templates/critique-principles.md"
  if [[ -f "$CRITIQUE_TEMPLATE_FILE" ]]; then
    CRITIQUE_TEMPLATE=$(cat "$CRITIQUE_TEMPLATE_FILE")
  fi
fi

# YAML-safe: strip characters that break double-quoted YAML values.
# Our YAML is parsed by sed (not a real parser), so escaping is impractical.
yaml_safe() {
  printf '%s' "$1" | tr -d '"\\\n\r'
}

SAFE_PROMISE=$(yaml_safe "$COMPLETION_PROMISE")
SAFE_SECTIONS=$(yaml_safe "$REQUIRED_SECTIONS")
SAFE_PHASES=$(yaml_safe "$PHASES")

# Create state file
cat > "$STATE_FILE" <<EOF
---
active: true
phase: $FIRST_PHASE
phase_index: 0
max_phases: $MAX_PHASES
completion_promise: "$SAFE_PROMISE"
block_tools: $BLOCK_TOOLS
required_sections: "$SAFE_SECTIONS"
phases: "$SAFE_PHASES"
refine_iterations: $REFINE_ITERATIONS
critique_mode: "$CRITIQUE_MODE"
use_memory: $USE_MEMORY
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT

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
  Critique mode: $CRITIQUE_MODE ($(if [[ "$CRITIQUE_MODE" == "principles" ]]; then echo "Constitutional AI"; else echo "open-ended"; fi))
  Session memory: $(if [[ "$USE_MEMORY" == "true" ]]; then echo "ON (Reflexion)"; else echo "OFF"; fi)
  Tool blocking: $(if [[ "$BLOCK_TOOLS" == "true" ]]; then echo "ON (Edit/Write/Bash blocked)"; else echo "OFF"; fi)
  Required sections: $REQUIRED_SECTIONS
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
  critique      → Evaluate against principles / list weaknesses (×${REFINE_ITERATIONS})
  revise        → Address critiques, output <promise>${COMPLETION_PROMISE}</promise> (×${REFINE_ITERATIONS})
===================================================================
EOF

echo ""
echo "$PROMPT"
