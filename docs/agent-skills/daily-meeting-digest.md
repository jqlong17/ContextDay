# Skill：每日会议整理（Routine 思路）

## 目标
定时（建议**每个工作日傍晚**晚扫）只读 ContextDay SQLite，把当天 `speech` 片段聚成「可能的会议块」，产出：
- 今日会议列表（时间段 + 一句话摘要）
- **与主人相关的待办**用醒目标记（聊天约定 `🟡 TODO`；若写入飞书 Wiki 则黄底，见下）
- 无新 speech / 无实质会议 → **本轮安静**（不刷「今日无会」）

## 如何判定「与自己相关」（启发式，可配置）
满足任一即可标黄 todo（勿过拟合）：
- 转写中出现第一人称行动：「我来」「我去」「我负责」「我明天」
- 出现本地配置的称呼别名列表 `{OWNER_ALIASES}`（本机配置，不进仓库）
- 待办句式：「…你来…」「…交给…」且宾语命中别名

无法判断时标 `⬜ 待确认`，不要强行变黄。

## 飞书周 Wiki 写入路径
需要按周落到飞书合集（父页 + `YYYY/MM/DD–MM/DD · 周会纪要` 子节点、场次 H2、相关文档、黄底主人 TODO）时：
→ 读并遵循 **`meeting-notes-weekly-wiki.md`**（结构、防重复、静默策略都在那边）。
本文件只管**本地 SQLite 摘要 + 黄 TODO 启发式**；不要在本文件重复 Wiki 版式。

单文档、用户当场指定链接时仍可用 `feishu-minutes-lark-cli.md`（先预览确认）。

## Routine 提示词骨架（可粘到 Grok Bot routine）
```
只读 ContextDay 库 {{RECORDS_ROOT}}/db/contextday.sqlite，取今日本地时区 speech 段。
按静默间隔聚成会议块，写「今日会议摘要」。
与主人相关的行动项标 🟡 TODO；其余待办普通列表。
若要写入飞书周 Wiki：再读 meeting-notes-weekly-wiki.md 并按其结构落盘（lark-cli；有实质更新才通知）。
仅本地预览时默认只发本聊天；用户说「写飞书」再选周 Wiki 或 feishu-minutes-lark-cli。
无新 speech 或已写完则本轮安静。
```

## 与「进度管理」类助手的关系
进度/周报类 skill 负责**飞书周报结构与确认流**；周会 Wiki 版式以 `meeting-notes-weekly-wiki.md` 为准。本模版负责**从本机转写抽会议与黄 todo**。对接时：先本模版产出 → 再按周 Wiki skill 或对方预览确认流写入，避免静默改飞书（周 Wiki 晚扫在「有更新」时通知即可）。
