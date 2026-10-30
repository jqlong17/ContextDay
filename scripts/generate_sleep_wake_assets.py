#!/usr/bin/env python3
"""Land Concept A sleep loop + S1 wake clip into DesktopOrb (Spec §2.7.5).

Sleep: chroma-key design/sleep-concepts/A-zzz.jpg (and/or preview-sleep-A frames)
       → Resources/DesktopOrb/sleep/fNN.png (首尾针, ~10fps).

Wake:  A → S1 (soft shy blush) → idle.png crossfade
       → Resources/DesktopOrb/wake-shy-S1.mov (ProRes 4444 alpha) + .mp4 green preview.

Also refreshes design/icon-orb-sleep-preview.mp4 and design/preview-wake-shy-S1.mp4.
"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONCEPT_A = ROOT / "design" / "sleep-concepts" / "A-zzz.jpg"
CONCEPT_S1 = ROOT / "design" / "wake-concepts" / "S1-soft-blush.jpg"
IDLE = ROOT / "Resources" / "DesktopOrb" / "idle.png"
SLEEP_DIR = ROOT / "Resources" / "DesktopOrb" / "sleep"
WAKE_FRAMES = ROOT / "design" / "wake_shy_s1_frames"
SLEEP_PREVIEW_DIR = ROOT / "design" / "sleep_preview_frames"
PREVIEW_SLEEP_SRC = ROOT / "design" / "preview-sleep-A.mp4"
SLEEP_PREVIEW_MP4 = ROOT / "design" / "icon-orb-sleep-preview.mp4"
WAKE_MOV = ROOT / "Resources" / "DesktopOrb" / "wake-shy-S1.mov"
WAKE_MP4_GREEN = ROOT / "Resources" / "DesktopOrb" / "wake-shy-S1.mp4"
WAKE_PREVIEW_MP4 = ROOT / "design" / "preview-wake-shy-S1.mp4"

SIZE = 512
SLEEP_N = 12
SLEEP_FPS = 10
WAKE_N = 36
WAKE_FPS = 18


def chroma_key_rgba(img: Image.Image) -> Image.Image:
    """Edge-flood green plate → alpha 0; keep cream Zzz / blush / orb."""
    rgb = np.array(img.convert("RGB"), dtype=np.float32)
    h, w, _ = rgb.shape
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    # Strong green plate
    plate = (g > r + 22) & (g > b + 22) & (g > 70)
    # Soft near-green fringe
    fringe = (g > r + 8) & (g > b + 8) & (g > 50) & ~plate

    alpha = np.full((h, w), 255, dtype=np.uint8)
    alpha[plate] = 0
    alpha[fringe] = np.clip((alpha[fringe].astype(np.float32) * 0.15), 0, 255).astype(np.uint8)

    # Edge flood: only clear green connected to border (protect green-ish highlights on orb)
    from collections import deque

    visited = np.zeros((h, w), dtype=bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if plate[y, x] or fringe[y, x]:
                q.append((x, y))
                visited[y, x] = True
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y, x] and (plate[y, x] or fringe[y, x]):
                q.append((x, y))
                visited[y, x] = True
    while q:
        x, y = q.popleft()
        alpha[y, x] = 0
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny, nx]:
                if plate[ny, nx] or fringe[ny, nx]:
                    visited[ny, nx] = True
                    q.append((nx, ny))

    out = np.dstack([rgb.astype(np.uint8), alpha])
    out[alpha == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


def fit_to_canvas(src: Image.Image, size: int = SIZE) -> Image.Image:
    """Scale keyed art so orb roughly matches idle framing on transparent canvas."""
    idle = Image.open(IDLE).convert("RGBA")
    idle_bbox = idle.getbbox() or (0, 0, idle.width, idle.height)
    idle_cx = (idle_bbox[0] + idle_bbox[2]) / 2 / idle.width
    idle_cy = (idle_bbox[1] + idle_bbox[3]) / 2 / idle.height
    idle_span = max(idle_bbox[2] - idle_bbox[0], idle_bbox[3] - idle_bbox[1]) / idle.width

    keyed = src if src.mode == "RGBA" else chroma_key_rgba(src)
    bb = keyed.getbbox()
    if not bb:
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        return canvas
    crop = keyed.crop(bb)
    target = int(size * idle_span * 1.02)
    crop = crop.resize((target, target), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = int(size * idle_cx - crop.width / 2)
    y = int(size * idle_cy - crop.height / 2)
    canvas.alpha_composite(crop, dest=(x, y))
    return canvas


def lerp_rgba(a: Image.Image, b: Image.Image, t: float) -> Image.Image:
    t = max(0.0, min(1.0, t))
    if t <= 0:
        return a.copy()
    if t >= 1:
        return b.copy()
    aa = np.array(a, dtype=np.float32)
    bb = np.array(b, dtype=np.float32)
    # Premultiplied-ish blend for cleaner alpha
    out = aa * (1 - t) + bb * t
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def ease_in_out(t: float) -> float:
    return 0.5 - 0.5 * math.cos(math.pi * t)


def generate_sleep_from_preview() -> list[Image.Image]:
    """Prefer animated preview-sleep-A (Concept A + floating Zzz); subsample to SLEEP_N."""
    if not PREVIEW_SLEEP_SRC.exists():
        return []
    tmp = ROOT / "design" / "_tmp_sleep_extract"
    tmp.mkdir(parents=True, exist_ok=True)
    for p in tmp.glob("*.png"):
        p.unlink()
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(PREVIEW_SLEEP_SRC),
            "-vf",
            "fps=10",
            str(tmp / "f%03d.png"),
        ],
        check=True,
        capture_output=True,
    )
    paths = sorted(tmp.glob("f*.png"))
    if len(paths) < 4:
        return []
    # Drop last frame if near-duplicate of first for loop; take evenly spaced
    idxs = [int(round(i * (len(paths) - 1) / SLEEP_N)) % len(paths) for i in range(SLEEP_N)]
    frames: list[Image.Image] = []
    for i in idxs:
        frames.append(fit_to_canvas(chroma_key_rgba(Image.open(paths[i]))))
    # Force 首尾针: last = first
    frames[-1] = frames[0].copy()
    return frames


def generate_sleep_from_still() -> list[Image.Image]:
    base = fit_to_canvas(chroma_key_rgba(Image.open(CONCEPT_A)))
    frames: list[Image.Image] = []
    for i in range(SLEEP_N):
        t = i / SLEEP_N
        dy = int(round(math.sin(t * 2 * math.pi) * 5))
        dx = int(round(math.cos(t * 2 * math.pi) * 1.5))
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.alpha_composite(base, dest=(dx, dy + 2))
        # subtle dim breathe
        dim = 0.92 + 0.06 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + math.pi))
        if dim < 0.999:
            arr = np.array(canvas, dtype=np.float32)
            arr[:, :, :3] *= dim
            canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        frames.append(canvas)
    frames[-1] = frames[0].copy()
    return frames


def write_sleep_frames(frames: list[Image.Image]) -> None:
    SLEEP_DIR.mkdir(parents=True, exist_ok=True)
    SLEEP_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for i, fr in enumerate(frames):
        fr.save(SLEEP_DIR / f"f{i:02d}.png", "PNG")
        preview = Image.new("RGBA", (SIZE, SIZE), (28, 28, 30, 255))
        preview.alpha_composite(fr)
        preview.convert("RGB").save(SLEEP_PREVIEW_DIR / f"f{i:02d}.png", "PNG")
        print(f"sleep f{i:02d} bbox={fr.getbbox()}")


def generate_wake_frames() -> list[Image.Image]:
    a = fit_to_canvas(chroma_key_rgba(Image.open(CONCEPT_A)))
    s1 = fit_to_canvas(chroma_key_rgba(Image.open(CONCEPT_S1)))
    idle = Image.open(IDLE).convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    frames: list[Image.Image] = []
    for i in range(WAKE_N):
        u = i / max(1, WAKE_N - 1)
        if u < 0.38:
            t = ease_in_out(u / 0.38)
            fr = lerp_rgba(a, s1, t)
        elif u < 0.52:
            fr = s1.copy()
        else:
            t = ease_in_out((u - 0.52) / 0.48)
            fr = lerp_rgba(s1, idle, t)
        frames.append(fr)
    # 首尾针-ish: start = sleep A, end = idle
    frames[0] = a.copy()
    frames[-1] = idle.copy()
    return frames


def write_wake_assets(frames: list[Image.Image]) -> None:
    WAKE_FRAMES.mkdir(parents=True, exist_ok=True)
    green_dir = ROOT / "design" / "wake_shy_s1_green"
    green_dir.mkdir(parents=True, exist_ok=True)
    for i, fr in enumerate(frames):
        fr.save(WAKE_FRAMES / f"f{i:02d}.png", "PNG")
        green = Image.new("RGBA", (SIZE, SIZE), (40, 205, 40, 255))
        green.alpha_composite(fr)
        green.convert("RGB").save(green_dir / f"f{i:02d}.png", "PNG")
        print(f"wake f{i:02d} bbox={fr.getbbox()}")

    # Alpha ProRes for runtime
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(WAKE_FPS),
            "-i",
            str(WAKE_FRAMES / "f%02d.png"),
            "-c:v",
            "prores_ks",
            "-profile:v",
            "4444",
            "-pix_fmt",
            "yuva444p10le",
            str(WAKE_MOV),
        ],
        check=True,
    )
    print(f"wrote {WAKE_MOV}")

    # Greenscreen H.264 source (not used at runtime)
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(WAKE_FPS),
            "-i",
            str(green_dir / "f%02d.png"),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-crf",
            "18",
            "-movflags",
            "+faststart",
            str(WAKE_MP4_GREEN),
        ],
        check=True,
    )
    print(f"wrote {WAKE_MP4_GREEN}")

    # Design preview (dark bg)
    preview_dir = ROOT / "design" / "wake_shy_s1_preview"
    preview_dir.mkdir(parents=True, exist_ok=True)
    for i, fr in enumerate(frames):
        p = Image.new("RGBA", (SIZE, SIZE), (28, 28, 30, 255))
        p.alpha_composite(fr)
        p.convert("RGB").save(preview_dir / f"f{i:02d}.png", "PNG")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(WAKE_FPS),
            "-i",
            str(preview_dir / "f%02d.png"),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-crf",
            "18",
            "-movflags",
            "+faststart",
            str(WAKE_PREVIEW_MP4),
        ],
        check=True,
    )
    print(f"wrote {WAKE_PREVIEW_MP4}")


def write_sleep_preview_mp4() -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(SLEEP_FPS),
            "-i",
            str(SLEEP_PREVIEW_DIR / "f%02d.png"),
            "-filter_complex",
            f"loop=loop=3:size={SLEEP_N}:start=0,fps={SLEEP_FPS}",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-crf",
            "18",
            "-movflags",
            "+faststart",
            str(SLEEP_PREVIEW_MP4),
        ],
        check=True,
    )
    print(f"wrote {SLEEP_PREVIEW_MP4}")


def write_readme() -> None:
    text = """# Sleep idle frames — Concept A (定稿)

Runtime: `OrbFrameLoopPlayer` loads `fNN.png` from Bundle `DesktopOrb/sleep/`.

## Contract
- Transparent PNG sequence, first≈last for seamless loop (首尾针).
- **Concept A**：闭眼 + 奶油色浮动 Zzz；轻微呼吸 / bob。
- Suggested: 8–16 frames at about 8–12 fps.

## Current files
Generated from `design/sleep-concepts/A-zzz.jpg` + `design/preview-sleep-A.mp4`
via `scripts/generate_sleep_wake_assets.py`. Wake leave-sleep clip:
`DesktopOrb/wake-shy-S1.mov` (A → S1 soft shy blush → idle).
"""
    (SLEEP_DIR / "README.md").write_text(text, encoding="utf-8")


def main() -> None:
    frames = generate_sleep_from_preview()
    if len(frames) < 2:
        print("preview extract failed — falling back to still A + bob")
        frames = generate_sleep_from_still()
    write_sleep_frames(frames)
    write_sleep_preview_mp4()
    write_readme()
    wake = generate_wake_frames()
    write_wake_assets(wake)
    print("done")


if __name__ == "__main__":
    main()
