#!/usr/bin/env bash
# Debug: inject checked-in speech fixture into running ContextDay via Agent IO.
# Requires ContextDay.app already running (Agent IO on 127.0.0.1:18787+).
# Does NOT open the mic UI path; auto-arms a debug inject session (no TCC).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${CONTEXTDAY_PCM_FIXTURE:-$ROOT/docs/fixtures/speech_16k_mono_s4.pcm}"
BASE="${CONTEXTDAY_AGENTIO:-http://127.0.0.1:18787}"
TRACK="${1:-mic}"

if [[ ! -f "$FIXTURE" ]]; then
  echo "fixture missing: $FIXTURE" >&2
  exit 1
fi

echo "== health =="
curl -fsS "$BASE/health"; echo

echo "== inject_pcm track=$TRACK path=$FIXTURE =="
# Prefer path (safer than huge base64). sample_rate 16000 matching fixture.
curl -fsS -X POST "$BASE/v1/tools/inject_pcm" \
  -H 'Content-Type: application/json' \
  -d "{\"track\":\"$TRACK\",\"path\":\"$FIXTURE\",\"sample_rate\":16000,\"auto_arm\":true}"
echo

echo "== wait for VAD→gate→ASR (~6s) =="
sleep 6

echo "== get_recent =="
curl -fsS -X POST "$BASE/v1/tools/get_recent" \
  -H 'Content-Type: application/json' \
  -d "{\"limit\":5,\"track\":\"$TRACK\"}"
echo

cat <<EOF

Notes for Mac retest (no App Store re-pack):
  1. Launch existing ContextDay.app (dev/debug build with this change).
  2. ./Scripts/pcm-inject-example.sh mic
  3. Or: curl -s -X POST http://127.0.0.1:18787/v1/tools/inject_pcm \\
       -H 'Content-Type: application/json' \\
       -d "{\"track\":\"mic\",\"path\":\"$FIXTURE\",\"sample_rate\":16000}"
  4. Poll get_recent; expect a new mic segment if models + gate accept the fixture.
EOF
