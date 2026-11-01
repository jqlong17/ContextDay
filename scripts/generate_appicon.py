#!/usr/bin/env python3
"""Export macOS AppIcon.appiconset sizes from the opaque App Icon master.

Master: Resources/AppIcon/icon-1024.png (product mark; may differ from DesktopOrb idle).
Desktop floating control keeps Resources/DesktopOrb/idle.png (transparent) separately.

Usage:
  python3 scripts/generate_appicon.py
  # Optional legacy rebuild from idle (charcoal square + centered orb):
  python3 scripts/generate_appicon.py --from-idle
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IDLE = ROOT / "Resources" / "DesktopOrb" / "idle.png"
ICON_SRC = ROOT / "Resources" / "AppIcon" / "icon-1024.png"
OUT = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

CHARCOAL = (28, 28, 30, 255)  # legacy --from-idle square base
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


def make_opaque_icon_from_idle(idle: Image.Image) -> Image.Image:
    """Legacy: charcoal square + centered transparent idle orb → opaque RGB."""
    base = Image.new("RGBA", (CANVAS, CANVAS), CHARCOAL)
    orb_size = int(CANVAS * ORB_FRACTION)
    orb = idle.convert("RGBA").resize((orb_size, orb_size), Image.Resampling.LANCZOS)
    offset = ((CANVAS - orb_size) // 2, (CANVAS - orb_size) // 2)
    base.alpha_composite(orb, dest=offset)
    flat = Image.new("RGBA", (CANVAS, CANVAS), CHARCOAL)
    flat.alpha_composite(base)
    return flat.convert("RGB").convert("RGBA")


def ensure_opaque(master: Image.Image) -> Image.Image:
    """Flatten any residual alpha onto near-black so catalog PNGs stay opaque."""
    rgba = master.convert("RGBA")
    if rgba.size != (CANVAS, CANVAS):
        rgba = rgba.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
    # Near-black matches the Grok-twin negative space (#0A0A0A).
    flat = Image.new("RGBA", (CANVAS, CANVAS), (10, 10, 10, 255))
    flat.alpha_composite(rgba)
    return flat.convert("RGB").convert("RGBA")


def write_catalog(opaque: Image.Image) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, px in SIZES:
        path = OUT / name
        opaque.resize((px, px), Image.Resampling.LANCZOS).save(path, "PNG")
        got = Image.open(path)
        print(f"{name}: {got.size} corner={got.getpixel((0, 0))}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-idle",
        action="store_true",
        help="Rebuild icon-1024.png from DesktopOrb/idle.png (legacy charcoal composite)",
    )
    args = parser.parse_args(argv)

    if args.from_idle:
        idle = Image.open(IDLE)
        opaque = make_opaque_icon_from_idle(idle)
        ICON_SRC.parent.mkdir(parents=True, exist_ok=True)
        opaque.save(ICON_SRC, "PNG")
        print(f"wrote {ICON_SRC} corner={opaque.getpixel((0, 0))} (from idle)")
    else:
        if not ICON_SRC.is_file():
            print(f"missing master {ICON_SRC}; pass --from-idle to rebuild from idle", file=sys.stderr)
            sys.exit(1)
        opaque = ensure_opaque(Image.open(ICON_SRC))
        # Keep master on disk as the approved opaque source (rewrite if alpha was flattened).
        opaque.save(ICON_SRC, "PNG")
        print(f"using master {ICON_SRC} corner={opaque.getpixel((0, 0))}")

    write_catalog(opaque)


if __name__ == "__main__":
    main()
