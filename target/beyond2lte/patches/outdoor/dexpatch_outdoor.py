#!/usr/bin/env python3
# crew: same-size bytecode rewrite of SecOutDoorModePreferenceController.isAvailable()Z -> true
# usage: dexpatch_outdoor.py [--check] <file.dex|file.apk> [...]
import hashlib, re, struct, sys, zlib, zipfile, os
CLS_RE = re.compile(rb'^Lcom/samsung/android/settings/.*/SecOutDoorModePreferenceController;$')
def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1
        r |= (x & 0x7f) << s
        if x < 0x80: return r, o
        s += 7
def u4(b, o): return struct.unpack_from('<I', b, o)[0]
def u2(b, o): return struct.unpack_from('<H', b, o)[0]
def string_at(b, sids, idx):
    off = u4(b, sids + idx * 4); _, o = uleb(b, off)
    return bytes(b[o:b.index(b'\0', o)])
CHECK = False
def patch_dex(b):
    if b[:4] != b'dex\n': return []
    if bytes(b[4:7]) == b'041': return ['SKIP-v41']
    sids, tids, pids, mids = u4(b, 0x3C), u4(b, 0x44), u4(b, 0x4C), u4(b, 0x5C)
    ncls, cdefs = u4(b, 0x60), u4(b, 0x64)
    tstr = lambda t: string_at(b, sids, u4(b, tids + t * 4))
    done = []
    for i in range(ncls):
        cd = cdefs + i * 32
        cname = tstr(u4(b, cd))
        if not CLS_RE.match(cname) or not u4(b, cd + 24): continue
        o = u4(b, cd + 24)
        sf, o = uleb(b, o); inf, o = uleb(b, o); dm, o = uleb(b, o); vm, o = uleb(b, o)
        for _ in range(sf + inf): _, o = uleb(b, o); _, o = uleb(b, o)
        for n in (dm, vm):
            midx = 0
            for _ in range(n):
                d, o = uleb(b, o); midx += d; _, o = uleb(b, o); code, o = uleb(b, o)
                m = mids + midx * 8
                name = string_at(b, sids, u4(b, m + 4))
                proto = pids + u2(b, m + 2) * 12
                ret = tstr(u4(b, proto + 4))
                if u4(b, proto + 8) or not code: continue
                if name == b'isAvailable' and ret == b'Z': val = 1
                elif name == b'getAvailabilityStatus' and ret == b'I': val = 0
                else: continue
                insns = u4(b, code + 12)
                if u2(b, code) < 1 or insns < 2: continue
                ip = code + 16
                new = struct.pack('<HH', 0x12 | ((val & 0xf) << 12), 0x000f) + b'\0\0' * (insns - 2)
                state = 'PATCHED' if bytes(b[ip:ip + insns * 2]) == new else 'STOCK'
                if not CHECK: b[ip:ip + insns * 2] = new; state = 'PATCHED'
                done.append('%s->%s()%s = %d [%s]' % (cname.decode(), name.decode(), ret.decode(), val, state))
    if done and not CHECK:
        b[12:32] = hashlib.sha1(bytes(b[32:])).digest()
        b[8:12] = struct.pack('<I', zlib.adler32(bytes(b[12:])) & 0xffffffff)
    return done
def do_dex(p):
    b = bytearray(open(p, 'rb').read()); r = patch_dex(b)
    if r and r != ['SKIP-v41'] and not CHECK: open(p, 'wb').write(b)
    return r
def do_apk(p):
    hits, data = [], {}
    with zipfile.ZipFile(p) as zi:
        infos = zi.infolist()
        for z in infos:
            if re.fullmatch(r'classes\d*\.dex', z.filename):
                b = bytearray(zi.read(z)); r = patch_dex(b)
                if r and r != ['SKIP-v41'] and not CHECK: data[z.filename] = bytes(b)
                hits += ['%s:%s' % (z.filename, x) for x in r]
        if not data: return hits
        with zipfile.ZipFile(p + '.crewtmp', 'w') as zo:
            for z in infos: zo.writestr(z, data.get(z.filename) or zi.read(z), compress_type=z.compress_type)
    os.replace(p + '.crewtmp', p); return hits
if __name__ == '__main__':
    args = sys.argv[1:]; total = 0
    if args and args[0] == '--check': CHECK = True; args = args[1:]
    for p in args:
        if not os.path.isfile(p): continue
        r = do_apk(p) if p.endswith(('.apk', '.jar', '.zip')) else do_dex(p)
        for x in r: print('  %s: %s' % (os.path.basename(p), x))
        total += len([x for x in r if 'PATCHED' in x])
    sys.exit(0 if total else 3)
