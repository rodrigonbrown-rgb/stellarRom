#!/usr/bin/env python3
# crew: force a static boolean field to a constant at the end of its <clinit>
# assignment, using a fresh register (no reuse of donor registers, so it is
# immune to register-allocation drift between donor builds).
# usage: crew_smali_force_bool.py <decoded apk/jar dir> <Lpkg/Class;> <FIELD> <true|false>
import re, sys
from pathlib import Path
root, cls, field, val = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
rel = cls[1:-1] + ".smali"
hits = [p for p in Path(root).glob("smali*/" + rel)]
if len(hits) != 1:
    sys.exit(f"{rel}: {len(hits)} candidates under {root}")
f = hits[0]; s = f.read_text()
m = re.search(r"^\.method static constructor <clinit>\(\)V\n(.*?)^\.end method", s, re.M | re.S)
if not m:
    sys.exit(f"{f.name}: no <clinit>")
body = m.group(1)
ref = f"{cls}->{field}:Z"
marker = f"# crew-force-bool {field}"
if marker in body:
    print(f"      {f.name}: {field} already forced"); sys.exit(0)
sputs = list(re.finditer(r"^    sput-boolean [vp]\d+, " + re.escape(ref) + r"\n", body, re.M))
if not sputs:
    sys.exit(f"{f.name}: no sput-boolean of {field} in <clinit>")
rm = re.search(r"^    \.(locals|registers) (\d+)$", body, re.M)
if not rm:
    sys.exit(f"{f.name}: no .locals/.registers in <clinit>")
n = int(rm.group(2))
if n >= 255:
    sys.exit(f"{f.name}: too many registers ({n})")
last = sputs[-1]
ins = (f"\n    {marker}\n    const/16 v{n}, 0x{1 if val == 'true' else 0}\n\n"
       f"    sput-boolean v{n}, {ref}\n")
body = body[:last.end()] + ins + body[last.end():]
body = body[:rm.start()] + f"    .{rm.group(1)} {n + 1}" + body[rm.end():]
s = s[:m.start(1)] + body + s[m.end(1):]
f.write_text(s)
print(f"      {f.name}: {field} forced {val} (v{n}, after {len(sputs)} sput)")
