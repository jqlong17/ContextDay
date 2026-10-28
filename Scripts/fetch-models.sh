#!/usr/bin/env bash
# Download ContextDay runtime models into Resources/Models/ (gitignored binaries).
# Spec: SenseVoice Core ML int8 primary ASR; YAMNet-ONNX gate. Never use SenseVoice ONNX.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="$ROOT/Resources/Models"
SV="$MODELS/SenseVoiceSmall_int8"
YAM="$MODELS/YAMNet"

YAM_ONNX_URL="${YAMNET_ONNX_URL:-https://huggingface.co/audiomagic/yamnet-onnx/resolve/main/yamnet.onnx}"
YAM_CSV_URL="${YAMNET_CSV_URL:-https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv}"

mkdir -p "$SV" "$YAM"

download() {
  local url="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    echo "skip (exists): $dest"
    return 0
  fi
  echo "fetch: $url"
  echo "  -> $dest"
  mkdir -p "$(dirname "$dest")"
  curl -fL --retry 3 --retry-delay 2 -o "$dest.tmp" "$url"
  mv "$dest.tmp" "$dest"
}

echo "== SenseVoice Small int8 (Core ML) =="
echo "Source: https://huggingface.co/FluidInference/sensevoice-small-coreml"
python3 - "$SV" <<'PY'
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
tmp = root / ".hf_tmp"
try:
    from huggingface_hub import snapshot_download
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "huggingface_hub"])
    from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="FluidInference/sensevoice-small-coreml",
    allow_patterns=[
        "SenseVoiceSmall_int8.mlmodelc/**",
        "SenseVoicePreprocessor.mlmodelc/**",
        "vocab.json",
    ],
    local_dir=str(tmp),
)
for name in ("SenseVoiceSmall_int8.mlmodelc", "SenseVoicePreprocessor.mlmodelc"):
    dest = root / name
    if dest.exists():
        shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
    shutil.move(str(tmp / name), str(dest))
vocab_dest = root / "vocab.json"
if vocab_dest.exists():
    vocab_dest.unlink()
shutil.move(str(tmp / "vocab.json"), str(vocab_dest))
shutil.rmtree(tmp, ignore_errors=True)
print("SenseVoice ready:", root)
PY

echo "== YAMNet ONNX + class map =="
download "$YAM_ONNX_URL" "$YAM/yamnet.onnx"
download "$YAM_CSV_URL" "$YAM/yamnet_class_map.csv"

echo
echo "Done. Expected layout:"
echo "  $SV/SenseVoiceSmall_int8.mlmodelc/"
echo "  $SV/SenseVoicePreprocessor.mlmodelc/"
echo "  $SV/vocab.json"
echo "  $YAM/yamnet.onnx"
echo "  $YAM/yamnet_class_map.csv"
