#!/usr/bin/env python3
"""Phase 1 decision gate for the tokens-per-percent study.

Reads the JSONL written by CalibrationLog and answers one question: is a limit-window percentage
convertible into a token figure tightly enough to display as a number?

Usage:
    ./scripts/analyse-calibration.py [path-to-jsonl]

Default path: ~/Library/Logs/PokeTokenBar.calibration.jsonl

The gate: within-window spread (p90/p10) under 1.5x means proceed to an estimated token figure.
Near the 4.0x measured before this instrumentation existed means stop, and drive the feature from
limit points instead, which need no conversion at all.

Why seven_day is the primary instrument: five_hour rolls, so its delta nets new usage against
usage ageing out and is not an integral. seven_day does not roll within a day.
"""
import json
import os
import sys
from collections import defaultdict

DEFAULT = os.path.expanduser("~/Library/Logs/PokeTokenBar.calibration.jsonl")
KINDS = ("input", "output", "cacheWrite", "cacheRead")


def load(path):
    rows = []
    with open(path, errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue          # torn final line costs one sample, not the set
    rows.sort(key=lambda r: r.get("t", 0))
    return rows


def totals(sample):
    """Token totals for this observation, by kind and overall, across all providers."""
    by_kind = dict.fromkeys(KINDS, 0)
    total = 0
    for p in sample.get("providers", []):
        for k in KINDS:
            by_kind[k] += p.get(k, 0) or 0
        total += p.get("total", 0) or 0
    return by_kind, total


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p))]


def analyse(rows, window):
    """tokens-per-percent samples for one window key, plus the token mix in each interval."""
    out = []
    for a, b in zip(rows, rows[1:]):
        dt = b.get("t", 0) - a.get("t", 0)
        if dt <= 0 or dt > 600:                       # ignore gaps: usage may have aged out
            continue
        pa, pb = a.get(window), b.get(window)
        if pa is None or pb is None:
            continue
        dpct = pb - pa
        if dpct <= 0:                                 # window reset or idle
            continue
        ka, ta = totals(a)
        kb, tb = totals(b)
        dtok = tb - ta
        if dtok <= 0:                                 # midnight reset or no local activity
            continue
        mix = {k: kb[k] - ka[k] for k in KINDS}
        out.append({"ratio": dtok / dpct, "dtok": dtok, "dpct": dpct, "mix": mix})
    return out


def report(name, samples):
    print(f"\n{name}: {len(samples)} usable intervals")
    if len(samples) < 5:
        print("  not enough data yet — keep collecting")
        return None
    ratios = [s["ratio"] for s in samples]
    p10, p50, p90 = pct(ratios, 0.10), pct(ratios, 0.50), pct(ratios, 0.90)
    spread = p90 / p10 if p10 else float("inf")
    print(f"  tokens per 1%:  p10 {p10:,.0f}   median {p50:,.0f}   p90 {p90:,.0f}")
    print(f"  spread p90/p10: {spread:.2f}x")

    # Does cache-read share explain the variance? If heavy-cache intervals sit at a different
    # ratio from light-cache ones, the fit needs to weight kinds separately rather than use one
    # constant. That is the whole reason the kinds are logged apart.
    withshare = []
    for s in samples:
        tot = sum(s["mix"].values())
        if tot > 0:
            withshare.append((s["mix"]["cacheRead"] / tot, s["ratio"]))
    if len(withshare) >= 6:
        withshare.sort()
        half = len(withshare) // 2
        lo = sum(r for _, r in withshare[:half]) / half
        hi = sum(r for _, r in withshare[half:]) / (len(withshare) - half)
        print(f"  low-cache intervals  mean ratio: {lo:,.0f}")
        print(f"  high-cache intervals mean ratio: {hi:,.0f}")
        if lo:
            print(f"  cache effect: {hi / lo:.2f}x  (>1.3x means weight kinds separately)")
    return spread


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        sys.exit(f"no calibration log at {path} — is logging enabled and has the app polled?")
    rows = load(path)
    print(f"samples: {len(rows)}")
    if rows:
        span_h = (rows[-1]["t"] - rows[0]["t"]) / 3600
        print(f"span: {span_h:.1f} hours")
        models = {w.get("model") for r in rows for w in r.get("scoped", []) if w.get("model")}
        print(f"per-model windows seen: {sorted(models) if models else 'none'}")
        if not models:
            print("  (no scoped model windows — per-model calibration is not available)")

    spread = report("seven_day (primary)", analyse(rows, "sd"))
    report("five_hour (rolls; for comparison only)", analyse(rows, "fh"))

    print("\n--- gate ---")
    if spread is None:
        print("UNDECIDED — collect more data")
    elif spread <= 1.5:
        print(f"PASS ({spread:.2f}x) — a displayed token estimate is defensible")
    else:
        print(f"FAIL ({spread:.2f}x) — do not display a token figure; use limit points")


if __name__ == "__main__":
    main()
