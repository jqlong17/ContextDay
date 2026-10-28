# ContextDay

本机 24h 语音上下文（Mac App Store 向），供 Grok Bot 类助手使用。

产品与技术细节以 [docs/01_spec.md](docs/01_spec.md) 为准（SSOT，当前 **v0.3.2**）。

## 在 Mac 上打开

| 项 | 值 |
|----|-----|
| Bundle ID | `app.contextday` |
| 部署 | macOS 14+ |
| 工程 | `ContextDay.xcodeproj` |

```bash
open ContextDay.xcodeproj
```

Signing → 选 Team → Run。浮控应出现在桌面附近（可被其它 App 遮盖）。

- 左键 / 右键「开始录音」「暂停录音」：同一激活路径 + 眼神微动  
- 「打开记录文件夹」：默认 `~/Downloads/ContextDay/`  
- 「复制提示词」/「修改保存文件夹…」

## 冒烟转写（模型）

模型二进制**不入库**。先拉取（或按下列路径自行拷贝）：

```bash
./Scripts/fetch-models.sh
```

```text
Resources/Models/SenseVoiceSmall_int8/
  SenseVoiceSmall_int8.mlmodelc/
  SenseVoicePreprocessor.mlmodelc/
  vocab.json
Resources/Models/YAMNet/
  yamnet.onnx
  yamnet_class_map.csv
```

来源与说明：[`Resources/Models/README.md`](Resources/Models/README.md)

- ASR：**SenseVoice Core ML int8 only**（失败须明确报错；**禁止**静默改走 SenseVoice ONNX）
- Gate：YAMNet-ONNX；Music 与 Speech 同高时 **Music 优先**

冒烟步骤：Run → 开始录音 → 对麦说话 ≥3s → 停止 → 查记录根 `db/contextday.sqlite` 是否有带 `text` 的段；门控开时纯音乐不应送 ASR。

Xcode 已将 `Resources/Models` 作为 folder reference 拷进 Bundle；并依赖 SPM `onnxruntime`（Microsoft）。

## 桌面球资源

| 资源 | 用途 |
|------|------|
| `Resources/DesktopOrb/idle.png` | 透明 idle（运行时再 chroma-key） |
| `Resources/DesktopOrb/eye-click-2s.mov`（若有）或 `.mp4` | 眼神微动；优先 `.mov` |
| `Resources/AppIcon/icon-1024.png` | 不透明炭灰底 App Icon 源 |

## 当前交付

- DesktopControl + 可配置记录根 + Agent IO §2.9 stub  
- **mic 采集 → VAD → YAMNet → SenseVoice Core ML → SQLite** 冒烟管线  
- 眼神动画结束：idle 垫底，避免闪没  

仍待：系统声轨、时间线 UI、配置页、完整 MCP、eye-click 去绿幕 rematte。
