#!/bin/bash

# Plan Ralph Loop PreToolUse Hook
# Blocks file-modifying tools during the planning phase.

set -euo pipefail

# --- 0. Dependency check ---
if ! command -v jq &>/dev/null; then
  exit 0
fi

# --- 1. Read hook input from stdin ---
HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name')

# --- 2. Check if planning loop is active with tool blocking ---
STATE_FILE=".claude/plan-ralph.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | awk '{print $2}')
BLOCK_TOOLS=$(echo "$FRONTMATTER" | grep '^block_tools:' | awk '{print $2}')

if [[ "$ACTIVE" != "true" ]] || [[ "$BLOCK_TOOLS" != "true" ]]; then
  exit 0
fi

# --- 3. Handle tool-specific logic ---
case "$TOOL_NAME" in
  Edit|Write|NotebookEdit)
    # Always block file-modifying tools during planning
    jq -n \
      --arg reason "[plan-ralph-loop] File modification is blocked during the planning phase. You are in READ-ONLY mode. Use Read, Glob, Grep, WebSearch, and WebFetch to explore the codebase." \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": $reason
        }
      }'
    exit 0
    ;;
  Bash)
    # Allow read-only commands only; block everything else
    COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')

    # Allow plugin's own scripts (setup, cancel, save-plan)
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    if [[ -n "$PLUGIN_ROOT" ]] && echo "$COMMAND" | grep -qF "$PLUGIN_ROOT/scripts/"; then
      exit 0
    fi

    # First: reject any compound commands, redirects, pipes, chains, subshells
    # This prevents bypass like "ls; rm -rf /", "cat foo | xargs rm", "echo x > file"
    if echo "$COMMAND" | grep -qE '[;|&>]|\$\(|`'; then
      jq -n \
        --arg reason "[plan-ralph-loop] Compound commands (pipes, chains, semicolons, redirects) are blocked during the planning phase. Use simple, single read-only commands only." \
        '{
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
          }
        }'
      exit 0
    fi

    # Then: check allowlist for single read-only commands
    if echo "$COMMAND" | grep -qE '^\s*(ls|cat|head|tail|find|grep|rg|wc|file|stat|du|df|git\s+(log|diff|status|show|branch|remote|tag|rev-parse)|pwd|echo|which|type|env|printenv|uname|hostname|date|whoami|id|tree|less|more|sort|uniq|cut|tr|comm|diff|cmp|md5sum|sha256sum|readlink|realpath|basename|dirname|test|\[|jq)(\s|$)'; then
      exit 0
    fi

    # Block everything else
    jq -n \
      --arg reason "[plan-ralph-loop] This Bash command is not in the read-only allowlist. During the planning phase, only read-only commands are allowed (ls, cat, grep, git log, git diff, find, etc.). Rewrite your command to be read-only, or wait until the planning phase is complete." \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": $reason
        }
      }'
    exit 0
    ;;
  *)
    # Allow all other tools (Read, Glob, Grep, WebSearch, WebFetch, Task, etc.)
    exit 0
    ;;
esac
