# Skill: 飞书纪要投递（Lark / Feishu CLI · 脱敏）

把已整理的会议纪要或日摘要，通过**本机已登录**的飞书 / Lark CLI 发到目标会话。

> 仓库内只有占位符。真实 `chat_id` / 应用凭证留在本机私密环境（shell 配置、本地未入库文件），**禁止**提交到 Git。

## 占位符（本机替换）

| 占位符 | 含义 |
|--------|------|
| `{FEISHU_CHAT_ID}` | 目标群 / 会话 ID |
| `{LARK_CLI}` | CLI 可执行名，如 `lark-cli` / `feishu`（以本机为准） |
| `{DOC_TITLE}` | 文档或消息标题 |
| `{MARKDOWN_BODY}` | 纪要 Markdown 正文 |

## 典型流程（示意）

1. 用 ContextDay 技能产出 Markdown（见 `meeting-minutes.md` / `daily-meeting-digest.md`）。
2. 确认本机 CLI 可用：`{LARK_CLI} --help`（或等价命令）。
3. 投递示意（**命令名与子命令因 CLI 版本而异，以本机 help 为准**）：

```bash
# 示例：将纪要作为消息发到会话（伪命令，勿照抄不存在的 flag）
{LARK_CLI} message send --chat-id "{FEISHU_CHAT_ID}" --text "{DOC_TITLE}\n\n{MARKDOWN_BODY}"
```

4. 若支持文档 API：先创建 doc，再分享到 `{FEISHU_CHAT_ID}`——具体子命令查本机 CLI 文档。

## 安全

- 不要在 PR、Issue、Skill 正文中粘贴真实 chat_id / open_id / tenant token。
- 不要把 ContextDay 记录根或 sqlite 上传到飞书，除非用户明确要求且已知情。
- Agent IO 与飞书凭证互不替代：转写仍以本机 SQLite 为准。
