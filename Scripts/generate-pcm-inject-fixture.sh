#!/usr/bin/env bash
# Regenerate docs/fixtures/speech_zh_16k_mono.pcm (16 kHz mono Int16 LE + 2s silence).
# Prefer natural TTS; avoid buzz/formant tones (YAMNet labels those as music).
#
# Backends (first available wins):
#   1) edge-tts  (pip install edge-tts) — zh-CN neural, recommended
#   2) espeak-ng -v cmn                — offline open-source fallback
#   3) macOS `say` + afconvert         — on Apple Silicon Mac without pip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/fixtures/speech_zh_16k_mono.pcm}"
TEST_COPY="$ROOT/Tests/Fixtures/$(basename "$OUT")"
TEXT="${CONTEXTDAY_FIXTURE_TEXT:-今天天气不错，我们下午开会讨论方案。}"
VOICE_EDGE="${CONTEXTDAY_EDGE_VOICE:-zh-CN-XiaoxiaoNeural}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "text: $TEXT"
echo "out:  $OUT"

have() { command -v "$1" >/dev/null 2>&1; }

if have edge-tts || python3 -c 'import edge_tts' 2>/dev/null; then
  echo "backend: edge-tts ($VOICE_EDGE)"
  python3 - <<PY
import asyncio, pathlib
try:
    import edge_tts
except ImportError:
    raise SystemExit("pip install edge-tts")
text = """$TEXT"""
voice = "$VOICE_EDGE"
out = pathlib.Path("$TMP/speech.mp3")
async def main():
    await edge_tts.Communicate(text, voice).save(str(out))
asyncio.run(main())
print("wrote", out, out.stat().st_size)
PY
  ffmpeg -y -hide_banner -loglevel error -i "$TMP/speech.mp3" -ar 16000 -ac 1 -f s16le "$TMP/speech.pcm"
elif have espeak-ng; then
  echo "backend: espeak-ng -v cmn (robotic but speech-like)"
  espeak-ng -v cmn -s 140 "$TEXT" -w "$TMP/speech.wav"
  ffmpeg -y -hide_banner -loglevel error -i "$TMP/speech.wav" -ar 16000 -ac 1 -f s16le "$TMP/speech.pcm"
elif have say && have afconvert && have ffmpeg; then
  echo "backend: macOS say (Ting-Ting / Sin-ji if available)"
  # Prefer Mandarin voice when installed; else system default.
  if say -v '?' 2>/dev/null | grep -qi 'ting-ting\|sin-ji\|meijia\|sinji'; then
    VOICE=$(say -v '?' 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /Ting-Ting|Sin-ji|Meijia/{print $1; exit}')
    say -v "$VOICE" -o "$TMP/speech.aiff" "$TEXT"
  else
    say -o "$TMP/speech.aiff" "$TEXT"
  fi
  ffmpeg -y -hide_banner -loglevel error -i "$TMP/speech.aiff" -ar 16000 -ac 1 -f s16le "$TMP/speech.pcm"
else
  cat >&2 <<'EOF'
No TTS backend found. Install one of:
  pip install edge-tts
  brew/apt install espeak-ng ffmpeg
  (macOS) use built-in `say` + ffmpeg
EOF
  exit 1
fi

python3 - <<PY
from pathlib import Path
import array
raw = Path("$TMP/speech.pcm").read_bytes()
raw = raw[: len(raw) - (len(raw) % 2)]
a = array.array("h")
a.frombytes(raw)
# Soft peak normalize
peak = max((abs(x) for x in a), default=1)
target = int(0.45 * 32767)
if peak > target:
    scale = target / peak
    for i, x in enumerate(a):
        a[i] = int(x * scale)
thr = int(0.01 * 32768)
start, end = 0, len(a) - 1
while start < len(a) and abs(a[start]) < thr:
    start += 1
while end > start and abs(a[end]) < thr:
    end -= 1
pad = 16000 * 80 // 1000
start = max(0, start - pad)
end = min(len(a) - 1, end + pad)
body = a[start : end + 1]
if len(body) < int(3.2 * 16000):
    body = a
out = array.array("h", body)
out.extend([0] * (16000 * 2))  # trailing silence for VAD close
Path("$OUT").parent.mkdir(parents=True, exist_ok=True)
Path("$OUT").write_bytes(out.tobytes())
print(f"fixture bytes={len(out)*2} dur_s={len(out)/16000:.2f}")
PY

mkdir -p "$(dirname "$TEST_COPY")"
cp -f "$OUT" "$TEST_COPY"
echo "also copied → $TEST_COPY"
echo "done. Sandboxed inject: copy into records scratch/ or use pcm_base64 (see Scripts/pcm-inject-example.sh)."
