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
4. curl -s http://127.0.0.1:18787/health
   Expect JSON containing: "service":"ContextDay"  (and bound "port")
   If 18787 busy, App scans 18788–18797 — check Console for READY line.
   Do NOT use :8787 (often another「生活日志」node service).
5. ./Scripts/contextday-cli.sh self_check
   Expect permissions / database / models / recording_desync fields.
6. curl -s -X POST http://127.0.0.1:18787/v1/tools/get_recent -H 'Content-Type: application/json' -d '{"limit":5}'
7. 右键 → 复制提示词 → 粘贴：应为短「助手索引」（含 skills 绝对路径），不是长篇提示词全文。
8. Optional MCP: ~/Applications/ContextDay.app/Contents/MacOS/ContextDay --mcp
9. 右键 → 设置 → 关于与隐私… 核对路径与睡眠说明
10. Console / recordsRoot/logs/contextday-YYYY-MM-DD.log：权限与采集启停可检索；无转写全文。

Port override: defaults write app.contextday agentIOHTTPPort <port>
            or ContextDay --port <port>
Models: ./Scripts/fetch-models.sh  (SenseVoice / YAMNet tests XCTSkip if absent)

PCM A/B (Spec v0.3.29): see Scripts/pcm-buffer-ab.md
  defaults write app.contextday pcm_buffer_variant A|B   # restart App
  python3 Scripts/pcm-buffer-ab-sim.py                  # capacity ratio on any host
EOF
