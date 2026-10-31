# Agent IO — 助手可用的请求/响应样例

供 Grok / MCP / 纪要技能对照。字段均为 **snake_case**；空命中返回 `[]`。  
合同：**MVP 首波**见 [`01_spec.md`](01_spec.md) §2.9；**优化轨**（分轨 activity / ISO / speech blocks / 统一错误 / 分页）见 [`02_spec.md`](02_spec.md)。

云端 Linux **不能**跑完整双轨采集 + SenseVoice；下列样例与 `Tests/AgentIOMeetingFixtureTests` 一致：先向 SQLite **插入**模拟转写段，再走工具往返。

父机真机：先 `./Scripts/mac-verify.sh` speak-smoke，再用 `./Scripts/contextday-cli.sh …`。

## 约定

| 项 | 值 |
|----|-----|
| Base | `http://127.0.0.1:18787`（忙碌则 18788–18797） |
| 调用 | `POST /v1/tools/{name}` + JSON body |
| 窗相交 | `get_window` / 带 `t0_ms`/`t1_ms` 的 search：**闭区间交集** |
| 权威时间 | `t0_ms` / `t1_ms`（UTC epoch ms）；`t0_iso` / `t1_iso` 为派生 |
| 分页 | `search_segments`：`page`×**50**；`get_recent`/`get_window`/扫描类硬顶 **500**（02 §2.9） |
| 摘要 | **无** `summarize_window` — 由上层助手做；长会议用 `list_speech_blocks` |
| 错误 | 统一 `{ "error", "message", "tool"? }` |

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
    "t0_iso": "2024-10-29T08:02:00.000+08:00",
    "t0_ms": 1730160120000,
    "t1_iso": "2024-10-29T08:02:08.000+08:00",
    "t1_ms": 1730160128000,
    "text": "决议：周五前完成上线检查清单。",
    "track": "mic",
    "tz_at_capture": "Asia/Shanghai"
  }
]
```

可选：`page`（0-based，页大小 50）、`max_chars`（截断 `text`）。

### `get_recent` — 最近 N 条 / 近 N 小时

```bash
./Scripts/contextday-cli.sh get_recent '{"limit":5}'
./Scripts/contextday-cli.sh get_recent '{"hours":24,"track":"mic"}'
```

最新在前；`limit` 硬顶 500。段对象同样含 `t0_iso` / `t1_iso`。

### `get_window` — 时间窗全量（双轨）

```bash
./Scripts/contextday-cli.sh get_window '{"t0_ms":1730160000000,"t1_ms":1730160300000}'
```

返回窗内 **mic + system** 全部相交段（硬顶 500）。若恰好 500 条，假定可能截断 → 改用下方 `list_speech_blocks`。系统轨 `music` **不会**从响应里抹掉麦轨 `speech`。

### `list_activity` — 分轨小时密度（02）

```bash
./Scripts/contextday-cli.sh list_activity '{"t0_ms":1730160000000,"t1_ms":1730160300000}'
./Scripts/contextday-cli.sh list_activity '{"t0_ms":1730160000000,"t1_ms":1730160300000,"include_total":false}'
```

```json
[
  {
    "bucket_end_iso": "2024-10-29T09:00:00.000+08:00",
    "bucket_end_ms": 1730163600000,
    "bucket_start_iso": "2024-10-29T08:00:00.000+08:00",
    "bucket_start_ms": 1730160000000,
    "music_count": 0,
    "other_count": 0,
    "segment_count": 5,
    "speech_count": 5,
    "track": "mic"
  },
  {
    "bucket_end_iso": "2024-10-29T09:00:00.000+08:00",
    "bucket_end_ms": 1730163600000,
    "bucket_start_iso": "2024-10-29T08:00:00.000+08:00",
    "bucket_start_ms": 1730160000000,
    "music_count": 1,
    "other_count": 0,
    "segment_count": 1,
    "speech_count": 0,
    "track": "system"
  },
  {
    "bucket_end_iso": "2024-10-29T09:00:00.000+08:00",
    "bucket_end_ms": 1730163600000,
    "bucket_start_iso": "2024-10-29T08:00:00.000+08:00",
    "bucket_start_ms": 1730160000000,
    "music_count": 1,
    "other_count": 0,
    "segment_count": 6,
    "speech_count": 5,
    "track": null
  }
]
```

默认 `include_total=true`（含 `track: null` 合计行）。看开会密度优先读 **mic** 行的 `speech_count`。

### `list_speech_blocks` — 连续 speech 块元数据（02；非摘要）

长会议推荐路径：`list_activity` → 本工具 → 每块 `get_window`。**不要**调用 `summarize_window`。

```bash
./Scripts/contextday-cli.sh list_speech_blocks '{"t0_ms":1730160000000,"t1_ms":1730160300000,"track":"mic","gap_ms":120000}'
```

```json
[
  {
    "gap_ms_used": 120000,
    "segment_count": 5,
    "segment_ids": [
      "aaaaaaaa-bbbb-cccc-dddd-000000000001",
      "aaaaaaaa-bbbb-cccc-dddd-000000000002"
    ],
    "speech_chars": 86,
    "t0_iso": "2024-10-29T08:00:00.000+08:00",
    "t0_ms": 1730160000000,
    "t1_iso": "2024-10-29T08:04:08.000+08:00",
    "t1_ms": 1730160248000,
    "track": "mic",
    "tz_at_capture": "Asia/Shanghai"
  }
]
```

默认 `track=mic`，`gap_ms=120000`（2 分钟；大于落库 merge gap，块≈话题轮次）。

## 诊断

```bash
./Scripts/contextday-cli.sh self_check
```

期望含：`ok`、`service`、`permissions`、`runtime`、`database`、`models`、`agent_io`、`notes`。

## Debug：`inject_pcm`（v0.3.30+，仅 localhost）

无人麦 / 无扬声器驱动 VAD→YAMNet→SenseVoice→SQLite。**App Sandbox 下仓库 `path` 通常失败** → 用 `pcm_base64` 或拷到记录根 `scratch/`。

```bash
./Scripts/pcm-inject-example.sh mic   # 默认 base64 + speech_zh_16k_mono.pcm
# 等待后：
./Scripts/contextday-cli.sh get_recent '{"limit":5,"track":"mic"}'
```

Fixture：`docs/fixtures/speech_zh_16k_mono.pcm`（中文 TTS；再生 `./Scripts/generate-pcm-inject-fixture.sh`）。**勿**用旧 buzz 音（YAMNet→`music`）。

响应示意（**无**转写正文；再 poll `get_recent` 应有非空 `text`）：

```json
{
  "ok": true,
  "track": "mic",
  "accepted_bytes": 169768,
  "duration_ms": 5305,
  "source_sample_rate": 16000,
  "pipeline_running": true,
  "inject_session": true,
  "poll_hint": "Wait ~3–8s for VAD→gate→ASR, then POST /v1/tools/get_recent …"
}
```

`auto_arm` 默认 true：管线未跑时启动 debug inject session（加载模型 + 处理循环，不开麦 / 不触发 TCC）。

## 错误形（统一）

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

HTTP **501**。`export_audio` 同理。未知路径 **404** → `{ "error":"not_found", "message":"no such route" }`。

## 助手提示词用法（推荐）

1. 粘贴一行「请阅读 …/README.md」或先 `get_clipboard_prompt`。  
2. `list_activity` 看 mic `speech_count` 高峰 → `list_speech_blocks` → 每块 `get_window` / `search_segments`。  
3. `get_agent_skill` → `meeting-minutes.md`，按技能结构写纪要。  
4. **不要**调用 `summarize_window`。  
5. 直接用 `t0_iso` 写墙钟；权威比较仍用 `t0_ms`。  
6. 需要回听时看 `audio_path`（相对记录根）；无文件则为 `null`。

## 与 Spec 的对齐

| 项 | 状态 |
|----|------|
| MVP 四 Segment 工具 + 技能 + `self_check` | 01 已实现 |
| `list_speech_blocks` + 分轨 `list_activity` + ISO | **02 v0.1.0** |
| `summarize_window` / `export_audio` | 仍 **unavailable** |
| 统一错误 JSON + 50/500 上限文档 | 02 §2.8–2.9 |
| SQLite Segment schema | **未破改**（派生字段仅 DTO） |
| 无头机完整 PCM→ASR→落库 | 父机 Mac：`inject_pcm` + fixture；云端单测用 SQLite fixture 插入代替 |
