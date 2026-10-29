# ContextDay

本机 24h 语音上下文（Mac App Store 向），供 Grok Bot 类助手使用。

产品与技术细节以 [docs/01_spec.md](docs/01_spec.md) 为准（**MVP SSOT**，当前 **v0.3.8**）。  
Agent IO post-MVP 优化（分轨 activity / ISO / speech blocks / 统一错误与分页）见 [docs/02_spec.md](docs/02_spec.md)；样例 [docs/agent-io-samples.md](docs/agent-io-samples.md)。

助手技能模板（脱敏）：仓库 [docs/agent-skills/](docs/agent-skills/)（Git SSOT）；运行时播种到 `~/Library/Application Support/ContextDay/agent-skills/`，可经 Agent IO 读写（见 [docs/agent-io-mcp.md](docs/agent-io-mcp.md)）。

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

Signing → 选 Team → Run。浮控默认约 **64pt**（设置 → 调整大小，切换时平滑缩放），可被其它 App 遮盖。左键仅拖动浮控，**不**启停录音。

右键顶层：开始/暂停录音 · 打开记录文件夹 · 复制提示词（**短索引**）· 设置▾ · 退出。完整提示词仅在 **设置 → 查看完整提示词…** 只读查看，不经剪贴板路径导出全文。

## 父机验收

```bash
./Scripts/fetch-models.sh
./Scripts/mac-verify.sh
```

Speak-smoke 后：

```bash
./Scripts/contextday-cli.sh health
./Scripts/contextday-cli.sh self_check
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
```

### 自检（可无 UI）

`self_check` 报告：权限快照、DB 可开、模型文件是否在 Bundle、录音 UI/管线 desync、上次采集错误、Agent IO 是否在听。日志：Console（subsystem `app.contextday`）与可选 `{recordsRoot}/logs/contextday-YYYY-MM-DD.log`。

MCP / Grok 样例：[docs/agent-io-mcp.md](docs/agent-io-mcp.md)  
助手 JSON 形状：[docs/agent-io-samples.md](docs/agent-io-samples.md)  
商店审核草稿：[docs/store-review-notes.md](docs/store-review-notes.md)

### XCTest

| 套件 | 内容 |
|------|------|
| `SegmentStoreMergeTests` | gap≤2s 合并、最早 `audio_path` |
| `AgentIOServiceTests` | §2.9 四工具 + unavailable |
| `AgentIOMeetingFixtureTests` | 会议 fixture → search/get_window/… 往返 |
| `DiagnosticsSelfCheckTests` | 权限 / self_check / 短索引 |
| `YamNetGateTests` | Music>Speech；有模型再跑 fixture |
| `SenseVoiceASRTests` | load 或 XCTSkip |
| `RetentionDiskTests` | 滚动删除 + 磁盘状态 |

## 模型

```bash
./Scripts/fetch-models.sh
```

ASR：**SenseVoice Core ML int8 only**。Gate：YAMNet；Music>Speech 同高时 Music 优先。

## 当前交付

Phase 0–4 MVP：双轨采集、合并落库、配置/时间线/隐私、HTTP + MCP stdio、磁盘守卫与睡眠停采、诊断自检、`ContextDayTests`。

仍待：正式公证与上架提交、Opus 比特流替换 CAF 证据档、eye-click 去绿幕 rematte。
