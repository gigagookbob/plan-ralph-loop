#!/bin/bash

# Integration tests for plansmith scripts and hooks.
# Tests each script as a black box (stdin → stdout/stderr + file side effects).
#
# Unlike test-phases.sh (which sources phase files directly), these tests
# invoke the actual scripts and hooks with crafted inputs.
#
# Usage: bash tests/test-integration.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0
TEST_TMPDIR=""
ORIGINAL_DIR="$(pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Test helpers ---

setup_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude"
}

cleanup_tmpdir() {
  cd "$ORIGINAL_DIR"
  if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

trap cleanup_tmpdir EXIT

# Create a minimal state file
create_state_file() {
  local phase="$1"
  local phase_index="${2:-0}"
  local max_phases="${3:-10}"
  cat > "$TEST_TMPDIR/.claude/plansmith.local.md" << STATEEOF
---
active: true
phase: $phase
phase_index: $phase_index
max_phases: $max_phases
phases: "understand,explore,alternatives,draft,critique,revise,critique,revise"
refine_iterations: 2
completion_promise: "PLAN_OK"
block_tools: true
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
---

<!-- PROMPT -->
Build a new feature for X.
<!-- /PROMPT -->
STATEEOF
}

# Parse a YAML value from a state file's frontmatter
get_state_value() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" | grep "^${key}:" | sed "s/${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# --- Assertion helpers ---

assert_equals() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_contains() {
  local test_name="$1" pattern="$2" text="$3"
  if echo "$text" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name — pattern '$pattern' not found"
    echo "    Got: $(echo "$text" | head -3)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" pattern="$2" text="$3"
  if ! echo "$text" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name — pattern '$pattern' should not be present"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_file_exists() {
  local test_name="$1" filepath="$2"
  if [[ -f "$filepath" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name — file not found: $filepath"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_file_not_exists() {
  local test_name="$1" filepath="$2"
  if [[ ! -f "$filepath" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name — file should not exist: $filepath"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ============================================================
# Group 1: setup.sh
# ============================================================

test_setup() {
  echo -e "\n${BOLD}=== setup.sh ===${RESET}"

  # Test 1: Default options create correct state file with 2 critique-revise cycles
  setup_tmpdir
  cd "$TEST_TMPDIR"
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" "Design auth system" > /dev/null 2>&1
  local phases
  phases=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "phases")
  assert_equals "Default: 2 critique-revise cycles" \
    "understand,explore,alternatives,draft,critique,revise,critique,revise" "$phases"
  cleanup_tmpdir

  # Test 2: --refine-iterations 1 builds single cycle
  setup_tmpdir
  cd "$TEST_TMPDIR"
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" "Plan something" --refine-iterations 1 > /dev/null 2>&1
  phases=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "phases")
  assert_equals "--refine-iterations 1: single cycle" \
    "understand,explore,alternatives,draft,critique,revise" "$phases"
  cleanup_tmpdir

  # Test 3: --max-iterations alias sets max_phases
  setup_tmpdir
  cd "$TEST_TMPDIR"
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" "Plan X" --max-iterations 5 > /dev/null 2>&1
  local max_phases
  max_phases=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "max_phases")
  assert_equals "--max-iterations sets max_phases" "5" "$max_phases"
  cleanup_tmpdir

  # Test 4: No prompt gives error
  setup_tmpdir
  cd "$TEST_TMPDIR"
  local exit_code=0
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" 2>/dev/null || exit_code=$?
  assert_equals "No prompt: exit 1" "1" "$exit_code"
  cleanup_tmpdir

  # Test 5: --refine-iterations 5 is rejected (out of range 1-4)
  setup_tmpdir
  cd "$TEST_TMPDIR"
  exit_code=0
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" "Plan Z" --refine-iterations 5 2>/dev/null || exit_code=$?
  assert_equals "--refine-iterations 5: exit 1" "1" "$exit_code"
  cleanup_tmpdir

  # Test 6: State file contains prompt markers (B-1)
  setup_tmpdir
  cd "$TEST_TMPDIR"
  CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/setup.sh" "Test prompt here" > /dev/null 2>&1
  local content
  content=$(cat "$TEST_TMPDIR/.claude/plansmith.local.md")
  assert_contains "Prompt markers present" "<!-- PROMPT -->" "$content"
  cleanup_tmpdir
}

# ============================================================
# Group 2: stop-hook.sh
# ============================================================

test_stop_hook() {
  echo -e "\n${BOLD}=== stop-hook.sh ===${RESET}"

  # Test 1: No state file exits silently
  setup_tmpdir
  local output
  output=$(cd "$TEST_TMPDIR" && echo '{"last_assistant_message": "hello"}' | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true
  assert_equals "No state file: no output" "" "$output"
  cleanup_tmpdir

  # Test 2: Valid understand output advances to EXPLORE
  setup_tmpdir
  create_state_file "understand" 0
  local hook_input
  hook_input=$(jq -n --arg msg "1. The problem is that authentication is broken when users try to login.
2. The success criteria: all login flows must work correctly without errors.
3. Constraints: we must maintain backward compatibility with the existing API.
4. Assumptions: the database schema remains unchanged.
5. Impact: all users attempting to authenticate will be affected." \
    '{"last_assistant_message": $msg}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true
  assert_contains "Understand valid → EXPLORE" "EXPLORE" "$output"
  cleanup_tmpdir

  # Test 3: Max phases reached deactivates
  setup_tmpdir
  create_state_file "understand" 5 5  # phase_index=5, max_phases=5
  hook_input=$(jq -n --arg msg "Some output" '{"last_assistant_message": $msg}')
  cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null || true
  local active
  active=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "active")
  assert_equals "Max phases: deactivated" "false" "$active"
  cleanup_tmpdir

  # Test 4: Missing last_assistant_message deactivates gracefully
  setup_tmpdir
  create_state_file "understand" 0
  output=$(cd "$TEST_TMPDIR" && echo '{}' | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>&1) || true
  active=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "active")
  assert_equals "Missing message: deactivated" "false" "$active"
  cleanup_tmpdir

  # Test 5: Prompt markers: only original prompt is injected (B-1)
  setup_tmpdir
  # Create state file with markers — template content should NOT appear in phase prompt
  cat > "$TEST_TMPDIR/.claude/plansmith.local.md" << 'MARKEREOF'
---
active: true
phase: understand
phase_index: 0
max_phases: 10
phases: "understand,explore,alternatives,draft,critique,revise,critique,revise"
refine_iterations: 2
completion_promise: "PLAN_OK"
block_tools: true
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
---

<!-- PROMPT -->
Design the auth system
<!-- /PROMPT -->

## Planning Quality Rubric
Some template content that should be excluded.
MARKEREOF
  hook_input=$(jq -n --arg msg "1. The problem is that auth is broken.
2. Success: all login flows work.
3. Constraints: backward compat.
4. Assumptions: stable DB.
5. Impact: all users." \
    '{"last_assistant_message": $msg}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true
  assert_contains "Prompt markers: original prompt in output" "Design the auth system" "$output"
  assert_not_contains "Prompt markers: template excluded" "Planning Quality Rubric" "$output"
  cleanup_tmpdir

  # Test 6: Valid explore output advances to ALTERNATIVES
  setup_tmpdir
  create_state_file "explore" 1
  hook_input=$(jq -n --arg msg "I examined the following files:
- src/auth/login.ts handles user authentication
- src/api/routes.ts defines the API endpoints
- config/database.yml has the DB configuration
The architecture follows a standard MVC pattern." \
    '{"last_assistant_message": $msg}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true
  assert_contains "Explore valid → ALTERNATIVES" "ALTERNATIVES" "$output"
  cleanup_tmpdir
}

# ============================================================
# Group 3: pretooluse-hook.sh
# ============================================================

test_pretooluse_hook() {
  echo -e "\n${BOLD}=== pretooluse-hook.sh ===${RESET}"

  # Test 1: Edit tool blocked
  setup_tmpdir
  create_state_file "draft" 3
  local output
  output=$(cd "$TEST_TMPDIR" && echo '{"tool_name": "Edit", "tool_input": {"file_path": "foo.ts"}}' | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Edit: denied" "deny" "$output"
  cleanup_tmpdir

  # Test 2: Write tool blocked
  setup_tmpdir
  create_state_file "draft" 3
  output=$(cd "$TEST_TMPDIR" && echo '{"tool_name": "Write", "tool_input": {"file_path": "foo.ts"}}' | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Write: denied" "deny" "$output"
  cleanup_tmpdir

  # Test 3: Read tool allowed (empty output = no block)
  setup_tmpdir
  create_state_file "draft" 3
  output=$(cd "$TEST_TMPDIR" && echo '{"tool_name": "Read", "tool_input": {"file_path": "foo.ts"}}' | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_equals "Read: allowed" "" "$output"
  cleanup_tmpdir

  # Test 4: Bash ls allowed
  setup_tmpdir
  create_state_file "draft" 3
  local hook_input
  hook_input=$(jq -n '{"tool_name": "Bash", "tool_input": {"command": "ls -la"}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_equals "Bash ls: allowed" "" "$output"
  cleanup_tmpdir

  # Test 5: Bash rm blocked
  setup_tmpdir
  create_state_file "draft" 3
  hook_input=$(jq -n '{"tool_name": "Bash", "tool_input": {"command": "rm -rf /tmp/foo"}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Bash rm: denied" "deny" "$output"
  cleanup_tmpdir

  # Test 6: Bash pipe blocked
  setup_tmpdir
  create_state_file "draft" 3
  hook_input=$(jq -n '{"tool_name": "Bash", "tool_input": {"command": "ls | grep foo"}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Bash pipe: denied" "deny" "$output"
  cleanup_tmpdir

  # Test 7: git log allowed
  setup_tmpdir
  create_state_file "draft" 3
  hook_input=$(jq -n '{"tool_name": "Bash", "tool_input": {"command": "git log --oneline"}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_equals "git log: allowed" "" "$output"
  cleanup_tmpdir

  # Test 8: Multiline command blocked
  setup_tmpdir
  create_state_file "draft" 3
  local multiline_cmd
  multiline_cmd=$(printf 'ls\nrm -rf /')
  hook_input=$(jq -n --arg cmd "$multiline_cmd" \
    '{"tool_name": "Bash", "tool_input": {"command": $cmd}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Multiline command: denied" "deny" "$output"
  cleanup_tmpdir

  # Test 9: Plugin script with compound command blocked
  setup_tmpdir
  create_state_file "draft" 3
  hook_input=$(jq -n --arg cmd "$PROJECT_ROOT/scripts/setup.sh && rm -rf /" \
    '{"tool_name": "Bash", "tool_input": {"command": $cmd}}')
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/pretooluse-hook.sh" 2>/dev/null) || true
  assert_contains "Plugin script + compound: denied" "deny" "$output"
  cleanup_tmpdir
}

# ============================================================
# Group 4: save.sh
# ============================================================

test_save() {
  echo -e "\n${BOLD}=== save.sh ===${RESET}"

  # Test 1: Plan output file created
  setup_tmpdir
  create_state_file "revise" 7
  bash "$PROJECT_ROOT/scripts/save.sh" "$TEST_TMPDIR" "## Goal
Fix auth.
## Steps
1. Fix it." "completed" 2>/dev/null
  assert_file_exists "Plan output created" "$TEST_TMPDIR/.claude/plansmith-output.local.md"
  cleanup_tmpdir

  # Test 2: Promise tag stripped from output
  setup_tmpdir
  create_state_file "revise" 7
  bash "$PROJECT_ROOT/scripts/save.sh" "$TEST_TMPDIR" "The plan here. <promise>PLAN_OK</promise> Done." "completed" 2>/dev/null
  local content
  content=$(cat "$TEST_TMPDIR/.claude/plansmith-output.local.md")
  assert_not_contains "Promise tag stripped" "<promise>" "$content"
  cleanup_tmpdir

}

# ============================================================
# Group 5: cancel.sh
# ============================================================

test_cancel() {
  echo -e "\n${BOLD}=== cancel.sh ===${RESET}"

  # Test 1: Active state deactivated
  setup_tmpdir
  create_state_file "draft" 3
  cd "$TEST_TMPDIR" && bash "$PROJECT_ROOT/scripts/cancel.sh" > /dev/null 2>&1
  local active
  active=$(get_state_value "$TEST_TMPDIR/.claude/plansmith.local.md" "active")
  assert_equals "Active → false" "false" "$active"
  cleanup_tmpdir

  # Test 2: No state file reports no active loop
  setup_tmpdir
  local output
  output=$(cd "$TEST_TMPDIR" && bash "$PROJECT_ROOT/scripts/cancel.sh" 2>/dev/null)
  assert_contains "No state file: 'No active'" "No active" "$output"
  cleanup_tmpdir

  # Test 3: Already inactive shows "No active" message (not "cancelled")
  setup_tmpdir
  create_state_file "draft" 3
  # Deactivate manually
  local tmp_file="${TEST_TMPDIR}/.claude/plansmith.local.md.tmp.$$"
  sed 's/^active: true/active: false/' "$TEST_TMPDIR/.claude/plansmith.local.md" > "$tmp_file"
  mv "$tmp_file" "$TEST_TMPDIR/.claude/plansmith.local.md"
  output=$(cd "$TEST_TMPDIR" && bash "$PROJECT_ROOT/scripts/cancel.sh" 2>/dev/null)
  assert_contains "Already inactive: shows 'No active'" "No active" "$output"
  assert_not_contains "Already inactive: not 'cancelled'" "cancelled" "$output"
  cleanup_tmpdir

  # Test 4: Active cancellation shows "cancelled" message
  setup_tmpdir
  create_state_file "draft" 3
  output=$(cd "$TEST_TMPDIR" && bash "$PROJECT_ROOT/scripts/cancel.sh" 2>/dev/null)
  assert_contains "Active cancel: shows 'cancelled'" "cancelled" "$output"
  cleanup_tmpdir
}

# ============================================================
# Run all tests
# ============================================================

echo -e "${BOLD}Plansmith Integration Tests${RESET}"
echo "Project root: $PROJECT_ROOT"

# Verify dependencies
for cmd in jq perl bash; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found."
    exit 1
  fi
done

test_setup
test_stop_hook
test_pretooluse_hook
test_save
test_cancel

echo -e "\n${BOLD}=== Results ===${RESET}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${RESET}"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  ${RED}Failed: $FAIL_COUNT${RESET}"
  exit 1
else
  echo -e "  Failed: 0"
  echo -e "\n${GREEN}All tests passed!${RESET}"
fi
