#!/usr/bin/env python3
# crew: keep the S10 face libs private: same-length rename of any lib One UI 9 also ships
import sys, os, re, filecmp, glob
stage, root = sys.argv[1], sys.argv[2]
def die(m): print('faceport_libs: ERROR ' + m); sys.exit(1)
libs = [os.path.join(d, f) for d, _, fs in os.walk(os.path.join(stage, 'lib64')) for f in fs if f.endswith('.so')]
elfs = libs + [os.path.join(stage, 'bin/faced')]
ren = {}
for p in libs:
    rel = os.path.relpath(p, stage); tgt = os.path.join(root, rel); name = os.path.basename(p)
    if not os.path.exists(tgt): continue
    if filecmp.cmp(p, tgt, shallow=False):
        os.remove(p); elfs.remove(p); print('faceport_libs: identical to ROM copy, using ROM: ' + rel); continue
    if rel.startswith('lib64/hw/'): print('faceport_libs: WARNING overriding ROM ' + rel); continue
    new = ('lic' + name[3:]) if name.startswith('lib') else ('c' + name[1:])
    if os.path.exists(os.path.join(os.path.dirname(tgt), new)): die('rename target exists: ' + new)
    ren[name] = new
for name, new in ren.items():
    pat = re.compile(rb'(?<=\x00)' + re.escape(name.encode()) + rb'\x00')
    for e in elfs:
        if not os.path.exists(e): continue
        b = open(e, 'rb').read(); nb = pat.sub(new.encode() + b'\x00', b)
        if nb != b: open(e, 'wb').write(nb)
    src = [p for p in libs if os.path.basename(p) == name][0]
    dst = os.path.join(os.path.dirname(src), new)
    os.rename(src, dst); elfs[elfs.index(src)] = dst
    print('faceport_libs: ROM has its own %s -> S10 copy renamed %s' % (name, new))
print('faceport_libs: %d private renames' % len(ren))
# crew: S10 libutils imports the C SetTaskProfiles that One UI 9 libprocessgroup dropped ->
# point its libprocessgroup.so dependency at libprocessgr_fc.so (exports it, then pulls in the real libprocessgroup)
shim = os.path.join(stage, 'lib64', 'libprocessgr_fc.so')
if os.path.exists(shim):
    for e in sorted(glob.glob(os.path.join(stage, 'lib64', '*.so'))):
        if os.path.samefile(e, shim): continue
        b = open(e, 'rb').read()
        if b'\x00SetTaskProfiles\x00' in b and b.count(b'\x00libprocessgroup.so\x00') == 1:
            open(e, 'wb').write(b.replace(b'\x00libprocessgroup.so\x00', b'\x00libprocessgr_fc.so\x00'))
            print('faceport_libs: %s -> libprocessgr_fc.so (SetTaskProfiles shim)' % os.path.basename(e))
