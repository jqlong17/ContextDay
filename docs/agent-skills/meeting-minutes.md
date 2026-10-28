# Skill: 会议纪要（ContextDay → Markdown）

将本机 ContextDay 某时间窗内的转写整理为**单场会议纪要**。

## 输入

- 时间窗：`t0_ms` / `t1_ms`（UTC epoch ms），或自然语言「今天下午 3–4 点」→ 先换算本地时区再查。
- 可选：`track`（`mic` | `system`）、关键词 `query`。

## 步骤

1. 健康检查  
   `GET http://127.0.0.1:18787/health` → JSON 含 `"service":"ContextDay"`。
2. 拉段（只读）  
   `POST http://127.0.0.1:18787/v1/tools/get_window`  
   Body 示例：`{"t0_ms":…,"t1_ms":…,"track":"mic"}`  
   或 `search_segments` / `get_recent`。
3. 整理纪要（输出 Markdown），建议结构：
   - 标题 / 时间范围（本地时区） / 轨
   - 参与方（仅当转写中可推断；否则写「未识别」）
   - 决议 / 待办（带负责人占位，勿编造）
   - 要点时间线（引用 `t0_ms` 或相对时刻）
   - 不确定处单独列出；**不要臆造未出现的承诺**
4. 若用户要核对证据：按 `audio_path` 拼记录根下的绝对路径（仅当 keep_audio 开启）。

## 禁止

- 写入或删除 ContextDay SQLite / audio
- 把未脱敏的内部人名映射表、飞书 ID 写进仓库或公开回复
- 静默调用云端 ASR 替代本机 Segment.text
