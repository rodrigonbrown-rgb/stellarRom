#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Point a smali patch at the smali_classesN tree each class really lives in.

A patch cut against another build of the same APK often only drifts in the dex
bucket a class landed in. Rewrite each path to the unique decoded location
(new files follow their .super class) so it can be dry-run at exact context.
Exit 1 if any class is missing or ambiguous.
"""
import re
import sys
from pathlib import Path

ROOT_RE = re.compile(r"smali(_classes\d+)?")


def locate(apk, rel):
    roots = sorted(p.name for p in apk.iterdir() if p.is_dir() and ROOT_RE.fullmatch(p.name))
    return [r for r in roots if (apk / r / rel).is_file()]


def main():
    apk, src, dst = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    lines = src.read_text(encoding="utf-8", errors="surrogateescape").splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith("diff --git ")]
    if not starts:
        sys.exit("no diff sections in %s" % src)
    out = lines[:starts[0]]
    for n, start in enumerate(starts):
        section = lines[start:starts[n + 1] if n + 1 < len(starts) else len(lines)]
        match = re.match(r"diff --git a/(\S+) b/(\S+)", section[0])
        if not match:
            sys.exit("bad diff header: " + section[0].strip())
        root, _, rel = match.group(2).partition("/")
        if not ROOT_RE.fullmatch(root):
            out.extend(section)
            continue
        if any(line.startswith("--- /dev/null") for line in section[:6]):
            if locate(apk, rel):
                sys.exit("%s already exists" % rel)
            parent = next((m.group(1) for m in (re.match(r"\+\.super L([^;]+);", l) for l in section) if m), None)
            hits = locate(apk, parent + ".smali") if parent else []
        else:
            hits = locate(apk, rel)
        if len(hits) != 1:
            sys.exit("%s: found in %s" % (rel, hits or "no smali tree"))
        if hits[0] != root:
            old, new = "%s/%s" % (root, rel), "%s/%s" % (hits[0], rel)
            section = [l.replace(old, new) if l.startswith(("diff --git ", "--- a/", "+++ b/")) else l
                       for l in section]
        out.extend(section)
    dst.write_text("".join(out), encoding="utf-8", errors="surrogateescape")


main()
