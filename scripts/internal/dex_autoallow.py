#!/usr/bin/env python3
"""Write the exact allowed-additions TSV for DEX trees a module flagged as extended.

Only the logical DEX units listed in --smali-list are diffed against the stock
entries; every other unit must still match stock exactly at verify time.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dex_inventory as di  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=Path, required=True)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--artifact", type=Path, required=True)
    ap.add_argument("--smali-list", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--baksmali", default="baksmali")
    a = ap.parse_args()

    wanted = {l.strip() for l in a.smali_list.read_text().splitlines() if l.strip()}
    rows = []
    for e in di.load_logical_map(a.map):
        if e.smali_dir not in wanted:
            continue
        for kind in di.INVENTORY_KINDS:
            src = set(di.run_baksmali_list(a.baksmali, kind, di._artifact_spec(a.source, e.source_entry)))
            new = set(di.run_baksmali_list(a.baksmali, kind, di._artifact_spec(a.artifact, e.output_dex)))
            removed = src - new
            if removed:
                print(f"dex_autoallow: {e.smali_dir} {kind} removed {len(removed)} item(s): "
                      f"{sorted(removed)[:5]}", file=sys.stderr)
                return 1
            rows += [f"{e.index}\t{kind}\t{i}" for i in sorted(new - src)]

    a.out.parent.mkdir(parents=True, exist_ok=True)
    if rows:
        a.out.write_text("logical_index\tkind\titem\n" + "\n".join(rows) + "\n", encoding="utf-8")
        print(f"dex_autoallow: {len(rows)} addition(s) -> {a.out}")
    elif a.out.exists():
        a.out.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
