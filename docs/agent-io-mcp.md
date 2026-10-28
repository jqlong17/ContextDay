# ContextDay Agent IO — HTTP / MCP / Grok 样例

只读工具与 Spec §2.9 一致。权威在 SQLite；不上云。

## HTTP（App 运行中）

默认绑定 `127.0.0.1` 上首个空闲端口 `18787–18797`（隐私：不监听局域网）。

```bash
curl -s http://127.0.0.1:18787/health
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
./Scripts/contextday-cli.sh search_segments '{"query":"会议","track":"mic"}'
./Scripts/contextday-cli.sh get_window '{"t0_ms":0,"t1_ms":9999999999999}'
./Scripts/contextday-cli.sh list_activity '{}'
```

`POST /v1/tools/{name}`，JSON body = 参数。非首波工具返回 501 `unavailable`。

## MCP stdio（无 GUI）

```bash
/path/to/ContextDay.app/Contents/MacOS/ContextDay --mcp
```

在 MCP 客户端配置：

| 字段 | 值 |
|------|-----|
| command | `…/ContextDay.app/Contents/MacOS/ContextDay` |
| args | `["--mcp"]` |

协议：JSON-RPC 2.0 + `Content-Length` framing；`initialize` / `tools/list` / `tools/call`。工具实现仍走 `AgentIOProtocol.dispatch`（与 HTTP 同层）。

## 剪贴板（Grok Bot 轻量路径）

App 右键「复制提示词」→ 粘贴到 Grok / 其它助手。模板见 Spec §2.8；路径随当前记录根变化；并指向仓库 [`docs/agent-skills/`](./agent-skills/)（脱敏纪要 / 日摘要 / 飞书 CLI 模板）与 Agent IO `:18787`。

建议对话开场：粘贴提示词后问「用 Agent IO get_recent 列出今天 mic 轨最近 10 条，再按 meeting-minutes 技能整理」。

## 安全

- HTTP / MCP 只读；不提供删除/改 schema 工具。
- HTTP 仅 localhost；沙盒已开 `network.server`。
- 勿把记录根或 `--mcp` 进程暴露到公网。
