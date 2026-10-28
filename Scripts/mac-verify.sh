#!/usr/bin/env bash
# Parent Mac verify after Debug install (Spec speak-smoke + XCTest).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="${DEST:-$HOME/Applications}"
SCHEME="ContextDay"
CONFIG="Debug"

echo "==> Build Debug → $DEST/ContextDay.app"
mkdir -p "$DEST"
xcodebuild \
  -project ContextDay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$ROOT/.derivedData" \
  build \
  | xcpretty 2>/dev/null || true

APP="$ROOT/.derivedData/Build/Products/$CONFIG/ContextDay.app"
if [[ ! -d "$APP" ]]; then
  # Fallback without derivedData path override
  APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/ContextDay.app' -type d 2>/dev/null | head -1 || true)
fi
if [[ -d "$APP" ]]; then
  rsync -a --delete "$APP" "$DEST/"
  echo "Installed: $DEST/ContextDay.app"
else
  echo "WARN: ContextDay.app not found — open Xcode and Product → Build, or set DEST after a local build."
fi

echo "==> XCTest (SegmentStore merge / Agent IO / YamNet bias / SenseVoice load-skip)"
xcodebuild \
  -project ContextDay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  test

cat <<'EOF'

==> Speak-smoke (manual)
1. Open ~/Applications/ContextDay.app (allow Mic / Screen Recording as prompted).
2. 右键 → 开始录音；对麦清晰说话 ≥3s；暂停。
3. 右键 → 打开记录文件夹 → sqlite3 db/contextday.sqlite \
     "SELECT track, gate_label, substr(text,1,40) FROM segment ORDER BY t0_ms DESC LIMIT 5;"
4. Optional: curl -s http://127.0.0.1:8787/health
5. Optional: POST /v1/tools/get_recent with {"limit":5}

Models: ./Scripts/fetch-models.sh  (SenseVoice / YAMNet tests XCTSkip if absent)
EOF
