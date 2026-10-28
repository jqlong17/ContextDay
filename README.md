# ContextDay

本机 24h 语音上下文（Mac App Store 向），供 Grok Bot 类助手使用。

产品与技术细节以 [docs/01_spec.md](docs/01_spec.md) 为准（SSOT）。

## Phase 0 工程骨架

本仓库已包含可在 Mac 上用 Xcode 打开的 **macOS App** 目标：

| 项 | 值 |
|----|-----|
| Bundle ID | `app.contextday` |
| 部署 | macOS 14+ |
| 工程 | `ContextDay.xcodeproj` |
| 源码树 | Spec §3.1：`App/`、`Features/*`、`Resources/` |

### 在 Mac 上用 Xcode 打开

1. Clone 本仓库到本机（Spec 记录的主路径示例：`/Users/ruska/projects/ContextDay`）。
2. 双击或执行：`open ContextDay.xcodeproj`
3. 选中 target **ContextDay** → Signing & Capabilities 里选你的 Team（Automatic signing）。
4. Run（⌘R）。期望：桌面底部附近出现透明背景的双眼球浮控（可被其它 App 窗口遮盖）。
5. 左键：切换 `isRecording` 占位布尔，并播放一次 `eye-click-2s.mp4` 眼神微动。
6. 右键：**开始录音** / **暂停录音**（与左键同一激活/停止路径）、**打开记录文件夹**（默认 `~/Downloads/ContextDay/`）、**复制提示词**（Spec §2.8 + 当前根路径）、**修改保存文件夹…**（`recordsRootPath`）。

> 当前云端 / Linux CI **无法**真正编译或运行该 AppKit 工程；请在 Apple Silicon Mac + Xcode 上验证。

可选：`Package.swift` 为伴生 SwiftPM 清单，便于浏览源码；完整 `.app`、App Icon、entitlements 以 **Xcode 工程**为准。

### 资源说明

| 资源 | 用途 |
|------|------|
| `Resources/DesktopOrb/idle.png` | **透明** 1024 双眼球 — 仅桌面浮控 |
| `Resources/DesktopOrb/eye-click-2s.mp4` | 左键眼神微动 ~2s |
| `Resources/AppIcon/icon-1024.png` | **不透明** 深炭灰方底 + 居中 orb — App Icon 源图 |
| `Resources/Assets.xcassets/AppIcon.appiconset` | 由源图导出的各尺寸 |
| `Resources/Assets.xcassets/DesktopOrbIdle.imageset` | 浮控 idle（透明）Asset |

重新生成不透明 App Icon（若替换了透明 idle 或要改炭灰底）：

```bash
python3 scripts/generate_appicon.py
```

若你另有定稿的不透明 `AppIcon-1024.png`，可覆盖 `Resources/AppIcon/icon-1024.png` 后重跑脚本（或直接替换 `AppIcon.appiconset`）。**不要**把透明 `DesktopOrb/idle.png` 直接当作 App Icon。

### Phase 0 已实现 / 未实现

**已有**

- Xcode macOS app target + Bundle ID / Info.plist 隐私文案草案（麦克风、屏幕录制等）
- DesktopControl：底层窗口 level、orb idle、左键播片占位、右键菜单
- Store：Application Support 目录创建 + SQLite `segment` 表 stub
- Capture / Gate / VAD / ASR / Config：**stubs + TODO 注释 only**（无真实 YAMNet / SenseVoice）

**未做（按 Spec 后续 Phase）**

- 真实采集、门控、ASR、时间线 UI、配置页、MCP

### 与其它 PR 的关系

仓库可能仍有 docs-only 的 Spec 更新 PR。本 Phase 0 骨架 **不改写 Spec**；实现路径对齐 Spec §3.1 / §2.7 / §2.8 / §3.3–3.4。若本地 Spec 仍偏旧，以合并后的 `docs/01_spec.md` 为准。
