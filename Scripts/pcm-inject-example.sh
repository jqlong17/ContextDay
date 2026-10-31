#!/usr/bin/env bash
# Debug: inject checked-in Chinese speech fixture into running ContextDay via Agent IO.
# Requires ContextDay.app already running (Agent IO on 127.0.0.1:18787+).
# Does NOT open the mic UI path; auto-arms a debug inject session (no TCC).
#
# App Sandbox: the app cannot read the git checkout path. This script therefore
# injects via pcm_base64 (always works) after optionally copying into scratch/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${CONTEXTDAY_PCM_FIXTURE:-$ROOT/docs/fixtures/speech_zh_16k_mono.pcm}"
BASE="${CONTEXTDAY_AGENTIO:-http://127.0.0.1:18787}"
TRACK="${1:-mic}"

if [[ ! -f "$FIXTURE" ]]; then
  echo "fixture missing: $FIXTURE" >&2
  echo "Regenerate: ./Scripts/generate-pcm-inject-fixture.sh" >&2
  exit 1
fi

BYTES=$(wc -c <"$FIXTURE" | tr -d ' ')
DUR=$(python3 -c "print(round($BYTES/2/16000, 2))")
echo "== fixture $FIXTURE ($BYTES bytes, ~${DUR}s @16k) =="

echo "== health =="
curl -fsS "$BASE/health"; echo

# Prefer base64: works under App Sandbox without reading repo paths.
# (path= under records scratch/ also works if you copy the file there yourself.)
B64=$(base64 <"$FIXTURE" | tr -d '\n')
echo "== inject_pcm track=$TRACK via pcm_base64 (sandbox-safe) =="
RESP=$(curl -fsS -X POST "$BASE/v1/tools/inject_pcm" \
  -H 'Content-Type: application/json' \
  -d "{\"track\":\"$TRACK\",\"pcm_base64\":\"$B64\",\"sample_rate\":16000,\"auto_arm\":true}")
echo "$RESP"
echo

echo "== wait for VAD→gate→ASR (~8s) =="
sleep 8

echo "== get_recent =="
curl -fsS -X POST "$BASE/v1/tools/get_recent" \
  -H 'Content-Type: application/json' \
  -d "{\"limit\":5,\"track\":\"$TRACK\"}"
echo

cat <<EOF

Notes for Mac retest (no App Store re-pack):
  1. Launch ContextDay.app built from this branch (gate ON).
  2. ./Scripts/pcm-inject-example.sh mic
  3. Expect inject ok + a new mic segment with non-empty Chinese text
     (fixture phrase ≈「今天天气不错，我们下午开会讨论方案。」).
  4. If gate still skips: regenerate with ./Scripts/generate-pcm-inject-fixture.sh
     (edge-tts / espeak-ng / macOS say) — do NOT reuse the old buzz tone.
  5. Sandbox: do not pass repo docs/fixtures path; use this script's base64
     or copy fixture → ~/Downloads/ContextDay/scratch/ then path= that file.
EOF
