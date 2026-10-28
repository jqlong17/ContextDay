# ContextDay Agent Skills（脱敏模版）

给 Grok Bot 类助手用的**思路模版**，不含个人姓名、飞书文档 ID、客户名。

| 位置 | 用途 |
|------|------|
| 本目录 `docs/agent-skills/` | Git SSOT（脱敏；随 PR 评审） |
| Bundle `Resources/AgentSkills/` | 随 App 打包 |
| `~/Library/Application Support/ContextDay/agent-skills/` | 运行时**可发现 / 可经 Agent IO 更新**的副本 |

产品「复制提示词」与 Agent IO 指向 **Application Support 绝对路径**（启动时按 Bundle `VERSION` 播种）。助手可用 `list_agent_skills` / `get_agent_skill` / `update_agent_skill` / `reset_agent_skill`（见 `docs/agent-io-mcp.md`），**无需** git checkout。

| 模版 | 用途 |
|------|------|
| `meeting-minutes.md` | 从 Segment 时间线整理一场会议纪要 |
| `feishu-minutes-lark-cli.md` | 用 lark-cli 写入飞书（占位符，不写死文档） |
| `daily-meeting-digest.md` | 定时：每日晚扫整理会议；「与主人相关」标黄 todo；静默若无会 |
| `meeting-notes-weekly-wiki.md` | 周会 Wiki：合集父页 + 按周子节点；发现会议、防重复、有更新才通知 |

配置约定：个人/团队绑定信息放本机 `AppConfig` 或用户自建 `agent-skills.local.md`（**勿提交仓库**；seed / reset 不会覆盖它）。
Routine 只保留「何时跑 + 调用哪个 skill」；结构与落盘规则写在对应 skill 文件里。
