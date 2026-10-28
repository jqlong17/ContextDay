# ContextDay

本机 24h 语音上下文（Mac App Store 向），供 Grok Bot 类助手使用。

产品与技术细节以 [docs/01_spec.md](docs/01_spec.md) 为准（SSOT，当前 **v0.3.2**）。

## 在 Mac 上打开

| 项 | 值 |
|----|-----|
| Bundle ID | `app.contextday` |
| 部署 | macOS 14+ |
| 工程 | `ContextDay.xcodeproj` |
| 测试 | `ContextDayTests`（scheme `ContextDay`） |
| Agent IO HTTP | `http://127.0.0.1:8787` |

```bash
open ContextDay.xcodeproj
```

Signing → 选 Team → Run。浮控默认约 **64pt**（右键「调整大小」可改 48–128），可被其它 App 遮盖。

- 左键 / 右键「开始录音」「暂停录音」：同一激活路径 + 眼神微动（末帧 settle）
- 「打开记录文件夹」：默认 `~/Downloads/ContextDay/`
- 「复制提示词」/「修改保存文件夹…」/「设置…」/「时间线…」

## 父机验收（Debug → ~/Applications）

```bash
./Scripts/fetch-models.sh          # 首次：SenseVoice + YAMNet
./Scripts/mac-verify.sh            # xcodebuild test + 安装到 ~/Applications
```

或手动：

```bash
xcodebuild -project ContextDay.xcodeproj -scheme ContextDay \
  -destination 'platform=macOS' test

# Speak-smoke：打开 ~/Applications/ContextDay.app → 开始录音 → 说话 ≥3s →
# sqlite3 ~/Downloads/ContextDay/db/contextday.sqlite \
#   "SELECT track, gate_label, substr(text,1,40) FROM segment ORDER BY t0_ms DESC LIMIT 5;"
# curl -s http://127.0.0.1:8787/health
```

### XCTest 覆盖

| 套件 | 内容 |
|------|------|
| `SegmentStoreMergeTests` | gap≤2s 合并、>2s 不合并、最早 `audio_path` |
| `AgentIOServiceTests` | §2.9 四工具 + unavailable；临时 SQLite |
| `YamNetGateTests` | Music>Speech `decideLabel`；有模型时再跑 fixture 波形 |
| `SenseVoiceASRTests` | Bundle 有模型则 load；缺失则 **XCTSkip** / 明确 `modelLoadFailed` |

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

- ASR：**SenseVoice Core ML int8 only**（失败须明确报错；**禁止**静默改走 SenseVoice ONNX）
- Gate：YAMNet-ONNX；Music 与 Speech 同高时 **Music 优先**

## 当前交付

- DesktopControl（64pt 默认、调整大小、末帧 settle、设置/时间线）
- 双轨采集 → VAD → YAMNet → SenseVoice → SQLite 合并落库（可选 keep-audio）
- Agent IO §2.9 真查 + 本机 HTTP `:8787`
- `ContextDayTests` XCTest 目标

仍待：正式 MCP SDK、Opus 比特流替换 CAF 证据档、Phase 3 商店向、eye-click 去绿幕 rematte。
