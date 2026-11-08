#!/usr/bin/env python3
# crew: Android 17 sepolicy uses netlink extended permissions
#   (allowx|auditallowx|dontauditx|neverallowx <src> <tgt> (nlmsg <class> (...)))
# which only kernel 6.x SELinux understands; an older kernel cannot load the
# compiled policy and the boot dies before the boot animation. Drop exactly
# those statements (KotlinRom S9 fix). Every other rule is untouched.
# usage: crew_sepolicy_nlmsg.py [--count] <file.cil>...
import re, sys
RX = re.compile(r"^\s*\((allowx|auditallowx|dontauditx|neverallowx)\s.*\(nlmsg\s")
count_only = "--count" in sys.argv
total = 0
for p in [a for a in sys.argv[1:] if a != "--count"]:
    try:
        lines = open(p, encoding="utf-8", errors="surrogateescape").read().split("\n")
    except OSError:
        continue
    keep = [l for l in lines if not RX.match(l)]
    n = len(lines) - len(keep)
    total += n
    if n and not count_only:
        open(p, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(keep))
    if n:
        print(f"  {'found' if count_only else '- removed'} {n} nlmsg rule(s): {p.split('/system/', 1)[-1] if '/system/' in p else p}")
print(f"  nlmsg total: {total}")
