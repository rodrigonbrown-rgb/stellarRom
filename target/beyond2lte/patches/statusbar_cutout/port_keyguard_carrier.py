#!/usr/bin/env python3
# beyond2lte: lockscreen carrier text ("Solo llamadas de emergencia") squeezed and
# marquee-scrolling with faded edges on the right punch-hole S10+.
# 1) IndicatorGardenAlgorithm{NoCutout,SidelingCenterCutout}.calculateLeftContainerMaxWidth:
#    with the top cutout in the right half (LTR, no visible center container), the left
#    container may use everything up to the right icons:
#    cutout.left - cutoutSidePaddingD - leftPadding - defaultSidePadding - rightContainer
#    (never below getEssentialLeftWidth). Center/no-cutout/landscape keep stock values.
# 2) CarrierText.onVisibilityChanged: END ellipsis instead of MARQUEE (no scrolling/fade).
# usage: port_keyguard_carrier.py <decoded SystemUI.apk dir> <dex mark file (merged)>
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PH = "com/android/systemui/statusbar/phone"
ALGO = f"L{PH}/IndicatorGardenAlgorithm;"
PROPS = f"L{PH}/IndicatorGardenInputProperties;"
GARDEN = f"L{PH}/IndicatorGarden;"
CONT = f"L{PH}/IndicatorGardenContainer;"
TAG = "crew_lw"
SIG = f"calculateLeftContainerMaxWidth({GARDEN})I"


def die(msg):
    print(f"  ! {msg}")
    sys.exit(2)


def find(root, rel):
    hits = sorted(root.glob(f"smali*/{rel}.smali"))
    return hits[0] if len(hits) == 1 else None


def patch_algo(path):
    text = path.read_text(encoding="utf-8")
    if f":{TAG}_tail" in text:
        print(f"  = {path.stem} (already patched)")
        return True
    m = re.search(r"^\.method [^\n]*" + re.escape(SIG) + r"\n(?P<body>.*?)^\.end method$", text, re.M | re.S)
    if not m:
        print(f"  - {path.stem}: no {SIG}")
        return False
    body = m.group("body")
    lm = re.search(r"^(\s*)\.locals (\d+)$", body, re.M)
    if not lm:
        print(f"  - {path.stem}: no .locals")
        return False
    n = int(lm.group(2))
    if n > 9:
        print(f"  - {path.stem}: .locals {n} too high")
        return False
    V, P, T, U, W, S, X = (f"v{n + i}" for i in range(7))
    rets = 0

    def repl(mm):
        nonlocal rets
        rets += 1
        return f"{mm.group(1)}move/from16 {V}, {mm.group(2)}\n\n{mm.group(1)}goto :{TAG}_tail"

    nb = re.sub(r"^(\s*)return ([vp]\d+)\s*$", repl, body, flags=re.M)
    if not rets:
        print(f"  - {path.stem}: no int return")
        return False
    i = "    "
    nb = nb.replace(lm.group(0), f"{lm.group(1)}.locals {n + 7}\n\n"
                    f"{i}move-object/from16 {S}, p0\n\n{i}move-object/from16 {X}, p1", 1)
    tail = f"""
{i}:{TAG}_tail
{i}if-eqz {X}, :{TAG}_ret

{i}iget-object {P}, {S}, {ALGO}->inputProperties:{PROPS}

{i}if-eqz {P}, :{TAG}_ret

{i}invoke-virtual {{{P}}}, {PROPS}->isRTL()Z

{i}move-result {U}

{i}if-nez {U}, :{TAG}_ret

{i}invoke-interface {{{X}}}, {GARDEN}->getCenterContainer(){CONT}

{i}move-result-object {T}

{i}if-eqz {T}, :{TAG}_nc

{i}invoke-interface {{{T}}}, {CONT}->isGardenVisible()Z

{i}move-result {U}

{i}if-nez {U}, :{TAG}_ret

{i}:{TAG}_nc
{i}iget-object {T}, {P}, {PROPS}->displayCutout:Landroid/view/DisplayCutout;

{i}if-eqz {T}, :{TAG}_ret

{i}invoke-virtual {{{T}}}, Landroid/view/DisplayCutout;->getBoundingRectTop()Landroid/graphics/Rect;

{i}move-result-object {T}

{i}if-eqz {T}, :{TAG}_ret

{i}invoke-virtual {{{T}}}, Landroid/graphics/Rect;->isEmpty()Z

{i}move-result {U}

{i}if-nez {U}, :{TAG}_ret

{i}iget {T}, {T}, Landroid/graphics/Rect;->left:I

{i}iget {U}, {P}, {PROPS}->statusBarWidth:I

{i}mul-int/lit8 {W}, {T}, 0x2

{i}if-le {W}, {U}, :{TAG}_ret

{i}iget {W}, {P}, {PROPS}->cutoutSidePaddingD:I

{i}sub-int/2addr {T}, {W}

{i}invoke-virtual {{{S}}}, {ALGO}->calculateLeftPadding()I

{i}move-result {W}

{i}sub-int/2addr {T}, {W}

{i}invoke-virtual {{{S}}}, {ALGO}->getDefaultSidePadding()I

{i}move-result {W}

{i}sub-int/2addr {T}, {W}

{i}invoke-interface {{{X}}}, {GARDEN}->getRightContainer(){CONT}

{i}move-result-object {U}

{i}if-eqz {U}, :{TAG}_nr

{i}invoke-interface {{{U}}}, {CONT}->getGardenWidth()I

{i}move-result {W}

{i}sub-int/2addr {T}, {W}

{i}:{TAG}_nr
{i}invoke-interface {{{X}}}, {GARDEN}->getEssentialLeftWidth()I

{i}move-result {W}

{i}invoke-static {{{T}, {W}}}, Ljava/lang/Math;->max(II)I

{i}move-result {V}

{i}:{TAG}_ret
{i}return {V}
"""
    nb = nb.rstrip("\n") + "\n" + tail
    text = text[:m.start("body")] + nb + text[m.end("body"):]
    shutil.copy2(path, str(path) + ".crew_bak")
    path.write_text(text, encoding="utf-8")
    print(f"  + {path.stem}.calculateLeftContainerMaxWidth ({rets} return(s))")
    return True


def patch_carrier(path):
    # Keep the MARQUEE field reference (dex inventory forbids removing it) and
    # override it right away with END: same register, no scrolling, no fade.
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^\.method [^\n]*onVisibilityChanged\(Landroid/view/View;I\)V\n(?P<body>.*?)^\.end method$", text, re.M | re.S)
    if not m:
        print("  - CarrierText.onVisibilityChanged not found, kept")
        return False
    body = m.group("body")
    MQ = "    sget-object p1, Landroid/text/TextUtils$TruncateAt;->MARQUEE:Landroid/text/TextUtils$TruncateAt;\n"
    EN = ("\n    # crew: carrier ellipsis instead of marquee (no scrolling / faded edges)\n"
          "    sget-object p1, Landroid/text/TextUtils$TruncateAt;->END:Landroid/text/TextUtils$TruncateAt;\n")
    if "# crew: carrier ellipsis" in body:
        if body.count("TruncateAt;->MARQUEE") == 1:
            print("  = CarrierText (already patched)")
            return True
        # repair the earlier variant that dropped the MARQUEE reference
        body = body.replace("    # crew: carrier ellipsis instead of marquee (no scrolling / faded edges)\n",
                            MQ + "\n    # crew: carrier ellipsis instead of marquee (no scrolling / faded edges)\n", 1)
        if body.count("TruncateAt;->MARQUEE") != 1:
            print("  - CarrierText: could not repair earlier patch, kept")
            return False
        msg = "  + CarrierText.onVisibilityChanged: repaired (MARQUEE reference kept)"
    else:
        if body.count(MQ) != 1:
            print("  - CarrierText.onVisibilityChanged: MARQUEE not found, kept")
            return False
        body = body.replace(MQ, MQ + EN, 1)
        msg = "  + CarrierText.onVisibilityChanged: END ellipsis (MARQUEE reference kept)"
    shutil.copy2(path, str(path) + ".crew_bak")
    path.write_text(text[:m.start("body")] + body + text[m.end("body"):], encoding="utf-8")
    print(msg)
    return True


def main():
    root, mark = Path(sys.argv[1]), Path(sys.argv[2])
    files = []
    for cls in ("IndicatorGardenAlgorithmNoCutout", "IndicatorGardenAlgorithmSidelingCenterCutout"):
        p = find(root, f"{PH}/{cls}")
        if p and patch_algo(p):
            files.append(p)
    if not files:
        die("no IndicatorGardenAlgorithm left-width method patched")
    c = find(root, "com/android/keyguard/CarrierText")
    if c and patch_carrier(c):
        files.append(c)
    edited = [f for f in files if Path(str(f) + ".crew_bak").exists()]
    if edited and shutil.which("smali"):
        with tempfile.TemporaryDirectory() as tmp:
            r = subprocess.run(["smali", "a", "-a", "34", "-o", f"{tmp}/t.dex"] + [str(f) for f in edited],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if r.returncode != 0:
                for f in edited:
                    shutil.move(str(f) + ".crew_bak", str(f))
                die("smali check failed, reverted:\n" + r.stdout[-3000:])
    for f in edited:
        Path(str(f) + ".crew_bak").unlink()
    dexes = set(mark.read_text().split()) if mark.exists() else set()
    dexes |= {f.relative_to(root).parts[0] for f in files}
    mark.write_text("".join(d + "\n" for d in sorted(dexes)), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
