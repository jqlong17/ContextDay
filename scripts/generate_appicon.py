#!/usr/bin/env python3
"""Generate opaque macOS AppIcon from transparent DesktopOrb idle art.

App Icon = dark charcoal square + centered twin-eye orb (fully opaque).
Desktop floating control keeps Resources/DesktopOrb/idle.png (transparent).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IDLE = ROOT / "Resources" / "DesktopOrb" / "idle.png"
ICON_SRC = ROOT / "Resources" / "AppIcon" / "icon-1024.png"
OUT = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

CHARCOAL = (28, 28, 30, 255)  # dark charcoal square base
CANVAS = 1024
ORB_FRACTION = 0.78

# (filename, pixel size) — build @2x names without embedding "@" in source literals awkwardly.
SIZES: list[tuple[str, int]] = [
    ("icon_16x16.png", 16),
    ("icon_16x16" + "@" + "2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32" + "@" + "2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128" + "@" + "2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256" + "@" + "2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512" + "@" + "2x.png", 1024),
]


def make_opaque_icon(idle: Image.Image) -> Image.Image:
    base = Image.new("RGBA", (CANVAS, CANVAS), CHARCOAL)
    orb_size = int(CANVAS * ORB_FRACTION)
    orb = idle.convert("RGBA").resize((orb_size, orb_size), Image.Resampling.LANCZOS)
    offset = ((CANVAS - orb_size) // 2, (CANVAS - orb_size) // 2)
    base.alpha_composite(orb, dest=offset)
    # Flatten any residual transparency onto charcoal → fully opaque.
    flat = Image.new("RGBA", (CANVAS, CANVAS), CHARCOAL)
    flat.alpha_composite(base)
    return flat.convert("RGB").convert("RGBA")


def main() -> None:
    idle = Image.open(IDLE)
    opaque = make_opaque_icon(idle)
    ICON_SRC.parent.mkdir(parents=True, exist_ok=True)
    opaque.save(ICON_SRC, "PNG")
    print(f"wrote {ICON_SRC} corner={opaque.getpixel((0, 0))}")

    OUT.mkdir(parents=True, exist_ok=True)
    for name, px in SIZES:
        path = OUT / name
        opaque.resize((px, px), Image.Resampling.LANCZOS).save(path, "PNG")
        got = Image.open(path)
        print(f"{name}: {got.size} corner={got.getpixel((0, 0))}")


if __name__ == "__main__":
    main()
