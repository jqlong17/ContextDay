#!/usr/bin/env bash
# Thin HTTP CLI over Agent IO :18787 (and helpers). Same tools as MCP / §2.9.
set -euo pipefail
BASE="${CONTEXTDAY_AGENTIO:-http://127.0.0.1:18787}"
cmd="${1:-help}"
shift || true

case "$cmd" in
  health)
    curl -fsS "$BASE/health"; echo
    ;;
  get_recent|search_segments|get_window|list_activity|\
  list_agent_skills|get_agent_skill|update_agent_skill|reset_agent_skill|get_clipboard_prompt)
    body="${1:-{}}"
    curl -fsS -X POST "$BASE/v1/tools/$cmd" \
      -H 'Content-Type: application/json' \
      -d "$body"
    echo
    ;;
  mcp-help)
    cat <<'EOF'
MCP stdio (no GUI):
  /path/to/ContextDay.app/Contents/MacOS/ContextDay --mcp

Wire as an MCP server in your client with command = that binary, args = ["--mcp"].
Segment tools (read-only): search_segments, get_recent, get_window, list_activity
Skills tools (App Support): list_agent_skills, get_agent_skill, update_agent_skill,
  reset_agent_skill, get_clipboard_prompt
EOF
    ;;
  help|*)
    cat <<EOF
Usage: $0 <command> [json-body]
Commands:
  health
  get_recent | search_segments | get_window | list_activity
  list_agent_skills | get_agent_skill | update_agent_skill | reset_agent_skill | get_clipboard_prompt
  mcp-help
Env: CONTEXTDAY_AGENTIO=$BASE
Example:
  $0 health
  $0 get_recent '{"limit":5}'
  $0 list_agent_skills '{}'
  $0 get_agent_skill '{"name":"meeting-minutes.md"}'
  $0 update_agent_skill '{"name":"meeting-minutes.md","content":"# custom\\n"}'
EOF
    ;;
esac
