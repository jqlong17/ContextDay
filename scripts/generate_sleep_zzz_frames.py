#!/usr/bin/env python3
"""DEPRECATED — use generate_sleep_wake_assets.py (Concept A + wake S1).

Legacy: idle-derived bob+dim + floating Zzz (首尾针).
"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
IDLE = ROOT / "Resources" / "DesktopOrb" / "idle.png"
OUT_DIR = ROOT / "Resources" / "DesktopOrb" / "sleep"
PREVIEW_DIR = ROOT / "design" / "sleep_preview_frames"
PREVIEW_MP4 = ROOT / "design" / "icon-orb-sleep-preview.mp4"

SIZE = 512
N = 12
FPS = 10


def load_orb() -> Image.Image:
    idle = Image.open(IDLE).convert("RGBA")
    orb_size = int(SIZE * 0.82)
    return idle.resize((orb_size, orb_size), Image.Resampling.LANCZOS)


def paste_orb(canvas: Image.Image, orb: Image.Image, t: float, dim: float) -> None:
    amp = 6.0
    dy = math.sin(t * 2 * math.pi) * amp
    dx = math.cos(t * 2 * math.pi) * 1.5
    base_x = (SIZE - orb.width) // 2
    base_y = (SIZE - orb.height) // 2 + 18
    x = int(base_x + dx)
    y = int(base_y + dy)
    layer = orb.copy()
    if dim < 0.999:
        px = layer.load()
        w, h = layer.size
        for j in range(h):
            for i in range(w):
                r, g, b, a = px[i, j]
                if a == 0:
                    continue
                px[i, j] = (
                    max(0, min(255, int(r * dim))),
                    max(0, min(255, int(g * dim))),
                    max(0, min(255, int(b * dim))),
                    a,
                )
    canvas.alpha_composite(layer, dest=(x, y))


def make_font(px: int) -> ImageFont.ImageFont:
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, px)
    return ImageFont.load_default()


def draw_z(
    draw: ImageDraw.ImageDraw, cx: float, cy: float, alpha: float, font: ImageFont.ImageFont
) -> None:
    if alpha <= 0.02:
        return
    a = max(0, min(255, int(255 * alpha)))
    text = "Z"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = cx - tw / 2
    y = cy - th / 2
    shadow_a = max(0, min(255, int(a * 0.45)))
    draw.text((x + 2, y + 2), text, font=font, fill=(12, 10, 8, shadow_a))
    draw.text((x, y), text, font=font, fill=(250, 242, 225, a))


def z_states(t: float) -> list[tuple[float, float, float, int]]:
    """Three staggered rising Z's; t in [0, 1)."""
    ox, oy = SIZE * 0.60, SIZE * 0.26
    out: list[tuple[float, float, float, int]] = []
    for i, phase in enumerate((0.0, 0.34, 0.68)):
        local = (t - phase) % 1.0
        if local > 0.58:
            continue
        u = local / 0.58
        ease = 1 - (1 - u) ** 2
        cx = ox + ease * 48 + i * 10
        cy = oy - ease * 88 - i * 8
        size = 22 + i * 8 + ease * 14
        if u < 0.12:
            alpha = u / 0.12
        elif u > 0.62:
            alpha = max(0.0, (1 - u) / 0.38)
        else:
            alpha = 1.0
        alpha *= 0.98
        out.append((cx, cy, alpha, int(size)))
    return out


def generate_frames() -> None:
    orb = load_orb()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    font_cache: dict[int, ImageFont.ImageFont] = {}
    for i in range(N):
        t = i / N
        dim = 0.88 + 0.08 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + math.pi))
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        paste_orb(canvas, orb, t, dim)
        zlayer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        zdraw = ImageDraw.Draw(zlayer)
        for cx, cy, alpha, font_px in z_states(t):
            if font_px not in font_cache:
                font_cache[font_px] = make_font(font_px)
            draw_z(zdraw, cx, cy, alpha, font_cache[font_px])
        glow = zlayer.filter(ImageFilter.GaussianBlur(radius=1.4))
        canvas.alpha_composite(glow)
        canvas.alpha_composite(zlayer)
        canvas.save(OUT_DIR / f"f{i:02d}.png", "PNG")
        preview = Image.new("RGBA", (SIZE, SIZE), (28, 28, 30, 255))
        preview.alpha_composite(canvas)
        preview.convert("RGB").save(PREVIEW_DIR / f"f{i:02d}.png", "PNG")
        print(f"wrote f{i:02d}.png bbox={canvas.getbbox()}")


def write_preview_mp4() -> None:
    PREVIEW_MP4.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-framerate",
        str(FPS),
        "-i",
        str(PREVIEW_DIR / "f%02d.png"),
        "-filter_complex",
        f"loop=loop=2:size={N}:start=0,fps={FPS}",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "18",
        "-movflags",
        "+faststart",
        str(PREVIEW_MP4),
    ]
    subprocess.run(cmd, check=True)
    print(f"wrote {PREVIEW_MP4}")


def main() -> None:
    generate_frames()
    write_preview_mp4()


if __name__ == "__main__":
    main()
