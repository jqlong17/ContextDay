# Mac App Store / 公证 — 审核说明草稿（Phase 3）

> 正式公证与上架在提交前执行；本文供审核叙事与隐私文案对齐 Spec §2.6 / §7。

## 产品叙事

ContextDay 是用户**显式激活**的本机 24h 语音上下文工具，服务个人助手（如 Grok Bot）拉取本地时间线。不是隐蔽监控、不是通话录音产品。

## 权限

| 权限 | 用途 |
|------|------|
| 麦克风 | 麦轨采集 → 门控 / ASR |
| 屏幕录制（ScreenCaptureKit） | 可选系统声音轨 |
| 文件（Downloads / 用户自选） | 记录根 `db/` + `audio/` |
| 本机网络 server | 仅 `127.0.0.1:8787` Agent IO |

Usage 字符串见 `Info.plist`；关于页见 App 内「关于与隐私…」。

## 隐私要点（审核可核对）

- 默认本地-only；转写在 SQLite；无每日 txt；不上云。
- 留音默认关；开则为证据回听（Opus 档）。
- 睡眠时停止采集，唤醒不自动续录。
- Agent IO（剪贴板 / HTTP / MCP）只读。

## 公证检查清单（提交时）

1. Archive → Notarize（Developer ID）或 App Store Connect 上传。
2. Hardened Runtime 已开；沙盒 entitlement 与实际 API 一致。
3. 隐私政策 URL（商店页）复述本页要点 + 记录根路径说明。
4. 截图：桌面 orb、设置、时间线、关于与隐私（含本地路径）。

## 已知限制（披露）

- Music>Speech 偏置：有 BGM 的说话可能不送 ASR。
- keep-audio 当前可能落 CAF 容器（Opus 比特流路径仍在完善）；目录仍在 Spec `audio/` 树下。
- 锁屏下系统声可能中断；24h 目标需保持唤醒策略。
