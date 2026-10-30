# ContextDay Agent Skills（脱敏模版）

给 Grok Bot 类助手用的**思路模版**，不含个人姓名、飞书文档 ID、客户名。

| 位置 | 用途 |
|------|------|
| 本目录 `docs/agent-skills/` | Git SSOT（脱敏；随 PR 评审） |
| Bundle `Resources/AgentSkills/` | 随 App 打包 |
| `~/Library/Application Support/ContextDay/agent-skills/` | 运行时**可发现 / 可经 Agent IO 更新**的副本 |

产品「复制提示词」只粘贴一行 `请阅读 <本目录>/README.md`（绝对路径）；设置内 **UK meeting skill shelf** 可对选中技能复制一行指向该 `.md` 的指针。详细做法见本文件与设置内「完整提示词」。Agent IO 指向 **Application Support 绝对路径**（启动时按 Bundle `VERSION` 播种）。助手可用 `list_agent_skills` / `get_agent_skill` / `update_agent_skill` / `reset_agent_skill`（见 `docs/agent-io-mcp.md`），**无需** git checkout。`get_clipboard_prompt` 可选 `name` 指向某一技能文件。

## 通用模版

| 模版 | 用途 |
|------|------|
| `meeting-minutes.md` | 从 Segment 时间线整理一场会议纪要 |
| `feishu-minutes-lark-cli.md` | 用 lark-cli 写入飞书（占位符，不写死文档） |
| `daily-meeting-digest.md` | 定时：每日晚扫整理会议；「与主人相关」标黄 todo；静默若无会 |
| `meeting-notes-weekly-wiki.md` | 周会 Wiki：合集父页 + 按周子节点；发现会议、防重复、有更新才通知 |

## UK meeting catalog（`category=uk-meeting`，`locale=en-GB`）

Stable ids / titles shared with UK landing (notes/follow.notta.uk) and web skill `uk-meeting-notes`:

| id | file | title | 用途 |
|----|------|-------|------|
| `uk-mom-detailed` | `uk-mom-detailed.md` | Detailed MoM | Decisions + actions + open questions |
| `uk-mom-brief` | `uk-mom-brief.md` | Brief | Half page / ~five bullets |
| `uk-weekly` | `uk-weekly.md` | Weekly | Compress multiple meetings into one week’s progress |
| `uk-monthly` | `uk-monthly.md` | Monthly | Theme merge + trends (not per-meeting dump) |
| `uk-followup-email` | `uk-followup-email.md` | Follow-up email | Gmail-draft oriented; **never** auto-send |

Shared hard rules in every UK skill: verifiable ContextDay content only; ambiguous commitments → TBC; no tax/legal conclusions; external-facing UK English.

配置约定：个人/团队绑定信息放本机 `AppConfig` 或用户自建 `agent-skills.local.md`（**勿提交仓库**；seed / reset 不会覆盖它）。
Routine 只保留「何时跑 + 调用哪个 skill」；结构与落盘规则写在对应 skill 文件里。
