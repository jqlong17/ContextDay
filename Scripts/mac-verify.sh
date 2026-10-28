#!/usr/bin/env bash
# Parent Mac verify after Debug install (Spec speak-smoke + XCTest).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="${DEST:-$HOME/Applications}"
SCHEME="ContextDay"
CONFIG="Debug"
DERIVED="${DERIVED:-$ROOT/.derivedData}"

echo "==> Build Debug → $DEST/ContextDay.app"
mkdir -p "$DEST"
xcodebuild \
  -project ContextDay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  build

APP="$DERIVED/Build/Products/$CONFIG/ContextDay.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: ContextDay.app missing at $APP" >&2
  exit 1
fi
rsync -a --delete "$APP" "$DEST/"
echo "Installed: $DEST/ContextDay.app"

echo "==> XCTest (SegmentStore merge / Agent IO / YamNet bias / SenseVoice load-skip)"
xcodebuild \
  -project ContextDay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  test

cat <<'EOF'

==> Speak-smoke (manual)
1. Open ~/Applications/ContextDay.app (allow Mic / Screen Recording as prompted).
2. 右键 → 开始录音；对麦清晰说话 ≥3s；暂停。
3. 右键 → 打开记录文件夹 → sqlite3 db/contextday.sqlite \
     "SELECT track, gate_label, substr(text,1,40) FROM segment ORDER BY t0_ms DESC LIMIT 5;"
4. curl -s http://127.0.0.1:8787/health
5. curl -s -X POST http://127.0.0.1:8787/v1/tools/get_recent -H 'Content-Type: application/json' -d '{"limit":5}'
6. Optional MCP: ~/Applications/ContextDay.app/Contents/MacOS/ContextDay --mcp
7. 右键 → 关于与隐私… 核对路径与睡眠说明

Models: ./Scripts/fetch-models.sh  (SenseVoice / YAMNet tests XCTSkip if absent)
EOF
