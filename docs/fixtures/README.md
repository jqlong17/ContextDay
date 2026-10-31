# PCM inject fixtures（debug / CI）

供 Agent IO `inject_pcm` 与离线自测使用。**不是**用户留音格式。

| 文件 | 格式 | 说明 |
|------|------|------|
| `speech_zh_16k_mono.pcm` | Int16 LE mono @ **16 kHz**；约 **3–4s** 中文朗读 + **2s** 静音（~170KB） | 自然语言 TTS（默认 edge-tts `zh-CN-XiaoxiaoNeural`）；目标：YAMNet `speech` / `send_asr` + SenseVoice 非空文本。**勿**再用 buzz/formant 合成音（会被标 `music`）。 |

同内容副本：`Tests/Fixtures/speech_zh_16k_mono.pcm`。

## 重新生成

```bash
./Scripts/generate-pcm-inject-fixture.sh
# 可选：CONTEXTDAY_FIXTURE_TEXT='……' CONTEXTDAY_EDGE_VOICE=zh-CN-YunxiNeural ./Scripts/generate-pcm-inject-fixture.sh
```

后端优先级：`edge-tts` → `espeak-ng -v cmn` → macOS `say`。

## 沙盒注入

App Sandbox **读不到**仓库路径。请用：

```bash
./Scripts/pcm-inject-example.sh mic          # pcm_base64（推荐）
# 或复制到记录根 scratch/ 后 path= 绝对路径
```

旧文件 `speech_16k_mono_s4.pcm`（buzz）已移除（v0.3.31）。
