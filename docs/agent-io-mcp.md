# ContextDay Agent IO — HTTP / MCP / Grok 样例

Segment 工具只读（与 Spec §2.9 一致）。助手技能模版可经同一表面读写 **Application Support** 副本（永不改 Bundle / Segment schema）。权威转写在 SQLite；不上云。

## HTTP（App 运行中）

默认绑定 `127.0.0.1` 上首个空闲端口 `18787–18797`（隐私：不监听局域网）。

```bash
curl -s http://127.0.0.1:18787/health
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
./Scripts/contextday-cli.sh search_segments '{"query":"会议","track":"mic"}'
./Scripts/contextday-cli.sh get_window '{"t0_ms":0,"t1_ms":9999999999999}'
./Scripts/contextday-cli.sh list_activity '{}'
```

`POST /v1/tools/{name}`，JSON body = 参数。非首波 Segment 工具返回 501 `unavailable`。

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
| `get_clipboard_prompt` | — | 当前「复制提示词」全文（含绝对技能路径） |

```bash
./Scripts/contextday-cli.sh list_agent_skills '{}'
./Scripts/contextday-cli.sh get_agent_skill '{"name":"meeting-minutes.md"}'
./Scripts/contextday-cli.sh update_agent_skill '{"name":"meeting-minutes.md","content":"# custom\n"}'
./Scripts/contextday-cli.sh reset_agent_skill '{"name":"meeting-minutes.md"}'
./Scripts/contextday-cli.sh reset_agent_skill '{}'   # all packaged
./Scripts/contextday-cli.sh get_clipboard_prompt '{}'
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

协议：JSON-RPC 2.0 + `Content-Length` framing；`initialize` / `tools/list` / `tools/call`。工具实现仍走 `AgentIOProtocol.dispatch`（与 HTTP 同层）；`tools/list` 含 Segment 四工具 + 上表技能工具。

## 剪贴板（Grok Bot 轻量路径）

App 右键「复制提示词」→ 粘贴到 Grok / 其它助手。路径为**本机绝对路径**：记录根 + `~/Library/Application Support/ContextDay/agent-skills/*.md` + Agent IO `127.0.0.1:18787–18797`。不依赖仓库相对路径。

建议对话开场：粘贴提示词后问「用 Agent IO `list_agent_skills` / `get_recent`，再按 meeting-minutes 技能整理」。

## 安全

- Segment HTTP / MCP **只读**；不提供删除/改 schema 工具。
- 技能工具仅写 Application Support；**永不**改 Bundle / 仓库。
- HTTP 仅 localhost；沙盒已开 `network.server`。
- 勿把记录根或 `--mcp` 进程暴露到公网。
- 个人 Feishu/Lark ID 放本机 `agent-skills.local.md` 或 AppConfig；**勿**提交仓库。
