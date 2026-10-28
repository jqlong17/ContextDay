# ContextDay — 产品与技术 Spec

| 字段 | 值 |
|------|-----|
| 产品名 | ContextDay |
| Spec 文件 | `docs/01_spec.md` |
| Spec 版本 | **v0.1.0** |
| 状态 | 起草中 / 未开工实现 |
| 创建时间 | 2026-10-28 23:13 Asia/Shanghai |
| 最后更新 | 2026-10-28 23:13 Asia/Shanghai |
| 目标平台 | macOS（计划独立上架 Mac App Store） |
| 主工程路径（Mac） | `/Users/ruska/projects/ContextDay` |
| 云端工作区镜像（可选） | `/workspace/notta/ContextDay`（经 GitHub 同步） |

---

## 1. 项目背景

### 1.1 要解决什么问题

对话助手（Grok Bot 及同类产品）缺的是**本机、连续、带时间戳的生活上下文**。用户一天里说话、开会、听播客的内容，若不在本地沉淀，助手只能依赖当前对话窗口，无法回答「今早我说了什么」「下午会议里谁定了什么」。

ContextDay 定位为：**本机 24h 语音上下文采集与转写层**，把可检索的时间线（文本 + 可选音频）交给上层助手 / MCP / CLI，而不是做成又一个云端录音日记。

### 1.2 产品边界

| 做 | 不做（MVP） |
|----|-------------|
| 激活后持续采集（麦 + 可选系统声） | 通话录音 / 隐蔽录音叙事 |
| 本机分类门控 + SenseVoice Core ML int8 转写 | 云端 ASR 主路径 |
| 时间线日志、邻近段合并、本地查询 | 重度社交 / 习惯打卡（避免与 DayTrace 等品类混淆） |
| 配置：门控、留音频策略与体积预估 | 与输入法壳强绑定（独立 App） |
| 向 Grok Bot 类产品暴露只读数据接口（后续 MCP/API） | 替助手做推理与总结（可由上层做） |

### 1.3 命名与竞品注意

- 已弃用：DayTrace、VoiceTrace、单名 Context（商店与品类冲突）。
- 选定：**ContextDay**（副标可写「本机全天语音上下文 / For agents」）。
- 上架前仍需自行核对商标与域名注册。

### 1.4 已有实测依据（选型）

本机 Apple Silicon Mac（2026-10-28）对比结论写入飞书：[本机 ASR 选型对比（MacBook 友好视角）](https://my.feishu.cn/docx/T6Sdd8q1ZoHLn6xV5JOcPWxhnyh)。

- **生活日志长期后台**：SenseVoice **Core ML int8**（本进程约 20–36 MB；~11.7s 试音识别约 2.6s）。
- **短时听写**（非本产品主路径）：SenseVoice ONNX 更快但内存高峰约 800–900+ MB。
- **音频门控**：YAMNet-ONNX，约 5s 窗；麦 / 系统**双轨独立标签**；Music 与 Speech 同高时 **Music 优先**。
- **采集策略**：环缓冲连续采 PCM；分类只打标，不挡采集。

---

## 2. 产品设计

### 2.1 核心体验

1. 用户打开并**激活** ContextDay → 立即开始 24h 采集与（按策略）转写。
2. 默认开启**分类过滤**：约每 5s 对环缓冲已有音频打标；仅判定为 **Speech** 的片段送入 SenseVoice Core ML int8。
3. 时间线展示：**起止时间 + 文本**；落库时对邻近碎片自动合并，避免过于零散。
4. 配置页可关过滤、可选择是否保留音频及质量；未开过滤时**只能保留全部音频**（不可选「仅人声」）。

### 2.2 配置项（MVP）

| 配置 | 默认 | 说明 |
|------|------|------|
| 分类过滤（YAMNet） | **开** | 关则所有达 VAD 门槛的段都送 ASR；留音频不可选「仅人声」 |
| 保留音频 | **关**（或短滚动窗口，见备忘） | 开则选质量档，并展示**预估 1 天占用** |
| 音频范围 | 仅人声 / 全部 | 仅人声依赖分类过滤开启 |
| 质量档（示例） | Opus 24 / 64 kbps；PCM 参考 | 配置页给出粗算 GB/天（见 §2.4） |
| VAD | 静音结束约 1.5–2s；最短送识 **3s**；最长 **30s** | 与「展示合并 gap」分开配置 |

### 2.3 分段与合并

- **门控层（~5s）**：决定「是否值得送 ASR / 是否按人声策略留音频」，**不**用 5s 硬切 ASR 句。
- **VAD 层**：决定送 ASR 的断点；最短 3s、最长 30s。
- **落库合并**：同轨（mic / system）、相邻 gap ≤ **2s**（可配 1–3s）合并为一条；保留合并后起止时间与原文拼接规则。

### 2.4 磁盘粗算（写进配置文案）

按 16 kHz mono 粗算（全天 24h，未计门控命中率折扣）：

| 档位 | 约占用 / 天 |
|------|-------------|
| PCM 16-bit | ~2.6 GB |
| Opus 64 kbps | ~0.7 GB |
| Opus 24 kbps | ~0.26 GB |

「仅人声」再按门控命中率打折；上线后用真实占比校准区间。

### 2.5 给 Grok Bot 类产品的价值

- 本地可查询的「今天到现在」语音时间线。
- 稳定 schema（时间、轨、文本、可选音频路径、分类标签）。
- 后续：本机 MCP / HTTP / CLI，只读为主，供对话助手拉取上下文。

### 2.6 隐私与系统边界（产品文案必写）

- 本地存储路径、是否上传（MVP 默认不上云）、删除与滚动保留策略。
- 权限：麦克风；系统声需 ScreenCaptureKit 等授权。
- 锁屏 / 睡眠下采集能力边界需在验收中写明「支持到哪一档」。

---

## 3. 技术架构设计

### 3.1 模块划分

| 模块 | 职责 |
|------|------|
| `Capture` | 双轨采集（AVAudioEngine 麦 + ScreenCaptureKit 系统声）→ 环缓冲 |
| `Gate` | YAMNet-ONNX，~5s 窗，双轨独立标签，Music>Speech 偏置 |
| `VAD` | 断句；min 3s / max 30s；静音门槛与合并 gap 分离 |
| `ASR` | SenseVoice Core ML int8（主力）；失败时明确降级策略（不默认偷开 ONNX） |
| `Store` | 时间线条目、合并、可选 Opus/PCM；查询 API |
| `Config` | 门控 / 留音 / 质量 / 预估占用 UI |
| `Export / Agent IO` | 后续 MCP/CLI/HTTP 只读接口（可二期） |
| `App Shell` | 激活态、菜单栏/窗口、权限引导、Mac App Store 打包 |

### 3.2 运行时原则

- **采集永不因分类延迟而停**；分类只标签已缓冲 PCM。
- **门控与 ASR 解耦**：Gate 决定 keep/transcribe；VAD 决定送模型切段。
- **本进程内存优先**：长期只留 Core ML；不把听写用 ONNX 绑进常驻路径。
- **轨语义**：过滤默认作用于「是否转写」；「全部保留音频」时非 Speech 仍可只存不转。

### 3.3 数据模型（草案）

```text
Segment {
  id, track: mic|system,
  t0, t1,                 // 墙钟
  text?,                  // 合并后文本
  gate_label?,            // speech|music|other…
  audio_path?,            // 可选
  source_segment_ids[]    // 合并前碎片
}
```

### 3.4 失败与降级

| 故障 | 行为 |
|------|------|
| Core ML 加载失败 | 提示；停转写或用户显式选降级（不静默上 ONNX） |
| YAMNet 失败 | 按配置：等同关闭过滤，或安全停写并提示 |
| 权限被拒 | 激活失败；引导系统设置 |
| 磁盘将满 | 停留音 / 滚动删除；转写可降级为只写文本 |

---

## 4. 技术架构拓扑图

```mermaid
flowchart TB
  subgraph UI["App Shell / Config"]
    Activate[激活 / 停止]
    Settings[配置页: 门控·留音·质量·预估]
    Timeline[时间线视图]
  end

  subgraph Capture["Capture"]
    Mic[麦克风 AVAudioEngine]
    Sys[系统声 ScreenCaptureKit]
    Ring[RAM 环缓冲 PCM]
  end

  subgraph Gate["Gate ~5s"]
    Yam[YAMNet-ONNX]
    Label[双轨标签 Speech/Music/…]
  end

  subgraph Seg["Segmentation"]
    VAD[VAD 3s–30s]
    Merge[落库合并 gap≤2s]
  end

  subgraph ASR["ASR"]
    CM[SenseVoice Core ML int8]
  end

  subgraph Store["Store"]
    DB[(时间线 DB)]
    Audio[(可选音频文件)]
  end

  subgraph Out["Agent IO 二期"]
    MCP[MCP / CLI / 本地 API]
    Bot[Grok Bot 类助手]
  end

  Activate --> Mic
  Activate --> Sys
  Mic --> Ring
  Sys --> Ring
  Ring --> Yam
  Yam --> Label
  Label -->|Speech 且门控开| VAD
  Label -->|门控关| VAD
  VAD --> CM
  CM --> Merge
  Merge --> DB
  Label -->|留音策略| Audio
  Settings --> Label
  Settings --> Audio
  DB --> Timeline
  DB --> MCP
  MCP --> Bot
```

---

## 5. 开发任务执行计划

### Phase 0 — Spec 与工程骨架（当前）

- [x] 产品命名 ContextDay；弃用冲突名
- [x] 本目录与 `docs/01_spec.md`
- [ ] Xcode / SPM 工程骨架、bundle id、权限 plist 草案
- [ ] 数据目录与 schema 定稿

### Phase 1 — 采集 + 门控 MVP

- [ ] 双轨采集 + 环缓冲
- [ ] YAMNet 5s 双轨标签 + Music 优先
- [ ] 激活/停止与权限引导
- [ ] 菜单栏或主窗口「正在记录」态

### Phase 2 — ASR + 时间线

- [ ] SenseVoice Core ML int8 接入
- [ ] VAD 3–30s + 落库合并
- [ ] 时间线 UI（时间点 + 文本）
- [ ] 配置：门控开关、留音、质量、预估占用、仅人声约束

### Phase 3 — 稳固与商店向

- [ ] 锁屏/睡眠行为说明与测试
- [ ] 磁盘滚动与爆盘保护
- [ ] 隐私文案、本地路径、删除策略
- [ ] Notarize / App Store 素材与审核说明（持续录音敏感）

### Phase 4 — Agent 供数

- [ ] 只读 MCP 或本地 HTTP/CLI
- [ ] 与 Grok Bot 类产品对接样例
- [ ] 查询：按时间范围 / 关键词 / 轨

---

## 6. 测试用例（草案）

| ID | 场景 | 步骤要点 | 期望 |
|----|------|----------|------|
| T01 | 激活即采 | 授权后点激活 | 环缓冲有 PCM；UI 显示记录中 |
| T02 | 门控开 + 说话 | 对麦说话 ≥3s | 出现 Speech 标签；产生转写条目 |
| T03 | 门控开 + 纯音乐（系统轨） | 本机放歌 | Music 优先；默认不送 ASR |
| T04 | 门控关 | 关过滤后说话/放歌 | 达 VAD 的段均可送 ASR；留音不可选仅人声 |
| T05 | VAD 最短 | 极短爆破音 | 不足 3s 不落转写 |
| T06 | VAD 最长 | 连续说 >30s | 约 30s 切段 |
| T07 | 合并 | 两句间隔 ≤2s | 时间线一条；起止覆盖两端 |
| T08 | 碎段 | 间隔 >2s | 两条独立 |
| T09 | 留音预估 | 切换质量档 | 显示与 §2.4 同量级的 GB/天 |
| T10 | 仅人声留音 | 门控开 + 仅人声 | 非 Speech 不写音频文件 |
| T11 | 门控关 + 仅人声 | 试图勾选仅人声 | UI 禁用或强制「全部」 |
| T12 | Core ML 失败 | 移走模型 | 明确错误；不静默切 ONNX |
| T13 | 权限拒绝 | 拒麦 | 无法激活；可跳转设置 |
| T14 | 双轨同时 | 麦说话 + 系统放歌 | 两轨标签独立；策略各自生效 |
| T15 | 内存 | 记录 1h | 本进程内存保持 Core ML 档（量级几十 MB，允许波动） |

---

## 7. 验收标准（MVP）

1. 激活后可持续采集 ≥ 8h 不崩溃（开发机冒烟）；正式目标 24h。
2. 默认门控下：明显音乐段不产生转写；清晰人声段有文本与时间戳。
3. 时间线无「一秒一条」式碎到不可读；合并规则符合 gap≤2s。
4. 配置页三项齐全：门控、留音与质量+日占用预估、仅人声/全部（约束正确）。
5. 主力 ASR 为 SenseVoice Core ML int8；文档与关于页写明本机推理。
6. 隐私：默认不上云；路径与删除方式可查。
7. 命名与商店素材使用 ContextDay，不与输入法产品混品牌。

---

## 8. 备忘录

- 门控 5s 与 VAD 切段是两级，不要合成一个旋钮。
- 默认不留音频或短滚动，避免 24h PCM 爆盘。
- 审核叙事：用户显式激活的本机上下文工具，服务个人助手；非隐蔽监控。
- 与既有 YamnetGate / AsrCompare 实验代码可参考，但 ContextDay 工程独立，避免绑听写 ONNX 生命周期。
- 中文连续数字 Core ML 仍可能弱于 ONNX；生活日志可接受，需在已知问题中披露。
- Agent IO（MCP）可晚于 MVP 商店版本，但 schema 尽早稳定。
- 飞书 ASR 对比文已入个人总索引「个人 · 其他」。

---

## 9. Spec 版本信息与时间点

| 版本 | 时间（Asia/Shanghai） | 说明 |
|------|----------------------|------|
| v0.1.0 | 2026-10-28 23:13 | 初稿：背景、产品、架构、拓扑、计划、用例、验收、备忘 |

变更规则：改需求或架构时升次版本号（v0.x）；破坏性改 schema 在备忘与验收中标明，并更新「最后更新」。

---

## 10. 执行状态

| 项 | 状态 | 备注 |
|----|------|------|
| 命名 ContextDay | 已定 | 2026-10-28 |
| Spec v0.1.0 | **已完成** | 本文件 |
| 工程骨架 | 未开始 | |
| 采集 / 门控 | 未开始 | 可复用 YamnetGate 经验 |
| Core ML ASR | 未开始 | 可复用 AsrCompare 模型路径经验 |
| 时间线 / 配置 UI | 未开始 | |
| Agent IO | 未开始 | Phase 4 |
| Mac App Store | 未开始 | |

**当前总状态：`spec_drafted`（仅文档，无实现交付）**

---

## 11. 参考链接

- ASR 选型（含实测）：https://my.feishu.cn/docx/T6Sdd8q1ZoHLn6xV5JOcPWxhnyh
- 个人总索引：https://my.feishu.cn/wiki/Dk5hwo3NriVP5ukV5hicLgHDnHf
