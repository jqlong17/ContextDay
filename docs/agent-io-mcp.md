# ContextDay Agent IO — HTTP / MCP / Grok 样例

Segment 工具只读（MVP：[01_spec.md](01_spec.md) §2.9；优化：[02_spec.md](02_spec.md)）。助手技能模版可经同一表面读写 **Application Support** 副本（永不改 Bundle / Segment schema）。权威转写在 SQLite；不上云。

**具体请求/响应 JSON（纪要 / Q&A）**：见 [agent-io-samples.md](agent-io-samples.md)。`summarize_window` / `export_audio` 为明确 unavailable；长会议用 `list_speech_blocks`。

## HTTP（App 运行中）

默认绑定 `127.0.0.1` 上首个空闲端口 `18787–18797`（隐私：不监听局域网）。

```bash
curl -s http://127.0.0.1:18787/health
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
./Scripts/contextday-cli.sh search_segments '{"query":"会议","track":"mic"}'
./Scripts/contextday-cli.sh get_window '{"t0_ms":0,"t1_ms":9999999999999}'
./Scripts/contextday-cli.sh list_activity '{}'
./Scripts/contextday-cli.sh list_speech_blocks '{"track":"mic","gap_ms":120000}'
```

`POST /v1/tools/{name}`，JSON body = 参数。非首波 Segment 工具返回 501 `unavailable`。分页/硬顶见 02 §2.9（page×50；硬顶 500）。

### 助手技能（Application Support）

运行时技能根（可发现绝对路径）：

`~/Library/Application Support/ContextDay/agent-skills/`

由 Bundle `Resources/AgentSkills/` 按 `VERSION` 播种；**不要求**助手 git checkout 仓库。仓库 `docs/agent-skills/` 仍是 Git SSOT。

| 工具 | 参数 | 说明 |
|------|------|------|
| `list_agent_skills` | — | 列出 App Support 下 `.md` / `VERSION` |
| `get_agent_skill` | `name` | 读单个文件内容 |
| `update_agent_skill` | `name`, `content` | 覆盖 App Support 副本（永不写 Bundle） |
| `reset_agent_skill` | `name?` | 从 Bundle 重置一个或全部 packaged 模版；跳过 `agent-skills.local.md` |
| `get_clipboard_prompt` | `name?` | **一行指针**（无 `name` → `请阅读 …/README.md`，`kind=index`；有 basename → 该技能，`kind=skill`）；不是完整提示词 |
| `self_check` | — | 权限 / DB / 模型 / 录音 desync / 上次错误 / Agent IO 监听 |
| `inject_pcm` | `track?`, `path?` **或** `pcm_base64?`, `sample_rate?`, `auto_arm?` | **Debug only**（v0.3.30）：注入 mono Int16 LE 到 mic/system 环；默认 auto-arm inject session（无 TCC）。见 `docs/fixtures/` + `Scripts/pcm-inject-example.sh` |

```bash
./Scripts/contextday-cli.sh list_agent_skills '{}'
./Scripts/contextday-cli.sh get_agent_skill '{"name":"meeting-minutes.md"}'
./Scripts/contextday-cli.sh update_agent_skill '{"name":"meeting-minutes.md","content":"# custom\n"}'
./Scripts/contextday-cli.sh reset_agent_skill '{"name":"meeting-minutes.md"}'
./Scripts/contextday-cli.sh reset_agent_skill '{}'   # all packaged
./Scripts/contextday-cli.sh get_clipboard_prompt '{}'
./Scripts/contextday-cli.sh get_clipboard_prompt '{"name":"uk-mom-brief.md"}'
./Scripts/contextday-cli.sh self_check
./Scripts/pcm-inject-example.sh mic
```

## MCP stdio（无 GUI）

```bash
/path/to/ContextDay.app/Contents/MacOS/ContextDay --mcp
```

在 MCP 客户端配置：

| 字段 | 值 |
|------|-----|
| command | `…/ContextDay.app/Contents/MacOS/ContextDay` |
| args | `["--mcp"]` |

协议：JSON-RPC 2.0 + `Content-Length` framing；`initialize` / `tools/list` / `tools/call`。工具实现仍走 `AgentIOProtocol.dispatch`（与 HTTP 同层）；`tools/list` 含 Segment 工具 + 技能工具 + `self_check` + debug `inject_pcm`。

## 剪贴板索引（Grok Bot 轻量路径）

App 右键「复制提示词」→ 粘贴一行 `请阅读 …/agent-skills/README.md`。**不会**把完整专有提示词 / health / 工具列表写入剪贴板；全文仅在 App **设置 → 查看完整提示词…** 只读查看。

建议对话开场：粘贴索引后问「用 Agent IO `list_agent_skills` / `get_recent`，再按 meeting-minutes 技能整理」。

## 安全

- Segment HTTP / MCP **只读**；不提供删除/改 schema 工具。
- 技能工具仅写 Application Support；**永不**改 Bundle / 仓库。
- HTTP 仅 localhost；沙盒已开 `network.server`。
- `inject_pcm` 为 debug 注入（同环路径）；路径 allowlist；勿写入 App Store 叙事。
- 勿把记录根或 `--mcp` 进程暴露到公网。
- 个人 Feishu/Lark ID 放本机 `agent-skills.local.md` 或 AppConfig；**勿**提交仓库。
