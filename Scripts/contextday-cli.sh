#!/usr/bin/env bash
# Thin HTTP CLI over Agent IO :8787 (and helpers). Same tools as MCP / §2.9.
set -euo pipefail
BASE="${CONTEXTDAY_AGENTIO:-http://127.0.0.1:8787}"
cmd="${1:-help}"
shift || true

case "$cmd" in
  health)
    curl -fsS "$BASE/health"; echo
    ;;
  get_recent|search_segments|get_window|list_activity)
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
Tools: search_segments, get_recent, get_window, list_activity (read-only).
EOF
    ;;
  help|*)
    cat <<EOF
Usage: $0 <health|get_recent|search_segments|get_window|list_activity|mcp-help> [json-body]
Env: CONTEXTDAY_AGENTIO=$BASE
Example:
  $0 health
  $0 get_recent '{"limit":5}'
  $0 search_segments '{"query":"会议","track":"mic"}'
EOF
    ;;
esac
