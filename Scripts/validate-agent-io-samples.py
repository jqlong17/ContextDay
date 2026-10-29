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
    "track",
    "gate_label",
    "text",
    "tz_at_capture",
    "audio_path",
}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    search = json.loads((FIXTURES / "sample-search-segments.json").read_text())
    if not isinstance(search, list) or not search:
        fail("search fixture must be non-empty array")
    row = search[0]
    missing = SEGMENT_KEYS - set(row)
    if missing:
        fail(f"search row missing keys: {sorted(missing)}")
    extra_camel = [k for k in row if any(c.isupper() for c in k)]
    if extra_camel:
        fail(f"camelCase keys not allowed: {extra_camel}")
    if row["track"] not in ("mic", "system"):
        fail("track must be mic|system")

    unavail = json.loads((FIXTURES / "sample-unavailable-summarize.json").read_text())
    for key in ("error", "tool", "message"):
        if key not in unavail:
            fail(f"unavailable fixture missing {key}")
    if unavail["error"] != "unavailable" or unavail["tool"] != "summarize_window":
        fail("unexpected unavailable payload")

    print("OK: agent-io fixture shapes match LLM-facing snake_case contract")


if __name__ == "__main__":
    main()
