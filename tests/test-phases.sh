#!/bin/bash

# Unit tests for plansmith phase validation logic.
# Tests each phase file by setting up the required environment (variables + functions)
# that stop-hook.sh normally provides, then sourcing the phase file.
#
# Usage: bash tests/test-phases.sh
#
# Each test captures the JSON output (what block_with would emit) and checks
# whether the phase blocked or passed as expected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE_DIR="$PROJECT_ROOT/hooks/phases"
PASS_COUNT=0
FAIL_COUNT=0
TEST_TMPDIR=""

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
  if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Create a minimal state file with given phase
create_state_file() {
  local phase="$1"
  local phase_index="${2:-0}"
  cat > "$TEST_TMPDIR/.claude/plansmith.local.md" << STATEEOF
---
active: true
phase: $phase
phase_index: $phase_index
max_phases: 10
phases: "understand,explore,alternatives,draft,critique,revise,critique,revise"
refine_iterations: 2
critique_mode: "principles"
use_memory: false
completion_promise: "PLAN_OK"
block_tools: true
required_sections: "Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
---
Build a new feature for X.

## Critique Principles

P1: Correctness
P2: Completeness
STATEEOF
}

# Set up all variables that stop-hook.sh dispatcher normally provides
setup_env() {
  local phase="$1"
  local phase_index="${2:-0}"
  local last_output="$3"

  create_state_file "$phase" "$phase_index"

  export PROJECT_DIR="$TEST_TMPDIR"
  export STATE_FILE="$TEST_TMPDIR/.claude/plansmith.local.md"
  export FRONTMATTER="active: true"
  export PHASE="$phase"
  export PHASE_INDEX="$phase_index"
  export MAX_PHASES=10
  export PHASES_STR="understand,explore,alternatives,draft,critique,revise,critique,revise"
  export COMPLETION_PROMISE="PLAN_OK"
  export REQUIRED_SECTIONS="Goal,Scope,Non-Scope,Steps,Verification,Risks,Open Questions"
  export CRITIQUE_MODE="principles"
  export USE_MEMORY="false"
  export LAST_OUTPUT="$last_output"
  export PROMPT_TEXT="Build a new feature for X."
  export TOTAL_PHASES=8
  export PROGRESS="[$((phase_index + 1))/8]"
}

# Define shared functions that phase files expect
define_functions() {
  # Portable sed in-place
  sed_inplace() {
    local pattern="$1" file="$2"
    local tmp="${file}.tmp.$$"
    sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"
  }

  # Advance phase (modifies state file)
  advance_phase() {
    local next_index=$((PHASE_INDEX + 1))
    IFS=',' read -ra PHASE_ARR <<< "$PHASES_STR"
    local next_phase
    if [[ $next_index -lt ${#PHASE_ARR[@]} ]]; then
      next_phase=$(echo "${PHASE_ARR[$next_index]}" | xargs)
    else
      next_phase="iterate"
    fi
    sed_inplace "s/^phase: .*/phase: $next_phase/" "$STATE_FILE"
    sed_inplace "s/^phase_index: .*/phase_index: $next_index/" "$STATE_FILE"
  }

  # Block with — capture output instead of exiting
  # In test mode, we write JSON to a file and use return instead of exit
  block_with() {
    local reason="$1" system_msg="$2"
    jq -n \
      --arg reason "$reason" \
      --arg msg "$system_msg" \
      '{
        "decision": "block",
        "reason": $reason,
        "systemMessage": $msg
      }' > "$TEST_TMPDIR/_block_output.json"
    # Exit the subshell — mirrors the real block_with behavior
    exit 0
  }

  # Bilingual section heading patterns
  get_section_pattern() {
    local section="$1"
    case "$section" in
      Goal)             echo "(Goal|목표)" ;;
      Scope)            echo "(Scope|범위)" ;;
      Non-Scope)        echo "(Non-Scope|Non Scope|비범위)" ;;
      Steps)            echo "(Steps|단계별 계획|단계별|단계)" ;;
      Verification)     echo "(Verification|검증)" ;;
      Risks)            echo "(Risks|Risk|리스크)" ;;
      "Open Questions") echo "(Open Questions|Open Question|오픈 질문)" ;;
      *)                echo "(${section})" ;;
    esac
  }

  export -f sed_inplace advance_phase block_with get_section_pattern
}

# Run a phase file in a subshell, capturing whether it blocked or passed
# Returns: 0 if blocked (block_with was called), 1 if passed through (no block)
run_phase() {
  local phase_file="$1"
  rm -f "$TEST_TMPDIR/_block_output.json"

  # Run in subshell to isolate exit behavior.
  # block_with calls exit 0 (same as production), terminating the subshell.
  # The outer script continues because of `|| true`.
  (
    set -euo pipefail
    define_functions
    source "$PHASE_DIR/$phase_file" 2>/dev/null
  ) || true

  if [[ -f "$TEST_TMPDIR/_block_output.json" ]]; then
    return 0  # blocked
  else
    return 1  # passed through
  fi
}

# Get the block reason from the last run_phase call
get_block_reason() {
  if [[ -f "$TEST_TMPDIR/_block_output.json" ]]; then
    jq -r '.reason' "$TEST_TMPDIR/_block_output.json"
  else
    echo "(no block)"
  fi
}

assert_blocked() {
  local test_name="$1"
  local expected_pattern="${2:-}"

  if [[ -f "$TEST_TMPDIR/_block_output.json" ]]; then
    if [[ -n "$expected_pattern" ]]; then
      local reason
      reason=$(get_block_reason)
      if echo "$reason" | grep -qiE "$expected_pattern"; then
        echo -e "  ${GREEN}PASS${RESET}: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        echo -e "  ${RED}FAIL${RESET}: $test_name — blocked but reason didn't match '$expected_pattern'"
        echo "    Got: $(echo "$reason" | head -1)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    else
      echo -e "  ${GREEN}PASS${RESET}: $test_name"
      PASS_COUNT=$((PASS_COUNT + 1))
    fi
  else
    echo -e "  ${RED}FAIL${RESET}: $test_name — expected block but phase passed through"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_blocked() {
  local test_name="$1"

  if [[ ! -f "$TEST_TMPDIR/_block_output.json" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    local reason
    reason=$(get_block_reason)
    echo -e "  ${RED}FAIL${RESET}: $test_name — expected pass but got blocked"
    echo "    Reason: $(echo "$reason" | head -1)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- UNDERSTAND phase tests ---

test_understand() {
  echo -e "\n${BOLD}=== UNDERSTAND phase ===${RESET}"

  # Test 1: Block when plan headings are present
  setup_tmpdir
  setup_env "understand" 0 "## Goal
Here is the goal of the project.
1. First point
2. Second point
3. Third point
The problem is clear."
  run_phase "understand.sh" || true
  assert_blocked "Blocks when plan headings found" "Do NOT write a plan"
  cleanup_tmpdir

  # Test 2: Block when insufficient analysis
  setup_tmpdir
  setup_env "understand" 0 "This is a short response without structure."
  run_phase "understand.sh" || true
  assert_blocked "Blocks when <3 numbered items" "Not enough problem analysis"
  cleanup_tmpdir

  # Test 3: Pass with proper analysis
  setup_tmpdir
  setup_env "understand" 0 "1. The problem is that authentication is broken when users try to login.
2. The success criteria: all login flows must work correctly without errors.
3. Constraints: we must maintain backward compatibility with the existing API.
4. Assumptions: the database schema remains unchanged.
5. Impact: all users attempting to authenticate will be affected."
  run_phase "understand.sh" || true
  assert_blocked "Passes and transitions to EXPLORE" "EXPLORE"
  cleanup_tmpdir
}

# --- EXPLORE phase tests ---

test_explore() {
  echo -e "\n${BOLD}=== EXPLORE phase ===${RESET}"

  # Test 1: Block when plan headings present
  setup_tmpdir
  setup_env "explore" 1 "## Steps
Here are the steps to implement."
  run_phase "explore.sh" || true
  assert_blocked "Blocks when plan headings found" "plan section headings"
  cleanup_tmpdir

  # Test 2: Block when no file references
  setup_tmpdir
  setup_env "explore" 1 "I looked at the codebase and found some interesting things."
  run_phase "explore.sh" || true
  assert_blocked "Blocks when no file paths found" "Not enough codebase exploration"
  cleanup_tmpdir

  # Test 3: Pass with file references
  setup_tmpdir
  setup_env "explore" 1 "I examined the following files:
- src/auth/login.ts handles user authentication
- src/api/routes.ts defines the API endpoints
- config/database.yml has the DB configuration
The architecture follows a standard MVC pattern."
  run_phase "explore.sh" || true
  assert_blocked "Passes and transitions to ALTERNATIVES" "ALTERNATIVES"
  cleanup_tmpdir
}

# --- ALTERNATIVES phase tests ---

test_alternatives() {
  echo -e "\n${BOLD}=== ALTERNATIVES phase ===${RESET}"

  # Test 1: Block when promise tag present
  setup_tmpdir
  setup_env "alternatives" 2 "Here are the options:
1. Option A
2. Option B
I recommend option A. The pros outweigh the cons.
<promise>PLAN_OK</promise>"
  run_phase "alternatives.sh" || true
  assert_blocked "Blocks when promise tag present" "Do NOT finalize"
  cleanup_tmpdir

  # Test 2: Block when plan headings present
  setup_tmpdir
  setup_env "alternatives" 2 "## Goal
1. Option A
2. Option B
I recommend A. Pros and cons analyzed."
  run_phase "alternatives.sh" || true
  assert_blocked "Blocks when plan headings found" "Do NOT write a plan"
  cleanup_tmpdir

  # Test 3: Block when missing recommendation
  setup_tmpdir
  setup_env "alternatives" 2 "1. Option A: use microservices
2. Option B: use monolith
Both have their advantages and disadvantages."
  run_phase "alternatives.sh" || true
  assert_blocked "Blocks when no recommendation keyword" "Incomplete alternatives"
  cleanup_tmpdir

  # Test 4: Pass with proper alternatives
  setup_tmpdir
  setup_env "alternatives" 2 "1. Option A: Refactor the auth module
   Pros: cleaner code, better testability
   Cons: more work upfront

2. Option B: Patch the existing code
   Pros: faster to implement
   Cons: technical debt

I recommend Option A because the pros outweigh the cons long-term."
  run_phase "alternatives.sh" || true
  assert_blocked "Passes and transitions to DRAFT" "DRAFT"
  cleanup_tmpdir
}

# --- DRAFT phase tests ---

test_draft() {
  echo -e "\n${BOLD}=== DRAFT phase ===${RESET}"

  # Test 1: Block when sections missing
  setup_tmpdir
  setup_env "draft" 3 "## Goal
Implement the feature.

## Steps
1. Do the thing."
  run_phase "draft.sh" || true
  assert_blocked "Blocks when required sections missing" "Missing sections"
  cleanup_tmpdir

  # Test 2: Pass with all sections
  setup_tmpdir
  setup_env "draft" 3 "## Goal
Implement authentication fix.

## Scope
Auth module only.

## Non-Scope
User management is out of scope.

## Steps
1. Fix the login handler
2. Update tests

## Verification
Run the test suite.

## Risks
Breaking change possible.

## Open Questions
Should we deprecate old API?"
  run_phase "draft.sh" || true
  assert_blocked "Passes and transitions to CRITIQUE" "CRITIQUE"
  cleanup_tmpdir
}

# --- CRITIQUE phase tests ---

test_critique() {
  echo -e "\n${BOLD}=== CRITIQUE phase ===${RESET}"

  # Test 1: Block when promise tag present
  setup_tmpdir
  setup_env "critique" 4 "1. Issue one
2. Issue two
3. Issue three
<promise>PLAN_OK</promise>"
  run_phase "critique.sh" || true
  assert_blocked "Blocks when promise tag present" "Do NOT finalize"
  cleanup_tmpdir

  # Test 2: Block when <3 numbered items
  setup_tmpdir
  setup_env "critique" 4 "1. One issue found.
2. Another small issue."
  run_phase "critique.sh" || true
  assert_blocked "Blocks when <3 numbered items" "Not enough specific critiques"
  cleanup_tmpdir

  # Test 3: Block when insufficient principle refs (principles mode)
  setup_tmpdir
  setup_env "critique" 4 "1. The step ordering could be improved.
2. Edge cases are not covered.
3. Verification steps are vague.
4. Missing error handling."
  run_phase "critique.sh" || true
  assert_blocked "Blocks when insufficient principle references" "Insufficient principle evaluation"
  cleanup_tmpdir

  # Test 4: Pass with proper principle-based critique
  setup_tmpdir
  setup_env "critique" 4 "1. P1 Correctness: FAIL — The login handler does not validate input.
2. P2 Completeness: PASS — All required sections are present.
3. P3 Edge Cases: FAIL — No handling for expired tokens.
4. P4 Dependencies: PASS — All imports are correct.
5. P5 Error Handling: FAIL — Missing try-catch blocks.
6. P6 Testing: PASS — Test plan is comprehensive.
7. P7 Security: PASS — No injection vulnerabilities.
8. P8 Performance: PASS — Query optimization addressed."
  run_phase "critique.sh" || true
  assert_blocked "Passes and transitions to REVISE" "REVISE"
  cleanup_tmpdir
}

# --- REVISE phase tests ---

test_revise() {
  echo -e "\n${BOLD}=== REVISE phase ===${RESET}"

  # Test 1: Block when no promise (next is critique)
  setup_tmpdir
  setup_env "revise" 5 "Here is the revised plan without a promise tag.

## Goal
Fix authentication.

## Scope
Auth module."
  run_phase "revise.sh" || true
  assert_blocked "Blocks when no promise and next is critique" "CRITIQUE"
  cleanup_tmpdir

  # Test 2: Block when no promise (last revise, next is not critique)
  setup_tmpdir
  setup_env "revise" 7 "Here is the revised plan without a promise tag."
  run_phase "revise.sh" || true
  assert_blocked "Blocks when no promise on final revise" "ITERATE"
  cleanup_tmpdir

  # Test 3: Block when promise present but sections missing
  setup_tmpdir
  setup_env "revise" 7 "## Goal
Fix authentication.

## Steps
1. Do the thing.

<promise>PLAN_OK</promise>"
  run_phase "revise.sh" || true
  assert_blocked "Blocks when promise present but sections missing" "Missing sections"
  cleanup_tmpdir

  # Test 4: Pass when promise + all sections present
  # Note: this test will try to call save.sh which may not work in test context.
  # We just verify it gets past the section check by checking no block_with on sections.
  setup_tmpdir
  setup_env "revise" 7 "## Goal
Fix authentication.

## Scope
Auth module.

## Non-Scope
User management.

## Steps
1. Fix login handler.

## Verification
Run tests.

## Risks
Breaking changes.

## Open Questions
API deprecation.

<promise>PLAN_OK</promise>"

  # Create a mock save.sh that does nothing
  mkdir -p "$TEST_TMPDIR/scripts"
  echo '#!/bin/bash' > "$TEST_TMPDIR/scripts/save.sh"
  echo 'exit 0' >> "$TEST_TMPDIR/scripts/save.sh"
  chmod +x "$TEST_TMPDIR/scripts/save.sh"

  # Override CLAUDE_PLUGIN_ROOT to use our mock
  CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR" run_phase "revise.sh" || true
  assert_not_blocked "Passes when promise + all sections present"
  cleanup_tmpdir
}

# --- Perspective rotation test ---

test_perspective_rotation() {
  echo -e "\n${BOLD}=== Critique perspective rotation ===${RESET}"

  # First critique (index 4): should be TECHNICAL
  setup_tmpdir
  setup_env "critique" 4 "Not enough items."
  run_phase "critique.sh" || true
  local reason1
  reason1=$(get_block_reason)
  if echo "$reason1" | grep -q "TECHNICAL\|technical"; then
    echo -e "  ${GREEN}PASS${RESET}: First critique uses TECHNICAL perspective"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: First critique should use TECHNICAL perspective"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  cleanup_tmpdir

  # Second critique (index 6): should be MAINTAINABILITY
  setup_tmpdir
  setup_env "critique" 6 "Not enough items."
  run_phase "critique.sh" || true
  local reason2
  reason2=$(get_block_reason)
  if echo "$reason2" | grep -q "MAINTAINABILITY\|maintainability"; then
    echo -e "  ${GREEN}PASS${RESET}: Second critique uses MAINTAINABILITY perspective"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: Second critique should use MAINTAINABILITY perspective"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  cleanup_tmpdir
}

# --- State file advancement test ---

test_state_advancement() {
  echo -e "\n${BOLD}=== State file advancement ===${RESET}"

  # After understand passes, state file should show phase: explore, phase_index: 1
  setup_tmpdir
  setup_env "understand" 0 "1. The problem is that the system fails on edge cases.
2. Success means all edge cases are handled correctly.
3. The constraint is backward compatibility must be maintained.
4. We assume the database schema is stable.
5. This impacts all API consumers."

  (
    set -euo pipefail
    define_functions
    source "$PHASE_DIR/understand.sh" 2>/dev/null
  ) > /dev/null 2>&1 || true

  local new_phase
  new_phase=$(grep '^phase: ' "$TEST_TMPDIR/.claude/plansmith.local.md" | sed 's/phase: //')
  local new_index
  new_index=$(grep '^phase_index: ' "$TEST_TMPDIR/.claude/plansmith.local.md" | sed 's/phase_index: //')

  if [[ "$new_phase" == "explore" ]] && [[ "$new_index" == "1" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: State advanced to explore (index 1)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: Expected phase=explore index=1, got phase=$new_phase index=$new_index"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  cleanup_tmpdir
}

# --- Dispatcher tests ---

test_dispatcher() {
  echo -e "\n${BOLD}=== Dispatcher (stop-hook.sh) ===${RESET}"

  # Test: unknown phase deactivates gracefully
  # stop-hook.sh uses PROJECT_DIR=$(pwd), so we must cd to the temp dir
  setup_tmpdir
  create_state_file "unknown_phase" 0
  local hook_input
  hook_input=$(jq -n --arg msg "Some output" '{"last_assistant_message": $msg}')

  local output
  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true

  local active
  active=$(grep '^active: ' "$TEST_TMPDIR/.claude/plansmith.local.md" | awk '{print $2}')
  if [[ "$active" == "false" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: Unknown phase deactivates state file"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: Unknown phase should deactivate (got active=$active)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  cleanup_tmpdir

  # Test: inactive state file exits silently
  setup_tmpdir
  create_state_file "understand" 0
  sed "s/^active: true/active: false/" "$TEST_TMPDIR/.claude/plansmith.local.md" > "$TEST_TMPDIR/.claude/plansmith.local.md.tmp" && mv "$TEST_TMPDIR/.claude/plansmith.local.md.tmp" "$TEST_TMPDIR/.claude/plansmith.local.md"
  hook_input=$(jq -n --arg msg "Some output" '{"last_assistant_message": $msg}')

  output=$(cd "$TEST_TMPDIR" && echo "$hook_input" | CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/stop-hook.sh" 2>/dev/null) || true
  if [[ -z "$output" ]]; then
    echo -e "  ${GREEN}PASS${RESET}: Inactive state file exits silently (no output)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "  ${RED}FAIL${RESET}: Inactive state file should produce no output, got: $output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  cleanup_tmpdir
}

# --- Run all tests ---

echo -e "${BOLD}Plansmith Phase Unit Tests${RESET}"
echo "Phase dir: $PHASE_DIR"

# Verify dependencies
for cmd in jq perl bash; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found."
    exit 1
  fi
done

# Verify phase files exist
for f in understand.sh explore.sh alternatives.sh draft.sh critique.sh revise.sh; do
  if [[ ! -f "$PHASE_DIR/$f" ]]; then
    echo "ERROR: Phase file not found: $PHASE_DIR/$f"
    exit 1
  fi
done

test_understand
test_explore
test_alternatives
test_draft
test_critique
test_revise
test_perspective_rotation
test_state_advancement
test_dispatcher

echo -e "\n${BOLD}=== Results ===${RESET}"
echo -e "  ${GREEN}Passed: $PASS_COUNT${RESET}"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  ${RED}Failed: $FAIL_COUNT${RESET}"
  exit 1
else
  echo -e "  Failed: 0"
  echo -e "\n${GREEN}All tests passed!${RESET}"
fi
