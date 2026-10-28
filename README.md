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
| Agent IO HTTP | `http://127.0.0.1:18787` (fallback 18787–18797) |
| Agent IO MCP | `ContextDay --mcp`（stdio） |

```bash
open ContextDay.xcodeproj
```

Signing → 选 Team → Run。浮控默认约 **64pt**（右键「调整大小」），可被其它 App 遮盖。

右键：开始/暂停录音、打开记录文件夹、复制提示词、修改保存文件夹、调整大小、设置…、时间线…、关于与隐私…

## 父机验收

```bash
./Scripts/fetch-models.sh
./Scripts/mac-verify.sh
```

Speak-smoke 后：

```bash
./Scripts/contextday-cli.sh health
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
```

MCP / Grok 样例：[docs/agent-io-mcp.md](docs/agent-io-mcp.md)  
商店审核草稿：[docs/store-review-notes.md](docs/store-review-notes.md)

### XCTest

| 套件 | 内容 |
|------|------|
| `SegmentStoreMergeTests` | gap≤2s 合并、最早 `audio_path` |
| `AgentIOServiceTests` | §2.9 四工具 + unavailable |
| `YamNetGateTests` | Music>Speech；有模型再跑 fixture |
| `SenseVoiceASRTests` | load 或 XCTSkip |
| `RetentionDiskTests` | 滚动删除 + 磁盘状态 |

## 模型

```bash
./Scripts/fetch-models.sh
```

ASR：**SenseVoice Core ML int8 only**。Gate：YAMNet；Music>Speech 同高时 Music 优先。

## 当前交付

Phase 0–4 MVP：双轨采集、合并落库、配置/时间线/隐私、HTTP + MCP stdio、磁盘守卫与睡眠停采、`ContextDayTests`。

仍待：正式公证与上架提交、Opus 比特流替换 CAF 证据档、eye-click 去绿幕 rematte。
