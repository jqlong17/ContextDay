# Runtime models (not committed)

Binaries under this tree are **gitignored**. Fetch on a Mac (or any machine with network) before Run:

```bash
chmod +x Scripts/fetch-models.sh
./Scripts/fetch-models.sh
```

Parent may instead copy the same layout locally.

## Expected layout

```text
Resources/Models/
├── SenseVoiceSmall_int8/
│   ├── SenseVoiceSmall_int8.mlmodelc/     # Core ML int8 encoder+CTC (ANE)
│   ├── SenseVoicePreprocessor.mlmodelc/  # fp32 waveform → features
│   └── vocab.json                        # 25055 SentencePiece tokens
└── YAMNet/
    ├── yamnet.onnx
    └── yamnet_class_map.csv
```

## Sources

| Artifact | Source |
|----------|--------|
| SenseVoice Core ML int8 + preprocessor + vocab | [FluidInference/sensevoice-small-coreml](https://huggingface.co/FluidInference/sensevoice-small-coreml) |
| YAMNet ONNX | [audiomagic/yamnet-onnx](https://huggingface.co/audiomagic/yamnet-onnx) (`yamnet.onnx`) |
| YAMNet class map | [tensorflow/models …/yamnet_class_map.csv](https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/yamnet_class_map.csv) |

Override YAMNet URLs with `YAMNET_ONNX_URL` / `YAMNET_CSV_URL` if needed.

## Spec notes

- Primary ASR is **SenseVoice Core ML int8 only** — never silently fall back to SenseVoice ONNX (Spec §3.5).
- YAMNet-ONNX ~5s gate; Music preferred over Speech when tied (Spec §1.4).
- Xcode must copy `Resources/Models` into the app bundle (folder reference → Copy Bundle Resources).
