#!/usr/bin/env python3
# crew: ABI gate for the hybrid essi85 layout (API 37 donor + API 36 multilib).
#
# _desixtification swaps com.android.runtime + com.android.i18n (and the 32-bit
# system/lib layer) from MULTILIB_FIRMWARE into the work dir. That is only safe
# if every 64-bit ELF of the donor that will keep running (system, system_ext,
# product, odm and every other donor APEX payload) can still resolve the
# symbols it imports from bionic/ICU against the multilib APEX copies, and if
# the multilib APEX libs can resolve their own outside imports against the
# donor's system libs.
#
# usage: crew_runtime_abi_check.py <donor_fw_dir> <multilib_fw_dir>
#            [--tools-bin DIR] [--json FILE] [--keep-tmp]
# exit: 0 = swap is ABI safe, 1 = missing symbols/libs (report printed), 2 = tool error
import argparse, json, os, re, shutil, struct, subprocess, sys, tempfile, zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RUNTIME = "com.android.runtime"
I18N = "com.android.i18n"
MACHINE = int(os.environ.get("CREW_ABI_MACHINE", "183"))  # EM_AARCH64


def which(name, extra):
    for d in extra:
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return shutil.which(name)


def is_elf64(path):
    try:
        with open(path, "rb") as f:
            h = f.read(20)
    except OSError:
        return False
    return (len(h) == 20 and h[:4] == b"\x7fELF" and h[4] == 2
            and struct.unpack_from("<H", h, 18)[0] == MACHINE)


SYM_RE = re.compile(r"^\s*\d+:\s+[0-9a-fA-F]+\s+\S+\s+(<[^>]*>:\s*\d+|\w+)\s+(\w+)\s+\w+(?:\s+\[[^\]]*\])*\s+(\S+)\s+(\S.*)$")


def strip_ver(name):
    return re.sub(r"\s+\(\d+\)$", "", name).split("@", 1)[0]


class Tools:
    def __init__(self, extra):
        self.readelf = which("readelf", extra) or which("llvm-readelf", extra)
        self.debugfs = which("debugfs", extra)
        self.fsck_erofs = which("fsck.erofs", extra)
        if not self.readelf:
            sys.exit("readelf not found")

    def elf(self, path):
        """-> (needed[list], undefined_strong[set], defined[set], odd_dyn_tags[set])"""
        r = subprocess.run([self.readelf, "-d", "--dyn-syms", "-W", str(path)],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                           errors="replace")
        needed, und, defined, odd = [], set(), set(), set()
        for line in r.stdout.splitlines():
            m = re.search(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", line)
            if m:
                needed.append(m.group(1))
                continue
            m = re.match(r"\s*0x[0-9a-f]+\s+\((.+?)\)", line)
            if m and ("unknown" in m.group(1).lower() or m.group(1).startswith("0x")):
                odd.add(m.group(1))
                continue
            # AArch64 readelf adds "[VARIANT_PCS]" after Vis -> parse by regex
            m = SYM_RE.match(line)
            if not m:
                continue
            typ, bind, ndx, name = m.group(1), m.group(2), m.group(3), strip_ver(m.group(4))
            if not name or typ in ("FILE", "SECTION") or bind == "LOCAL":
                continue
            if ndx == "UND":
                if bind != "WEAK":
                    und.add(name)
            else:
                defined.add(name)
        return needed, und, defined, odd


def extract_apex(tools, archive, dest, tmp):
    """Extract an .apex/.capex payload filesystem into dest. -> error string or None"""
    try:
        z = zipfile.ZipFile(archive)
    except (OSError, zipfile.BadZipFile) as e:
        return f"bad zip: {e}"
    with z:
        names = z.namelist()
        if "original_apex" in names:  # compressed apex
            inner = Path(tempfile.mkdtemp(dir=tmp)) / "original.apex"
            with z.open("original_apex") as s, open(inner, "wb") as d:
                shutil.copyfileobj(s, d)
            err = extract_apex(tools, inner, dest, tmp)
            inner.unlink(missing_ok=True)
            return err
        if "apex_payload.img" not in names:
            return "no apex_payload.img"
        img = Path(tempfile.mkdtemp(dir=tmp)) / "apex_payload.img"
        with z.open("apex_payload.img") as s, open(img, "wb") as d:
            shutil.copyfileobj(s, d)
    dest.mkdir(parents=True, exist_ok=True)
    err = None
    with open(img, "rb") as f:
        f.seek(1024)
        sb = f.read(0x40)
    if len(sb) > 0x3a and struct.unpack_from("<H", sb, 0x38)[0] == 0xEF53:
        if not tools.debugfs:
            err = "ext4 payload but debugfs missing"
        else:
            subprocess.run([tools.debugfs, "-R", f"rdump / {dest}", str(img)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        if not tools.fsck_erofs:
            err = "non-ext4 (erofs?) payload but fsck.erofs missing"
        else:
            subprocess.run([tools.fsck_erofs, f"--extract={dest}", "--no-preserve",
                            str(img)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    img.unlink(missing_ok=True)
    if err is None and not (dest / "apex_manifest.pb").exists():
        err = "payload extraction produced no apex_manifest.pb"
    return err


def find_apex(root, name):
    for base in ("system/system/apex", "system/apex", "system/system/system_ext/apex",
                 "system_ext/apex"):
        for ext in (".apex", ".capex"):
            p = root / base / (name + ext)
            if p.is_file():
                return p
    return None


def all_apexes(root):
    out = []
    for base in ("system/system/apex", "system/apex", "system/system/system_ext/apex",
                 "system_ext/apex", "product/apex"):
        d = root / base
        if d.is_dir():
            out += sorted(p for p in d.iterdir() if p.suffix in (".apex", ".capex"))
    return out


def iter_elf64(root, skip=()):
    for dirpath, dirnames, filenames in os.walk(root):
        dp = Path(dirpath)
        dirnames[:] = [d for d in dirnames if (dp / d) not in skip]
        for fn in filenames:
            p = dp / fn
            if not p.is_symlink() and is_elf64(p):
                yield p


def exports_by_basename(tools, root):
    out = {}
    for p in iter_elf64(root):
        if p.suffix == ".so" or ".so." in p.name:
            out.setdefault(p.name, set()).update(tools.elf(p)[2])
    return out


DROPINS = (
    "system/system/lib64/libvkjni.so",
    "system/system/lib64/libvkmanager.so",
    "system/system/lib64/vendor.samsung.hardware.security.vaultkeeper@2.0.so",
    "system/system/lib64/lib.engmode.samsung.so",
    "system/system/lib64/lib.engmodejni.samsung.so",
    "system/system/lib64/vendor.samsung.hardware.security.engmode@1.0.so",
)


def split_check(a, tools):
    """Split runtime: the donor keeps its own runtime/i18n APEX, the 32-bit
    layer is a closed API 36 set. Only API 36 64-bit libraries dropped into
    the API 37 system (stock_blobs security JNI) must link against the donor."""
    tmp = Path(tempfile.mkdtemp(prefix="crew-abi-", dir=os.environ.get("CREW_ABI_TMP")))
    bad, notes = [], []
    try:
        index = {}
        for base in (a.donor / "system/system/lib64", a.donor / "system/system/system_ext/lib64",
                     a.donor / "system_ext/lib64"):
            if base.is_dir():
                for p in iter_elf64(base):
                    index.setdefault(p.name, []).append(p)
        napex = 0
        for arc in all_apexes(a.donor):
            dest = tmp / arc.name
            if extract_apex(tools, arc, dest, tmp) is None:
                napex += 1
                for p in iter_elf64(dest):
                    if "hwasan" not in str(p) and (p.suffix == ".so" or ".so." in p.name):
                        index.setdefault(p.name, []).append(p)
        drop = {Path(r).name: a.multilib / r for r in DROPINS if (a.multilib / r).is_file()}
        notes.append(f"donor index: {len(index)} sonames ({napex} apex payloads); "
                     f"drop-ins present: {len(drop)}/{len(DROPINS)}")
        cache = {}
        def exp(p):
            if p not in cache:
                cache[p] = tools.elf(p)[2]
            return cache[p]
        for name, p in sorted(drop.items()):
            needed, und, own, _o = tools.elf(p)
            avail, missing_libs = set(own), []
            for n in needed:
                if n in drop:
                    avail |= exp(drop[n])
                elif n in index:
                    for q in index[n]:
                        avail |= exp(q)
                else:
                    missing_libs.append(n)
            miss = sorted(s for s in und if s not in avail)
            if missing_libs or miss:
                bad.append(f"{name}: libs={missing_libs} syms({len(miss)})={miss[:10]}")
    finally:
        if not a.keep_tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"crew split-runtime drop-in ABI check: {'PASS' if not bad else 'FAIL'}")
    for n in notes:
        print("  " + n)
    for b in bad:
        print("  [drop-in] " + b)
    return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("donor", type=Path)
    ap.add_argument("multilib", type=Path)
    ap.add_argument("--tools-bin", action="append", default=[])
    ap.add_argument("--json", type=Path)
    ap.add_argument("--keep-tmp", action="store_true")
    ap.add_argument("--jobs", type=int, default=max(2, (os.cpu_count() or 4) // 2))
    ap.add_argument("--split", action="store_true",
                    help="donor runtime/i18n APEX stays; only check 64-bit multilib drop-ins")
    a = ap.parse_args()
    tools = Tools(a.tools_bin)
    if a.split:
        return split_check(a, tools)
    tmp = Path(tempfile.mkdtemp(prefix="crew-abi-", dir=os.environ.get("CREW_ABI_TMP")))
    rep = {"ok": False, "notes": [], "missing_libs": {}, "missing_symbols": {},
           "reverse_missing": {}, "odd_dynamic_tags": {}, "apex_errors": {}}
    try:
        prov = {}
        for side, root in (("donor", a.donor), ("multilib", a.multilib)):
            for apx in (RUNTIME, I18N):
                arc = find_apex(root, apx)
                if not arc:
                    rep["apex_errors"][f"{side}:{apx}"] = "apex not found"
                    continue
                dest = tmp / side / apx
                err = extract_apex(tools, arc, dest, tmp)
                if err:
                    rep["apex_errors"][f"{side}:{apx}"] = err
                    continue
                prov[(side, apx)] = (dest, exports_by_basename(tools, dest))
        need = [(s, x) for s in ("donor", "multilib") for x in (RUNTIME, I18N)]
        if any(k not in prov for k in need):
            print(json.dumps(rep["apex_errors"], indent=2))
            return 2

        donor_exp, cand_exp = {}, {}
        for apx in (RUNTIME, I18N):
            for k, v in prov[("donor", apx)][1].items():
                donor_exp.setdefault(k, set()).update(v)
            for k, v in prov[("multilib", apx)][1].items():
                cand_exp.setdefault(k, set()).update(v)
        rep["notes"].append(f"donor runtime+i18n provide {len(donor_exp)} libs, "
                            f"multilib copy provides {len(cand_exp)}")

        # consumers: donor partitions that stay + every other donor apex payload
        roots = []
        for part in ("system", "system_ext", "product", "odm"):
            p = a.donor / part
            if p.is_dir():
                roots.append(p)
        skip_dirs = {a.donor / "system/system/apex", a.donor / "system/apex"}
        consumers = []
        for r in roots:
            consumers += list(iter_elf64(r, skip=skip_dirs))
        apex_count = 0
        for arc in all_apexes(a.donor):
            stem = arc.name.rsplit(".", 1)[0]
            if stem in (RUNTIME, I18N):
                continue
            dest = tmp / "donor_apex" / stem
            err = extract_apex(tools, arc, dest, tmp)
            if err:
                rep["apex_errors"][f"donor:{stem}"] = err
                continue
            apex_count += 1
            consumers += list(iter_elf64(dest))
        rep["notes"].append(f"scanned {len(consumers)} donor ELF64 files "
                            f"({apex_count} extra apex payloads)")

        def check(p):
            needed, und, _d, odd = tools.elf(p)
            res = []
            for n in needed:
                if n not in donor_exp:
                    continue
                if n not in cand_exp:
                    res.append(("lib", n, None))
                    continue
                for s in und:
                    if s in donor_exp[n] and s not in cand_exp[n]:
                        if not any(s in cand_exp.get(o, ()) for o in needed if o != n):
                            res.append(("sym", n, s))
            return p, res, odd

        with ThreadPoolExecutor(a.jobs) as ex:
            for p, res, odd in ex.map(check, consumers):
                rel = str(p.relative_to(tmp) if str(p).startswith(str(tmp)) else
                          p.relative_to(a.donor))
                for kind, lib, sym in res:
                    if kind == "lib":
                        rep["missing_libs"].setdefault(lib, []).append(rel)
                    else:
                        d = rep["missing_symbols"].setdefault(lib, {})
                        d.setdefault(sym, []).append(rel)
                for t in odd:
                    rep["odd_dynamic_tags"].setdefault(t, []).append(rel)

        # reverse: multilib apex libs importing from donor libs outside the apex
        # (system/system_ext lib64 + every other donor apex payload, e.g. ART's
        # libnativehelper), resolved by symbol, not just by file presence
        donor_index = {}
        for base in (a.donor / "system/system/lib64", a.donor / "system/system/system_ext/lib64",
                     a.donor / "system_ext/lib64", tmp / "donor_apex"):
            if base.is_dir():
                for p in iter_elf64(base):
                    if p.suffix == ".so" or ".so." in p.name:
                        donor_index.setdefault(p.name, []).append(p)
        exp_cache = {}
        def exports_of(p):
            if p not in exp_cache:
                exp_cache[p] = tools.elf(p)[2]
            return exp_cache[p]
        for apx in (RUNTIME, I18N):
            dest = prov[("multilib", apx)][0]
            inside = prov[("multilib", apx)][1]
            for p in iter_elf64(dest):
                if "hwasan" in str(p.relative_to(dest)):
                    continue  # hwasan variants are never loaded on user builds
                needed, und, own, _o = tools.elf(p)
                avail = set(own)
                origin = []
                for n in needed:
                    if n in inside:
                        avail |= inside[n]
                    elif n in cand_exp:
                        avail |= cand_exp[n]
                    elif n in donor_index:
                        for q in donor_index[n]:
                            avail |= exports_of(q)
                        origin.append(f"{n}<-A17:" + ",".join(
                            str(q.relative_to(tmp) if str(q).startswith(str(tmp))
                                else q.relative_to(a.donor)) for q in donor_index[n][:2]))
                    else:
                        rep["reverse_missing"].setdefault(n, []).append(
                            f"{apx}:{p.relative_to(dest)} needs missing lib")
                miss = sorted(s for s in und if s not in avail)
                if miss:
                    rep["reverse_missing"].setdefault(
                        f"{apx}:{p.relative_to(dest)}", []).append(
                        f"{len(miss)} unresolved: {', '.join(miss[:12])}"
                        + (f" | from donor: {'; '.join(origin)}" if origin else ""))
        rep["ok"] = not (rep["missing_libs"] or rep["missing_symbols"]
                         or rep["reverse_missing"] or rep["odd_dynamic_tags"])
    finally:
        if not a.keep_tmp:
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"crew runtime ABI check: {'PASS' if rep['ok'] else 'FAIL'}")
    for n in rep["notes"]:
        print("  " + n)
    for k, v in rep["apex_errors"].items():
        print(f"  [apex] {k}: {v}")
    for lib, users in sorted(rep["missing_libs"].items()):
        print(f"  [lib-missing] {lib} needed by {len(users)}: {', '.join(users[:4])}")
    for lib, syms in sorted(rep["missing_symbols"].items()):
        users = sorted({u for us in syms.values() for u in us})
        print(f"  [sym-missing] {lib}: {len(syms)} symbols, {len(users)} consumers")
        print(f"      symbols: {', '.join(sorted(syms)[:20])}")
        print(f"      e.g.   : {', '.join(users[:6])}")
    for lib, users in sorted(rep["reverse_missing"].items()):
        print(f"  [reverse] {lib}: {users[:3]}")
    for t, users in sorted(rep["odd_dynamic_tags"].items()):
        print(f"  [dyn-tag] {t} in {len(users)} files, e.g. {users[:3]}")
    if a.json:
        rep_json = dict(rep)
        rep_json["missing_symbols"] = {l: {s: u[:20] for s, u in d.items()}
                                       for l, d in rep["missing_symbols"].items()}
        a.json.write_text(json.dumps(rep_json, indent=1, sort_keys=True))
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
