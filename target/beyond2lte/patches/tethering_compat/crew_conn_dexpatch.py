#!/usr/bin/env python3
# crew: same-size in-place dex edits in service-connectivity.jar
#   getLocalNetEventListener -> return null; BpfEventPoller.nativeInit*EventConsumer() calls -> nops
# usage: crew_conn_dexpatch.py [--check] <jar>   exit 0 ok, 3 targets missing
import hashlib, re, struct, sys, zlib, zipfile, os

DEPS_RE = re.compile(rb"/ConnectivityService\$Dependencies;$")
POLLER_RE = re.compile(rb"/BpfEventPoller;$")
CONSUMER_RE = re.compile(rb"^nativeInit\w*EventConsumer$")

u2 = lambda b, o: struct.unpack_from("<H", b, o)[0]
u4 = lambda b, o: struct.unpack_from("<I", b, o)[0]


def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1
        r |= (x & 0x7f) << s
        if x < 0x80:
            return r, o
        s += 7


def sstr(b, sids, i):
    _, o = uleb(b, u4(b, sids + i * 4))
    return bytes(b[o:b.index(b"\0", o)])


W = [1] * 256
for op, w in {0x02: 2, 0x03: 3, 0x05: 2, 0x06: 3, 0x08: 2, 0x09: 3, 0x13: 2, 0x14: 3,
              0x15: 2, 0x16: 2, 0x17: 3, 0x18: 5, 0x19: 2, 0x1a: 2, 0x1b: 3, 0x1c: 2,
              0x1f: 2, 0x20: 2, 0x22: 2, 0x23: 2, 0x24: 3, 0x25: 3, 0x26: 3, 0x29: 2,
              0x2a: 3, 0x2b: 3, 0x2c: 3, 0xfa: 4, 0xfb: 4, 0xfc: 3, 0xfd: 3, 0xfe: 2,
              0xff: 2}.items():
    W[op] = w
for lo, hi, w in ((0x2d, 0x3d, 2), (0x44, 0x6d, 2), (0x6e, 0x72, 3), (0x74, 0x78, 3),
                  (0x90, 0xaf, 2), (0xd0, 0xe2, 2)):
    for op in range(lo, hi + 1):
        W[op] = w


def insn_walk(b, ip, n):
    pc = 0
    while pc < n:
        unit = u2(b, ip + pc * 2)
        op = unit & 0xff
        if op == 0 and unit == 0x0100:
            pc += 4 + u2(b, ip + pc * 2 + 2) * 2
            continue
        if op == 0 and unit == 0x0200:
            pc += 2 + u2(b, ip + pc * 2 + 2) * 4
            continue
        if op == 0 and unit == 0x0300:
            width, size = u2(b, ip + pc * 2 + 2), u4(b, ip + pc * 2 + 4)
            pc += 4 + (size * width + 1) // 2
            continue
        yield pc
        pc += W[op]
    if pc != n:
        raise ValueError("instruction walk overran the code item")


def iter_methods(b):
    sids, tids, pids, mids = u4(b, 0x3C), u4(b, 0x44), u4(b, 0x4C), u4(b, 0x5C)
    tstr = lambda t: sstr(b, sids, u4(b, tids + t * 4))
    for i in range(u4(b, 0x60)):
        cd = u4(b, 0x64) + i * 32
        cname = tstr(u4(b, cd))
        cdata = u4(b, cd + 24)
        if not cdata:
            continue
        o = cdata
        sf, o = uleb(b, o); inf, o = uleb(b, o); dm, o = uleb(b, o); vm, o = uleb(b, o)
        for _ in range(sf + inf):
            _, o = uleb(b, o); _, o = uleb(b, o)
        for cnt in (dm, vm):
            midx = 0
            for _ in range(cnt):
                d, o = uleb(b, o); midx += d
                _, o = uleb(b, o)
                code, o = uleb(b, o)
                m = mids + midx * 8
                proto = pids + u2(b, m + 2) * 12
                yield cname, sstr(b, sids, u4(b, m + 4)), tstr(u4(b, proto + 4)), code


def patch_dex(b, check):
    if bytes(b[:4]) != b"dex\n":
        return []
    if bytes(b[4:7]) >= b"041":
        raise SystemExit("dex %s container format is not supported" % bytes(b[4:7]).decode())
    sids, tids, pids, mids = u4(b, 0x3C), u4(b, 0x44), u4(b, 0x4C), u4(b, 0x5C)
    tstr = lambda t: sstr(b, sids, u4(b, tids + t * 4))
    targets = {}
    for mi in range(u4(b, 0x58)):
        m = mids + mi * 8
        if not POLLER_RE.search(tstr(u2(b, m))):
            continue
        name = sstr(b, sids, u4(b, m + 4))
        proto = pids + u2(b, m + 2) * 12
        if CONSUMER_RE.match(name) and tstr(u4(b, proto + 4)) == b"V" and u4(b, proto + 8) == 0:
            targets[mi] = name.decode()
    log = []
    for cname, mname, ret, code in iter_methods(b):
        if not code:
            continue
        n = u4(b, code + 12)
        ip = code + 16
        if DEPS_RE.search(cname) and mname == b"getLocalNetEventListener" \
                and ret.endswith(b"/LocalNetEventListener;"):
            new = b"\x12\x00\x11\x00" + b"\x00\x00" * (n - 2)
            state = "already" if bytes(b[ip:ip + n * 2]) == new else "patched"
            if n < 2:
                raise SystemExit("getLocalNetEventListener body too small")
            if not check:
                b[ip:ip + n * 2] = new
            log.append(f"{cname.decode()}->getLocalNetEventListener = null [{state}]")
            continue
        if not targets:
            continue
        for pc in insn_walk(b, ip, n):
            o = ip + pc * 2
            op, aa = b[o], b[o + 1]
            if op in (0x71, 0x77) and u2(b, o + 2) in targets and \
                    ((op == 0x71 and aa >> 4 == 0) or (op == 0x77 and aa == 0)):
                callee = targets[u2(b, o + 2)]
                if not check:
                    b[o:o + 6] = b"\x00" * 6
                log.append(f"{cname.decode()}->{mname.decode()}: removed {callee}() @{pc:#x}")
    if not any("removed" in x for x in log) and targets:
        log.append("no live nativeInit*EventConsumer call sites (already patched?) [already]")
    if log and not check:
        b[12:32] = hashlib.sha1(bytes(b[32:])).digest()
        b[8:12] = struct.pack("<I", zlib.adler32(bytes(b[12:])) & 0xffffffff)
    return log


def fix_crc_in_place(raw, zi, newcrc):
    lh = zi.header_offset
    struct.pack_into("<I", raw, lh + 14, newcrc)
    name = zi.filename.encode()
    p = 0
    while True:
        p = raw.find(b"PK\x01\x02", p)
        if p < 0:
            raise SystemExit("central directory entry not found for " + zi.filename)
        nlen = u2(raw, p + 28)
        if bytes(raw[p + 46:p + 46 + nlen]) == name and u4(raw, p + 42) == lh:
            struct.pack_into("<I", raw, p + 16, newcrc)
            return
        p += 4


def main():
    a = sys.argv[1:]
    check = a[:1] == ["--check"]
    if check:
        a = a[1:]
    path = a[0]
    raw = bytearray(open(path, "rb").read())
    logs, patched = [], {}
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        for zi in infos:
            if not re.fullmatch(r"classes\d*\.dex", zi.filename):
                continue
            d = bytearray(z.read(zi))
            r = patch_dex(d, check)
            logs += [f"{zi.filename}: {x}" for x in r]
            if r and not check:
                patched[zi.filename] = (zi, bytes(d))
    for x in logs:
        print("   ", x)
    deps = any("getLocalNetEventListener" in x for x in logs)
    cons = any("removed" in x or "[already]" in x for x in logs)
    if check:
        sys.exit(0 if deps else 3)
    if not (deps and cons):
        print("    missing target(s): getLocalNetEventListener=%s consumer-calls=%s" % (deps, cons))
        sys.exit(3)
    if all(zi.compress_type == zipfile.ZIP_STORED and not zi.flag_bits & 0x08
           for zi, _ in patched.values()):
        for zi, d in patched.values():
            lh = zi.header_offset
            start = lh + 30 + u2(raw, lh + 26) + u2(raw, lh + 28)
            raw[start:start + len(d)] = d
            fix_crc_in_place(raw, zi, zlib.crc32(d) & 0xffffffff)
        open(path, "wb").write(raw)
    else:
        tmp = path + ".crewtmp"
        with zipfile.ZipFile(path) as zr, zipfile.ZipFile(tmp, "w") as zo:
            for zi in infos:
                data = patched[zi.filename][1] if zi.filename in patched else zr.read(zi)
                zo.writestr(zi, data, compress_type=zi.compress_type)
        os.replace(tmp, path)
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            sys.exit(f"CRC check failed for {bad}")


if __name__ == "__main__":
    main()
