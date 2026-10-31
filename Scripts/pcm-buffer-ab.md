# PCM 缓冲 A/B 测量（Mac）

Spec §3.2.1 / v0.3.29。产品默认 **B**（60s 固定环）；**A**（~10 min soft-cap）仅作对照 / 回滚。

## 切换变体（同包翻转，无需两套 App Store 包）

```bash
# Variant A（对照，~10 min growable soft-cap）
defaults write app.contextday pcm_buffer_variant A

# Variant B（处理组 / 默认，60s fixed ring）
defaults write app.contextday pcm_buffer_variant B

# 或用秒数：>=300 -> A，(0,300) -> B
defaults write app.contextday pcm_buffer_seconds -int 600
defaults write app.contextday pcm_buffer_seconds -int 60

# 恢复默认（删键 -> B）
defaults delete app.contextday pcm_buffer_variant
defaults delete app.contextday pcm_buffer_seconds
```

改完后**完全退出并重启** App（缓冲在 `CapturePipeline` 构造时解析变体）。

编译期强制（可选，Xcode `OTHER_SWIFT_FLAGS`）：

- `-DCONTEXTDAY_PCM_VARIANT_A`
- `-DCONTEXTDAY_PCM_VARIANT_B`

编译期覆盖优先于 UserDefaults。

## 指标怎么采

| Metric | 做法 | Pass（可默认 B） |
|--------|------|------------------|
| Peak PCM buffer bytes（每轨 + sum） | 录音 >=10 min（让 A 顶到 soft-cap）或读日志 `pcm_ab ... peakBytes=`；亦可跑 XCTest `testABHarnessPeakRatioAtSoftCap` | B <= A x 0.15（约 10x 更小） |
| Process `phys_footprint`（录 3 min，闲聊+安静） | 同机同包：`footprint -p $(pgrep -x ContextDay)` 或 Activity Monitor；先 A 后 B | B <= A - 20 MB **或** B <= 150 MB（取更严且可达） |
| 转写质量代理 | 同一段 ~60s 连说 + 短停顿；数非空 text 段；看有无「在说话却 utt=0 长时间」 | B 段数在 A 的 +/-20%；30s 强切不回退 |
| Correctness | `xcodebuild ... test`（`PCMRingBufferTests` 等） | 0 failures |

启动日志应含：`pcm_variant=A|B pcm_cap_sec=600|60`。  
运行中约每 30s：`pcm_ab pcm_buf variant=... filledBytes=... peakBytes=... | system ... sumFilled=... sumPeak=...`。

## 推荐流程（父机）

```bash
./Scripts/mac-verify.sh   # 构建 + XCTest

# --- Run A ---
defaults write app.contextday pcm_buffer_variant A
open ~/Applications/ContextDay.app
# 右键开始录音 >=3 min（footprint）与 >=10 min（buffer peak，可选同机过夜）
# 记录：footprint、Console/logs 中 pcm_ab 行、时间线非空段数
# 完全退出 App

# --- Run B ---
defaults write app.contextday pcm_buffer_variant B
open ~/Applications/ContextDay.app
# 同一脚本说话；同样记 footprint / pcm_ab / 段数
```

Linux CI **不能**采 `phys_footprint`；可用：

```bash
python3 Scripts/pcm-buffer-ab-sim.py
```

核对理论容量：A = 19200000 B/轨（600s * 16k * 2），B = 1920000 B/轨（60s），比值 0.10。

## 决策

- 指标全过 -> 保持默认 **B**；A 留 `pcm_buffer_variant=A` 回滚。
- 任一项失败 -> `defaults write ... pcm_buffer_variant A` 作默认前报告数字，勿翻转产品默认。
