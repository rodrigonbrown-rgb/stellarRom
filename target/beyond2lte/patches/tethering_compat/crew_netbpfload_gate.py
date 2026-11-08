#!/usr/bin/env python3
# crew: bypass only NetBpfLoad "Android 25Q4/26Q3 requires kernel X" hard refusals
import hashlib, sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
gates = [
    (b"Android 25Q4 requires kernel 5.10.", [
        ("280200546808009008614439c8010036", "2802005468080090086144390e000014"),
        ("6a0800d04a914439ca000036", "6a0800d04a91443906000014"),
    ]),
    (b"Android 26Q3 requires kernel 5.15.", [
        ("680800d008a1443928010036", "680800d008a1443909000014"),
    ]),
]
print(f"      netbpfload sha256 {hashlib.sha256(d).hexdigest()} (in)")
fail = not any(msg in d for msg, _ in gates)
if fail:
    print("      unknown NetBpfLoad: none of the known kernel-gate messages present")
for msg, pats in gates:
    if msg not in d:
        continue
    done = False
    for f, t in pats:
        fb, tb = bytes.fromhex(f), bytes.fromhex(t)
        if d.count(fb) == 0 and d.count(tb) == 1:
            print(f"      already bypassed: {msg.decode()}")
            done = True
            break
        if d.count(fb) == 1:
            i = d.find(fb)
            d[i:i + len(fb)] = tb
            print(f"      bypassed: {msg.decode()} @ {i:#x}")
            done = True
            break
    if not done:
        print(f"      NO GATE MATCH: {msg.decode()}")
        fail = True
if not fail:
    open(p, "wb").write(d)
print(f"      netbpfload sha256 {hashlib.sha256(d).hexdigest()} (out)")
sys.exit(1 if fail else 0)
