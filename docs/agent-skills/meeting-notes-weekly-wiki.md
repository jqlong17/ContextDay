# Skill：周会纪要 → 飞书 Wiki（按周节点）

## 何时用
定时晚扫或用户要求「把今天的会写进周会 Wiki」时。本文件管**结构与发现/落盘规则**；routine 只保留「何时跑 + 调用本 skill」。

## 占位符（本机配置，勿写进仓库）
- `{{WIKI_PARENT}}`：飞书合集父页 URL / token
- `{{OWNER}}` / `{{owner_name}}`：主人显示名（黄底 TODO 用）
- `{{LIFELOG_ROOT}}`：可选语音/活动日志根（若与 ContextDay 分目录）
- `{{RECORDS_ROOT}}`：ContextDay 记录根（库在 `{{RECORDS_ROOT}}/db/contextday.sqlite`）
- `{{CALENDAR}}`：本机日历名或日历查询约定

## Wiki 结构
1. **合集父页** `{{WIKI_PARENT}}`
2. **按周子节点**，标题：`YYYY/MM/DD–MM/DD · 周会纪要`（该周周一–周日，本地时区）
3. **场次 H2**：`YYYY-MM-DD HH:mm · 主题`
4. 每场块顺序：
   - **时间**
   - **主题**
   - **来源**（ContextDay 时间窗 / 日历事件 / 可选会议产品）
   - **相关文档**（标题 + 链接；搜不到在回报里说明）
   - **要点**
   - **TODO**

## 与主人相关的 TODO
- 聊天约定可用 `🟡 TODO`
- 写入飞书时：与 `{{owner_name}}` 相关的项用**黄底高亮**（占位文案形如 `{{owner_name}} TODO`）
- 判定启发式可复用 `daily-meeting-digest.md`（第一人称行动、本机别名等）

## 发现会议
- 多源交叉：ContextDay SQLite `speech` 时间簇 + `{{CALENDAR}}` 事件 +（可选）会议产品 API
- 过滤过短碎片、明显非会议音频
- **落盘前**先用 lark-cli 读当周子页已有 H2，标题/时间重合则跳过，防重复

## 落盘后
1. 从转写/要点里抽出提到的文档名，在飞书/本机知识库搜索
2. 搜到：标题 + 链接写入「相关文档」
3. 搜不到：在对用户的回报里点名说明，不要编造链接
4. 飞书**一律** lark-cli（可与 `feishu-minutes-lark-cli.md` 配合）；先读后写

## 通知策略
- **有实质更新**（新建场次或补了要点/TODO/文档）才回聊
- 当天无候选会、或已全部写过 → **静默**，不刷「今日无会」

## Routine 侧只留
```
每晚：调用 meeting-notes-weekly-wiki.md
WIKI={{WIKI_PARENT}} OWNER={{OWNER}} RECORDS={{RECORDS_ROOT}} CAL={{CALENDAR}}
有更新才通知。
```

## 与其它模版关系
- 单场预览、不定时 Wiki：`meeting-minutes.md`
- 用户指定单文档写入：`feishu-minutes-lark-cli.md`
- 本地晚扫摘要 + 黄 TODO（可不写 Wiki）：`daily-meeting-digest.md`（写周 Wiki 时改走本文件）
