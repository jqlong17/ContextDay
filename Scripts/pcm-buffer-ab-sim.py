#!/usr/bin/env python3
"""Linux-side capacity check for PCM buffer A/B (Spec v0.3.29).

Does not measure macOS phys_footprint — only theoretical Int16@16k bytes.
Exit 0 when B peak <= A peak * 0.15 after a 600s fill simulation.
"""
from __future__ import annotations

SAMPLE_RATE = 16_000
BYTES_PER_SAMPLE = 2
VARIANT_A_SEC = 600
VARIANT_B_SEC = 60
PASS_RATIO = 0.15


def capacity_bytes(seconds: int) -> int:
    return SAMPLE_RATE * BYTES_PER_SAMPLE * seconds


def simulate_peak(cap_sec: int, write_sec: float) -> int:
    """Grow-then-cap (A) or hard ring (B): peak filled bytes after write_sec."""
    cap = capacity_bytes(cap_sec)
    written = int(write_sec * SAMPLE_RATE) * BYTES_PER_SAMPLE
    return min(written, cap)


def main() -> int:
    a_cap = capacity_bytes(VARIANT_A_SEC)
    b_cap = capacity_bytes(VARIANT_B_SEC)
    a_peak = simulate_peak(VARIANT_A_SEC, 600)
    b_peak = simulate_peak(VARIANT_B_SEC, 600)
    ratio = b_peak / a_peak if a_peak else float("inf")
    sum_a = a_peak * 2  # mic + system at soft-cap
    sum_b = b_peak * 2

    print("PCM buffer A/B capacity simulation (Int16 LE @ 16 kHz mono)")
    print(f"  A capacity/track : {a_cap} bytes ({VARIANT_A_SEC}s)")
    print(f"  B capacity/track : {b_cap} bytes ({VARIANT_B_SEC}s)")
    print(f"  After 600s write : A_peak={a_peak}  B_peak={b_peak}  ratio={ratio:.4f}")
    print(f"  Dual-track sum   : A={sum_a}  B={sum_b}")
    print(f"  Pass B<=A*{PASS_RATIO}: {ratio <= PASS_RATIO}")

    # Short-run note: at 3 min A is still growing (not yet 10x).
    a_3 = simulate_peak(VARIANT_A_SEC, 180)
    b_3 = simulate_peak(VARIANT_B_SEC, 180)
    print(f"  After 180s write : A_peak={a_3}  B_peak={b_3}  ratio={b_3 / a_3:.4f} (footprint A/B is Mac-only)")

    if ratio > PASS_RATIO:
        print("FAIL: peak ratio above threshold")
        return 1
    if b_cap != SAMPLE_RATE * 2 * VARIANT_B_SEC:
        print("FAIL: B capacity constant mismatch")
        return 1
    print("PASS: capacity ratio OK (Mac footprint still required for product flip confirmation)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
