#!/usr/bin/env python3
# crew: rootless APEX payload unpack/repack helper (no mount, no sudo).
#   crew_apex.py unpack <apex|capex> <outdir> [--tools-bin DIR]
#   crew_apex.py zip <outdir> <payload.img> <pubkey> <out.apex>
import json, os, re, shutil, struct, subprocess, sys, tempfile, zipfile
from pathlib import Path

DEFAULT_LABEL = "u:object_r:system_file:s0"


def tool(name, extra):
    for d in extra:
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return shutil.which(name)


def manifest_name(pb):
    i = 0
    while i < len(pb):
        key = pb[i]; i += 1
        field, wt = key >> 3, key & 7
        if wt == 0:
            while pb[i] & 0x80:
                i += 1
            i += 1
        elif wt == 2:
            ln = s = 0
            while True:
                b = pb[i]; i += 1
                ln |= (b & 0x7f) << s; s += 7
                if b < 0x80:
                    break
            if field == 1:
                return pb[i:i + ln].decode()
            i += ln
        elif wt == 5:
            i += 4
        elif wt == 1:
            i += 8
        else:
            break
    return None


def caps_of(raw):
    if not raw or len(raw) < 12:
        return 0
    magic = struct.unpack_from("<I", raw, 0)[0] & 0xFF000000
    lo = struct.unpack_from("<I", raw, 4)[0]
    hi = struct.unpack_from("<I", raw, 12)[0] if magic >= 0x02000000 and len(raw) >= 16 else 0
    return lo | (hi << 32)


def fc_escape(rel):
    return re.sub(r"([.+*?\[\]()^$|{}\\])", r"\\\1", rel)


def ext4_meta(debugfs, img, tree, tmp):
    rels = [""] + sorted(str(p.relative_to(tree)) for p in tree.rglob("*"))
    ea = Path(tempfile.mkdtemp(dir=tmp))
    cmds = []
    for n, rel in enumerate(rels):
        q = "/" + rel
        cmds.append(f'stat "{q}"')
        cmds.append(f'ea_get -f {ea}/se{n} "{q}" security.selinux')
        cmds.append(f'ea_get -f {ea}/cap{n} "{q}" security.capability')
    cf = ea / "cmds"
    cf.write_text("\n".join(cmds) + "\n")
    out = subprocess.run([debugfs, "-f", str(cf), str(img)], capture_output=True,
                         text=True, errors="replace").stdout
    blocks = re.split(r'^debugfs: stat "(.*)"$', out, flags=re.M)
    st = {}
    for i in range(1, len(blocks), 2):
        b = blocks[i + 1]
        m = re.search(r"Mode:\s+(0?[0-7]+)", b)
        u = re.search(r"User:\s+(\d+)\s+Group:\s+(\d+)", b)
        if not (m and u):
            raise SystemExit(f"debugfs stat failed for {blocks[i]}")
        st[blocks[i]] = (int(u.group(1)), int(u.group(2)), int(m.group(1), 8) & 0o7777)
    meta = {}
    for n, rel in enumerate(rels):
        q = "/" + rel
        if q not in st:
            raise SystemExit(f"debugfs: no stat for {q}")
        se = ea / f"se{n}"
        label = se.read_bytes().rstrip(b"\0").decode() if se.is_file() and se.stat().st_size else None
        cap = ea / f"cap{n}"
        caps = caps_of(cap.read_bytes()) if cap.is_file() else 0
        meta[rel] = (*st[q], caps, label)
    shutil.rmtree(ea, ignore_errors=True)
    return meta


class Erofs:
    def __init__(self, path):
        self.d = Path(path).read_bytes()
        sb = 1024
        if struct.unpack_from("<I", self.d, sb)[0] != 0xE0F5E1E2:
            raise SystemExit("not an erofs image")
        self.bits = self.d[sb + 12]
        self.bs = 1 << self.bits
        self.root = struct.unpack_from("<H", self.d, sb + 14)[0]
        self.meta = struct.unpack_from("<I", self.d, sb + 40)[0] << self.bits
        self.xattr = struct.unpack_from("<I", self.d, sb + 44)[0] << self.bits

    def inode(self, nid):
        o = self.meta + nid * 32
        fmt, icount, mode = struct.unpack_from("<HHH", self.d, o)
        ext = fmt & 1
        layout = (fmt >> 1) & 7
        if ext:
            size = struct.unpack_from("<Q", self.d, o + 8)[0]
            raw, _, uid, gid = struct.unpack_from("<IIII", self.d, o + 16)
            isz = 64
        else:
            size = struct.unpack_from("<I", self.d, o + 8)[0]
            raw = struct.unpack_from("<I", self.d, o + 16)[0]
            uid, gid = struct.unpack_from("<HH", self.d, o + 24)
            isz = 32
        xsz = 0 if icount == 0 else 12 + (icount - 1) * 4
        return dict(off=o, mode=mode, layout=layout, size=size, raw=raw, uid=uid,
                    gid=gid, isz=isz, xsz=xsz)

    def _entry(self, p):
        nlen, idx, vlen = struct.unpack_from("<BBH", self.d, p)
        name = self.d[p + 4:p + 4 + nlen]
        val = self.d[p + 4 + nlen:p + 4 + nlen + vlen]
        return idx, name, val, (4 + nlen + vlen + 3) & ~3

    def xattrs(self, ino):
        out = {}
        if not ino["xsz"]:
            return out
        p = ino["off"] + ino["isz"]
        end = p + ino["xsz"]
        shared = self.d[p + 4]
        q = p + 12
        for _ in range(shared):
            sid = struct.unpack_from("<I", self.d, q)[0]; q += 4
            idx, name, val, _ = self._entry(self.xattr + sid * 4)
            out[(idx, name)] = val
        while q + 4 <= end:
            idx, name, val, step = self._entry(q)
            out[(idx, name)] = val
            q += step
        return out

    def data(self, ino):
        lay, size = ino["layout"], ino["size"]
        if lay == 0:
            s = ino["raw"] << self.bits
            return self.d[s:s + size]
        if lay == 2:
            full = size // self.bs * self.bs
            s = ino["raw"] << self.bits
            tail = ino["off"] + ino["isz"] + ino["xsz"]
            return self.d[s:s + full] + self.d[tail:tail + size - full]
        raise SystemExit(f"erofs: unsupported directory layout {lay}")

    def readdir(self, ino):
        d = self.data(ino)
        out = []
        for b in range(0, len(d), self.bs):
            blk = d[b:b + self.bs]
            if len(blk) < 12:
                break
            n = struct.unpack_from("<H", blk, 8)[0] // 12
            ents = [struct.unpack_from("<QHBB", blk, i * 12) for i in range(n)]
            for i, (nid, noff, _, _) in enumerate(ents):
                nend = ents[i + 1][1] if i + 1 < n else len(blk)
                name = blk[noff:nend].split(b"\0", 1)[0].decode()
                if name not in (".", ".."):
                    out.append((name, nid))
        return out

    def walk(self):
        stack = [("", self.root)]
        while stack:
            rel, nid = stack.pop()
            ino = self.inode(nid)
            yield rel, ino
            if (ino["mode"] & 0o170000) == 0o040000:
                for name, cnid in self.readdir(ino):
                    stack.append((f"{rel}/{name}" if rel else name, cnid))


def erofs_meta(img):
    e = Erofs(img)
    meta = {}
    for rel, ino in e.walk():
        xa = e.xattrs(ino)
        se = xa.get((6, b"selinux"))
        meta[rel] = (ino["uid"], ino["gid"], ino["mode"] & 0o7777,
                     caps_of(xa.get((6, b"capability"))),
                     se.rstrip(b"\0").decode() if se else None)
    return meta


def unpack(archive, out, tools_bin):
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    (out / "apex").mkdir(parents=True)
    tmp = out / ".tmp"
    tmp.mkdir()
    z = zipfile.ZipFile(archive)
    if "original_apex" in z.namelist():
        inner = tmp / "original.apex"
        with z.open("original_apex") as s, open(inner, "wb") as d:
            shutil.copyfileobj(s, d)
        z.close()
        z = zipfile.ZipFile(inner)
    img = out / "original_payload.img"
    for zi in z.infolist():
        if zi.filename == "apex_payload.img":
            with z.open(zi) as s, open(img, "wb") as d:
                shutil.copyfileobj(s, d)
        elif not zi.filename.startswith("META-INF/") and not zi.is_dir():
            dst = out / "apex" / zi.filename
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(z.read(zi))
    order = [zi.filename for zi in z.infolist()
             if not zi.filename.startswith("META-INF/") and not zi.is_dir()]
    stored = [zi.filename for zi in z.infolist() if zi.compress_type == zipfile.ZIP_STORED]
    z.close()
    if not img.is_file():
        raise SystemExit("APEX has no apex_payload.img")

    tree = out / "payload"
    tree.mkdir()
    with open(img, "rb") as f:
        f.seek(1024 + 0x38)
        is_ext4 = f.read(2) == b"\x53\xef"
    if is_ext4:
        dfs = tool("debugfs", tools_bin)
        if not dfs:
            raise SystemExit("debugfs not found")
        subprocess.run([dfs, "-R", f"rdump / {tree}", str(img)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(tree / "lost+found", ignore_errors=True)
        meta = ext4_meta(dfs, img, tree, tmp)
    else:
        fsck = tool("fsck.erofs", tools_bin)
        if not fsck:
            raise SystemExit("fsck.erofs not found")
        subprocess.run([fsck, f"--extract={tree}", "--no-preserve", str(img)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        meta = erofs_meta(img)
    on_disk = {""} | {str(p.relative_to(tree)) for p in tree.rglob("*")}
    missing = sorted(on_disk - set(meta))
    if missing:
        raise SystemExit(f"no metadata for: {missing[:5]}")

    root_label = meta[""][4] or DEFAULT_LABEL
    fsc, fc, nolabel = [], [f"/ {root_label}"], 0
    for rel in sorted(meta):
        if rel not in on_disk:
            continue
        uid, gid, mode, caps, label = meta[rel]
        fsc.append(f"{rel} {uid} {gid} {mode:o} capabilities={caps:#x}")
        if rel:
            if label is None:
                nolabel += 1
                label = DEFAULT_LABEL
            fc.append(f"/{fc_escape(rel)} {label}")
    (out / "fs_config").write_text("\n".join(fsc) + "\n")
    (out / "file_contexts").write_text("\n".join(fc) + "\n")

    key = None
    avb = tool("avbtool", tools_bin)
    if avb:
        r = subprocess.run([avb, "info_image", "--image", str(img)], capture_output=True, text=True)
        m = re.search(r"Prop:\s*apex\.key\s*->\s*'([^']*)'", r.stdout)
        key = m.group(1) if m else None
    name = manifest_name((out / "apex/apex_manifest.pb").read_bytes())
    info = {"fs": "ext4" if is_ext4 else "erofs", "name": name, "apex_key": key or name,
            "order": order, "stored": stored, "unlabeled": nolabel,
            "special": {r: f"{m[0]}:{m[1]} {m[2]:o} caps={m[3]:#x} {m[4]}"
                        for r, m in meta.items() if m[4] not in (None, DEFAULT_LABEL) or m[3]
                        or m[2] & 0o7000 or m[0] or m[1]}}
    (out / "info.json").write_text(json.dumps(info, indent=1))
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"  {info['fs']} payload, {len(meta)} entries, name={name}, apex.key={info['apex_key']}")
    for r, s in sorted(info["special"].items()):
        print(f"    /{r}: {s}")
    if nolabel:
        print(f"    WARNING: {nolabel} entries had no security.selinux, defaulted to {DEFAULT_LABEL}")


def rezip(out, payload, pubkey, dest):
    out = Path(out)
    info = json.loads((out / "info.json").read_text())
    names = list(info["order"])
    for must in ("apex_payload.img", "apex_pubkey"):
        if must not in names:
            names.append(must)
    with zipfile.ZipFile(dest, "w") as z:
        for n in names:
            src = payload if n == "apex_payload.img" else pubkey if n == "apex_pubkey" \
                else out / "apex" / n
            ct = zipfile.ZIP_STORED if (n in info["stored"] or n in
                                        ("apex_payload.img", "apex_pubkey")) else zipfile.ZIP_DEFLATED
            zi = zipfile.ZipInfo(n, date_time=(2009, 1, 1, 0, 0, 0))
            zi.compress_type = ct
            zi.external_attr = 0o644 << 16
            z.writestr(zi, Path(src).read_bytes())
    print(f"  assembled {dest} ({len(names)} entries)")


if __name__ == "__main__":
    a = sys.argv[1:]
    tb = []
    if "--tools-bin" in a:
        i = a.index("--tools-bin"); tb = [a[i + 1]]; del a[i:i + 2]
    if a[:1] == ["unpack"] and len(a) == 3:
        unpack(a[1], a[2], tb)
    elif a[:1] == ["zip"] and len(a) == 5:
        rezip(*a[1:])
    else:
        sys.exit("usage: crew_apex.py unpack <apex> <out> | zip <out> <img> <pubkey> <dest>")
