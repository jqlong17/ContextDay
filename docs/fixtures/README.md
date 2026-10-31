# PCM inject fixtures（debug / CI）

供 Agent IO `inject_pcm` 与离线自测使用。**不是**用户留音格式。

| 文件 | 格式 | 说明 |
|------|------|------|
| `speech_16k_mono_s4.pcm` | Int16 LE mono @ **16 kHz**；约 **4s** 合成浊音 + **2s** 静音（共 ~6s，192000 bytes） | 能量足以过自适应 VAD；频谱偏人声（F0+formant），便于 YAMNet `speech` 偏置 |

同内容副本：`Tests/Fixtures/speech_16k_mono_s4.pcm`。

示例见 `Scripts/pcm-inject-example.sh`。
