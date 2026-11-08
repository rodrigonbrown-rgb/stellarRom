#!/usr/bin/env python3
# beyond2lte: push status bar right icons (battery, wifi, signal...) left of the
# top-right punch hole. One UI 8.5 SystemUI dropped the right-cutout garden
# algorithm, so every IndicatorGardenAlgorithm*.calculateRightPadding() gets a
# tail: if the top cutout rect sits in the right half of the screen, right
# padding = max(stock, distance(cutout.left -> right edge) + gap).
# Center/no-cutout devices and landscape (empty top rect) keep stock values.
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PKG = "com/android/systemui/statusbar/phone"
BASE = f"L{PKG}/IndicatorGardenAlgorithm;"
PROPS = f"L{PKG}/IndicatorGardenInputProperties;"
TAG = "crew_rc"


def die(msg):
    print(f"  ! {msg}")
    sys.exit(2)


def parse(path):
    text = path.read_text(encoding="utf-8")
    cls = re.search(r"^\.class [^\n]*?(L[^\s;]+;)$", text, re.M).group(1)
    sup = re.search(r"^\.super (L[^\s;]+;)$", text, re.M)
    fields = {}
    for m in re.finditer(r"^\.field (?P<flags>[^\n]*?)(?P<name>[\w$]+):(?P<type>\S+)", text, re.M):
        fields[m.group("name")] = (m.group("flags"), m.group("type"))
    return {"path": path, "text": text, "cls": cls,
            "super": sup.group(1) if sup else None, "fields": fields}


def main():
    root = Path(sys.argv[1])
    out_list = Path(sys.argv[2])
    smali_dirs = sorted(d for d in root.iterdir() if d.is_dir() and d.name.startswith("smali"))
    if not smali_dirs:
        die(f"no smali dirs in {root}")

    idx = {}
    for d in smali_dirs:
        p = d / PKG
        if p.is_dir():
            for f in p.glob("*.smali"):
                info = parse(f)
                info["dex"] = d.name
                idx[info["cls"]] = info

    if BASE not in idx:
        die("IndicatorGardenAlgorithm not found (SystemUI layout changed)")
    if PROPS not in idx:
        die("IndicatorGardenInputProperties not found")

    props = idx[PROPS]
    dc_field = next((n for n, (fl, t) in props["fields"].items()
                     if t == "Landroid/view/DisplayCutout;" and "static" not in fl and "private" not in fl), None)
    if not dc_field:
        die("no accessible DisplayCutout field in IndicatorGardenInputProperties: "
            + ", ".join(f"{n}:{t}" for n, (fl, t) in props["fields"].items()))
    gap_field = None
    fl = props["fields"].get("cutoutSidePaddingD")
    if fl and fl[1] == "I" and "private" not in fl[0] and "static" not in fl[0]:
        gap_field = "cutoutSidePaddingD"

    def chain(cls):
        seen = []
        while cls in idx and cls not in seen:
            seen.append(cls)
            if cls == BASE:
                return seen
            cls = idx[cls]["super"]
        return None

    def props_holder(ch):
        for c in ch:
            for n, (fl, t) in idx[c]["fields"].items():
                if t == PROPS and "static" not in fl:
                    if c != ch[0] and "private" in fl:
                        continue
                    return c, n
        return None

    targets = []
    for cls, info in idx.items():
        ch = chain(cls)
        if not ch:
            continue
        m = re.search(r"^\.method [^\n]*calculateRightPadding\(\)I$", info["text"], re.M)
        if not m or "abstract" in m.group(0):
            continue
        holder = props_holder(ch)
        if not holder:
            print(f"  - skip {cls}: no IndicatorGardenInputProperties field in chain")
            continue
        targets.append((info, holder))

    if not targets:
        base_methods = re.findall(r"^\.method ([^\n]+)$", idx[BASE]["text"], re.M)
        die("no concrete calculateRightPadding()I found. Base methods:\n      "
            + "\n      ".join(base_methods))

    changed = []
    already = False
    for info, (decl, fname) in targets:
        text = info["text"]
        if f":{TAG}_tail" in text:
            already = True
            changed.append(info)
            print(f"  = {info['cls']} (already patched)")
            continue
        m = re.search(r"^\.method [^\n]*calculateRightPadding\(\)I\n(?P<body>.*?)^\.end method$",
                      text, re.M | re.S)
        body = m.group("body")
        lm = re.search(r"^(\s*)\.locals (\d+)$", body, re.M)
        if not lm:
            print(f"  - skip {info['cls']}: no .locals")
            continue
        n = int(lm.group(2))
        if n > 9:
            print(f"  - skip {info['cls']}: .locals {n} too high for 4-bit regs")
            continue
        # R8 reuses p0 for results (move-result p0), so pin `this` in S first.
        V, P, T, U, W, S = (f"v{n + i}" for i in range(6))
        ind = "    "
        rets = 0

        def repl(mm):
            nonlocal rets
            rets += 1
            return f"{mm.group(1)}move/from16 {V}, {mm.group(2)}\n\n{mm.group(1)}goto :{TAG}_tail"

        new_body = re.sub(r"^(\s*)return ([vp]\d+)\s*$", repl, body, flags=re.M)
        if not rets:
            print(f"  - skip {info['cls']}: no int return")
            continue
        new_body = new_body.replace(
            lm.group(0), f"{lm.group(1)}.locals {n + 6}\n\n{lm.group(1)}move-object/from16 {S}, p0", 1)
        gap = (f"{ind}iget {W}, {P}, {PROPS}->{gap_field}:I" if gap_field
               else f"{ind}move {W}, {V}")
        tail = f"""
{ind}:{TAG}_tail
{ind}iget-object {P}, {S}, {decl}->{fname}:{PROPS}

{ind}if-eqz {P}, :{TAG}_ret

{ind}iget-object {T}, {P}, {PROPS}->{dc_field}:Landroid/view/DisplayCutout;

{ind}if-eqz {T}, :{TAG}_ret

{ind}invoke-virtual {{{T}}}, Landroid/view/DisplayCutout;->getBoundingRectTop()Landroid/graphics/Rect;

{ind}move-result-object {T}

{ind}if-eqz {T}, :{TAG}_ret

{ind}invoke-virtual {{{T}}}, Landroid/graphics/Rect;->isEmpty()Z

{ind}move-result {U}

{ind}if-nez {U}, :{TAG}_ret

{ind}iget {T}, {T}, Landroid/graphics/Rect;->left:I

{ind}invoke-static {{}}, Landroid/content/res/Resources;->getSystem()Landroid/content/res/Resources;

{ind}move-result-object {U}

{ind}invoke-virtual {{{U}}}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;

{ind}move-result-object {U}

{ind}iget {U}, {U}, Landroid/util/DisplayMetrics;->widthPixels:I

{ind}mul-int/lit8 {W}, {T}, 0x2

{ind}if-le {W}, {U}, :{TAG}_ret

{ind}sub-int/2addr {U}, {T}

{ind}if-lez {U}, :{TAG}_ret

{gap}

{ind}add-int/2addr {U}, {W}

{ind}invoke-static {{{V}, {U}}}, Ljava/lang/Math;->max(II)I

{ind}move-result {V}

{ind}:{TAG}_ret
{ind}return {V}
"""
        new_body = new_body.rstrip("\n") + "\n" + tail
        text = text[:m.start("body")] + new_body + text[m.end("body"):]
        shutil.copy2(info["path"], str(info["path"]) + ".crew_bak")
        info["path"].write_text(text, encoding="utf-8")
        info["text"] = text
        changed.append(info)
        print(f"  + {info['cls']} ({info['dex']}, {rets} return(s), props={decl}->{fname}, "
              f"cutout={dc_field}, gap={gap_field or 'stock padding'})")

    if not changed:
        die("nothing patched")

    # Syntax/register check of just the edited classes.
    if not already and shutil.which("smali"):
        with tempfile.TemporaryDirectory() as tmp:
            cmd = ["smali", "a", "-a", "34", "-o", f"{tmp}/t.dex"] + [str(i["path"]) for i in changed]
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if r.returncode != 0:
                for i in changed:
                    bak = Path(str(i["path"]) + ".crew_bak")
                    if bak.exists():
                        shutil.move(str(bak), str(i["path"]))
                die("smali check failed, reverted:\n" + r.stdout[-3000:])
    for i in changed:
        bak = Path(str(i["path"]) + ".crew_bak")
        if bak.exists():
            bak.unlink()

    out_list.write_text("".join(sorted({i["dex"] + "\n" for i in changed})), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
