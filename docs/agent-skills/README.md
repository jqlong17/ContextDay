# ContextDay agent skills（脱敏模板）

本目录是给 Grok Bot / MCP / 本地助手用的**只读技能模板**，与 Spec §2.8 剪贴板提示词、Agent IO HTTP（默认 `127.0.0.1:18787`）配合使用。

| 文件 | 用途 |
|------|------|
| [meeting-minutes.md](./meeting-minutes.md) | 从本机 Segment 时间线整理单场会议纪要 |
| [daily-meeting-digest.md](./daily-meeting-digest.md) | 按自然日汇总多场会议要点 |
| [feishu-minutes-lark-cli.md](./feishu-minutes-lark-cli.md) | 用飞书 / Lark CLI 投递或拉取纪要（**无个人 ID**） |

## 硬性约定

- **脱敏**：仓库内不得出现真实 Feishu/Lark `chat_id` / `open_id` / 个人邮箱 / 内部群名。用占位符（如 `{FEISHU_CHAT_ID}`），由使用者在本机私密配置中替换。
- **只读数据**：转写权威在 ContextDay SQLite；不要删改用户 `db/` / `audio/`，除非用户在对话中明确要求并再次确认。
- **Agent IO**：优先 `http://127.0.0.1:18787`（`/health` 须含 `"service":"ContextDay"`）。端口可能在 `18787–18797` 空闲扫描；以 Console READY 行为准。
- **技能不是可执行代码**：助手阅读本 Markdown 后按步骤操作；CLI 命令需本机已安装并登录对应工具。

## 推荐调用顺序

1. 确认 Agent IO：`curl -s http://127.0.0.1:18787/health`
2. 取段：`POST /v1/tools/get_window` 或 `get_recent` / `search_segments`
3. 按目标技能整理输出（纪要 / 日摘要）
4. 若需同步飞书：再读 `feishu-minutes-lark-cli.md`，用**本机私密**占位符配置执行
