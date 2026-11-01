# AppIcon source

`icon-1024.png` is the **opaque** macOS App Icon master (product mark).

Current mark (v0.3.32+): dark-green Grok Bot twin — green orb enters top-right, twin pill eyes look down-left, black negative space; no mouth/text. Design refs: `design/appicon-gemini-vision-2026-11-01/`.

- Desktop floating control uses transparent `Resources/DesktopOrb/idle.png` (may differ from App Icon).
- Regenerate catalog sizes from the master: `python3 scripts/generate_appicon.py`
- Legacy rebuild from idle (charcoal + centered orb): `python3 scripts/generate_appicon.py --from-idle`
