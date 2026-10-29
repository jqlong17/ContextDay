# Agent IO — 助手可用的请求/响应样例

供 Grok / MCP / 纪要技能对照。字段均为 **snake_case**；空命中返回 `[]`。  
云端 Linux **不能**跑完整双轨采集 + SenseVoice；下列样例与 `Tests/AgentIOMeetingFixtureTests` 一致：先向 SQLite **插入**模拟转写段（等同短音频 ASR 结果），再走工具往返。

父机真机：先 `./Scripts/mac-verify.sh` speak-smoke，再用 `./Scripts/contextday-cli.sh …`。

## 约定

| 项 | 值 |
|----|-----|
| Base | `http://127.0.0.1:18787`（忙碌则 18788–18797） |
| 调用 | `POST /v1/tools/{name}` + JSON body |
| 窗相交 | `get_window` / 带 `t0_ms`/`t1_ms` 的 search：**闭区间交集** |
| 摘要 | **无** `summarize_window` — 由上层助手做；工具返回 `unavailable` |

## `GET /health`（轻量）

```bash
curl -s http://127.0.0.1:18787/health
```

```json
{
  "ok": true,
  "service": "ContextDay",
  "port": 18787,
  "listening": true,
  "ui_wants_recording": false,
  "pipeline_running": false,
  "recording_desync": false,
  "last_capture_error": null
}
```

完整权限/模型/DB → `self_check`。

## Segment 工具（纪要 / Q&A）

### `search_segments` — 关键词圈选

**Request**

```http
POST /v1/tools/search_segments
Content-Type: application/json

{"query":"决议","track":"mic","t0_ms":1730160000000,"t1_ms":1730160300000}
```

**Response**（数组；示意一条）

```json
[
  {
    "audio_path": null,
    "gate_label": "speech",
    "segment_id": "11111111-2222-3333-4444-555555555555",
    "t0_ms": 1730160120000,
    "t1_ms": 1730160128000,
    "text": "决议：周五前完成上线检查清单。",
    "track": "mic",
    "tz_at_capture": "Asia/Shanghai"
  }
]
```

可选：`page`、`max_chars`（截断 `text`）。

### `get_recent` — 最近 N 条 / 近 N 小时

```bash
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
./Scripts/contextday-cli.sh get_recent '{"hours":24,"track":"mic"}'
```

```json
[
  {
    "audio_path": null,
    "gate_label": "speech",
    "segment_id": "…",
    "t0_ms": 1730160240000,
    "t1_ms": 1730160248000,
    "text": "风险：第三方回调偶发超时，先记未决。",
    "track": "mic",
    "tz_at_capture": "Asia/Shanghai"
  }
]
```

最新在前。助手可过滤 `gate_label != "speech"` 做纪要。

### `get_window` — 时间窗全量（双轨）

```bash
./Scripts/contextday-cli.sh get_window '{"t0_ms":1730160000000,"t1_ms":1730160300000}'
```

返回窗内 **mic + system** 全部相交段。系统轨 `music` **不会**从响应里抹掉麦轨 `speech`（双轨独立）。纪要技能应：**用 mic+speech 写决议/待办**；system+music 可忽略或作环境备注。

### `list_activity` — 粗粒度桶

```bash
./Scripts/contextday-cli.sh list_activity '{"t0_ms":1730160000000,"t1_ms":1730160300000}'
```

```json
[
  {
    "bucket_end_ms": 1730163600000,
    "bucket_start_ms": 1730160000000,
    "segment_count": 6,
    "track": null
  }
]
```

`track` 目前恒为 `null`（按小时合计，未分轨）— 见下方缺口。

## 诊断

```bash
./Scripts/contextday-cli.sh self_check
```

期望含：`ok`、`service`、`permissions`、`runtime`、`database`、`models`、`agent_io`、`notes`。

## 非首波（明确 stub）

```bash
curl -s -X POST http://127.0.0.1:18787/v1/tools/summarize_window \
  -H 'Content-Type: application/json' -d '{}'
```

```json
{
  "error": "unavailable",
  "tool": "summarize_window",
  "message": "not in first wave; leave summarization to the upstream assistant"
}
```

HTTP 状态 **501**。`export_audio` 同理。

## 助手提示词用法（推荐）

1. 粘贴短「助手索引」或先 `get_clipboard_prompt`。  
2. `get_window` / `search_segments` 拉 mic speech。  
3. `get_agent_skill` → `meeting-minutes.md`，按技能结构写纪要。  
4. **不要**调用 `summarize_window`。  
5. 需要回听时看 `audio_path`（相对记录根）；无文件则为 `null`。

## 与 Spec 的缺口 / 后续

| 项 | 状态 |
|----|------|
| 四 Segment 工具 + 技能工具 + `self_check` | 已实现 |
| `summarize_window` / `export_audio` | Spec 定稿 **unavailable** |
| DTO：`tz_at_capture` / `audio_path` | v0.3.6 起对外暴露（纪要友好） |
| `list_activity.track` 分轨 | 未做（桶级合计） |
| 派生 ISO-8601 时间字段 | Spec 允许另附；首波未加（用 `t0_ms` + `tz_at_capture`） |
| 无头机完整 PCM→ASR→落库 | 需父机 Mac；云端用 fixture 插入代替 |
| MCP `tools/list` 含 `self_check` | 已挂 |
