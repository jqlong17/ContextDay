# ContextDay ↔ Grok 中心对称测量

## 怎么量的
1. 读 `/workspace/grokbot-appicon-mac.png`（与 `cd-ref-grok.png` 同图）。
2. 球体：亮度>90 的像素质心约 **(0.467, 0.588)**，朝左下最远点 **(0.129, 0.824)** → 白球从**左下**进入。
3. 胶囊眼：与高光邻接的暗斑两枚，中心约 **(0.497, 0.317)** 与 **(0.698, 0.443)**，对角抬升 → 看向**右上**。
4. 中心对称：`(x,y) → (1-x, 1-y)` = `rotate(180)`，**不是**左右镜像。
5. 映射后眼心：[(0.297268161525974, 0.5525821834415584, 308), (0.4593684895833333, 0.6676822916666667, 600)] → 看向**左下**；球体进入**右上**（贴顶+右边）。
6. 仅球体亮度 remap 暗绿；负空间强制 `#0A0A0A`；双 pill 眼近黑；无嘴无字。

## 交付
- Solo 1024: `design/appicon-gemini-vision-2026-11-01/contextday-appicon-1024.png`（拷入 `Resources/AppIcon/icon-1024.png`）
- 并排: `design/appicon-gemini-vision-2026-11-01/contextday-grok-pair.png`
- 几何：本文件；App Icon ≠ DesktopOrb idle（Spec v0.3.32）
