#!/usr/bin/env python3
"""Offline check of docs/fixtures/agent-io JSON shapes (runs on Linux cloud VM)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "docs" / "fixtures" / "agent-io"

SEGMENT_KEYS = {
    "segment_id",
    "t0_ms",
    "t1_ms",
    "t0_iso",
    "t1_iso",
    "track",
    "gate_label",
    "text",
    "tz_at_capture",
    "audio_path",
}

ACTIVITY_KEYS = {
    "bucket_start_ms",
    "bucket_end_ms",
    "bucket_start_iso",
    "bucket_end_iso",
    "segment_count",
    "speech_count",
    "music_count",
    "other_count",
    "track",
}

BLOCK_KEYS = {
    "track",
    "t0_ms",
    "t1_ms",
    "t0_iso",
    "t1_iso",
    "segment_count",
    "speech_chars",
    "segment_ids",
    "gap_ms_used",
    "tz_at_capture",
}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def assert_snake(row: dict, label: str) -> None:
    extra_camel = [k for k in row if any(c.isupper() for c in k)]
    if extra_camel:
        fail(f"{label}: camelCase keys not allowed: {extra_camel}")


def main() -> None:
    search = json.loads((FIXTURES / "sample-search-segments.json").read_text())
    if not isinstance(search, list) or not search:
        fail("search fixture must be non-empty array")
    row = search[0]
    missing = SEGMENT_KEYS - set(row)
    if missing:
        fail(f"search row missing keys: {sorted(missing)}")
    assert_snake(row, "search")
    if row["track"] not in ("mic", "system"):
        fail("track must be mic|system")
    if "+08:00" not in row["t0_iso"]:
        fail("t0_iso should include +08:00 for Shanghai fixture")

    activity = json.loads((FIXTURES / "sample-list-activity.json").read_text())
    if not isinstance(activity, list) or len(activity) < 3:
        fail("activity fixture needs mic/system/total rows")
    tracks = [r.get("track") for r in activity]
    if "mic" not in tracks or "system" not in tracks or None not in tracks:
        fail(f"activity must include mic, system, and null total; got {tracks}")
    for r in activity:
        missing = ACTIVITY_KEYS - set(r)
        if missing:
            fail(f"activity row missing keys: {sorted(missing)}")
        assert_snake(r, "activity")

    blocks = json.loads((FIXTURES / "sample-list-speech-blocks.json").read_text())
    if not isinstance(blocks, list) or not blocks:
        fail("speech blocks fixture must be non-empty array")
    block = blocks[0]
    missing = BLOCK_KEYS - set(block)
    if missing:
        fail(f"speech block missing keys: {sorted(missing)}")
    assert_snake(block, "speech_block")
    if not isinstance(block["segment_ids"], list) or not block["segment_ids"]:
        fail("segment_ids must be non-empty list")

    unavail = json.loads((FIXTURES / "sample-unavailable-summarize.json").read_text())
    for key in ("error", "tool", "message"):
        if key not in unavail:
            fail(f"unavailable fixture missing {key}")
    if unavail["error"] != "unavailable" or unavail["tool"] != "summarize_window":
        fail("unexpected unavailable payload")

    print("OK: agent-io fixture shapes match 02 Spec (ISO + per-track activity + speech blocks)")


if __name__ == "__main__":
    main()
