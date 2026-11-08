#!/usr/bin/env python3
# crew: enable the One UI screen-resolution switch (WQHD+/FHD+/HD+) in a SecSettings
# built for an FHD donor. The UI, entries and getScreenResolution() are intact in the
# donor; only availability and the setter are compiled out. Edits are by method,
# use only references already present in the same dex, and are idempotent.
# usage: crew_resolution_smali.py <decoded SecSettings dir>
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
CTRL = "com/samsung/android/settings/display/controller"
MARK = "# crew-resolution"

def one(rel):
    hits = list(root.glob(f"smali*/{rel}.smali"))
    if len(hits) != 1:
        sys.exit(f"{rel}: {len(hits)} candidates")
    return hits[0]

def method(s, sig):
    m = re.search(r"^\.method public " + re.escape(sig) + r"\n.*?^\.end method\n", s, re.M | re.S)
    if not m:
        sys.exit(f"method not found: {sig}")
    return m

AVAIL = """.method public getAvailabilityStatus()I
    .locals 0

    # crew-resolution: AVAILABLE (QHD panel, see SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL)
    const/4 p0, 0x0

    return p0
.end method
"""

SETTER = """.method public setSelectedValue(Ljava/lang/String;)Z
    .locals 12

    # crew-resolution: 2=WQHD+ 1=FHD+ 0=HD+ via forced display size, density
    # scaled from the current one so the screen zoom level is kept
    :try_start_crew
    invoke-static {p1}, Ljava/lang/Integer;->parseInt(Ljava/lang/String;)I

    move-result v0

    const/16 v1, 0x5a0

    const/4 v2, 0x2

    if-eq v0, v2, :crew_w

    const/16 v1, 0x438

    const/4 v2, 0x1

    if-eq v0, v2, :crew_w

    const/16 v1, 0x2d0

    :crew_w
    invoke-static {}, Landroid/view/WindowManagerGlobal;->getWindowManagerService()Landroid/view/IWindowManager;

    move-result-object v5

    new-instance v2, Landroid/graphics/Point;

    invoke-direct {v2}, Landroid/graphics/Point;-><init>()V

    const/4 v6, 0x0

    invoke-interface {v5, v6, v2}, Landroid/view/IWindowManager;->getInitialDisplaySize(ILandroid/graphics/Point;)V

    iget v3, v2, Landroid/graphics/Point;->x:I

    iget v8, v2, Landroid/graphics/Point;->y:I

    if-lez v3, :crew_fail

    move v10, v3

    iget-object v4, p0, Lcom/android/settingslib/core/AbstractPreferenceController;->mContext:Landroid/content/Context;

    invoke-virtual {v4}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v7

    const-string v9, "display_size_forced"

    invoke-static {v7, v9}, Landroid/provider/Settings$Global;->getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v7

    if-eqz v7, :crew_cur

    const-string v9, ","

    invoke-virtual {v7, v9}, Ljava/lang/String;->split(Ljava/lang/String;)[Ljava/lang/String;

    move-result-object v7

    array-length v9, v7

    const/4 v11, 0x2

    if-lt v9, v11, :crew_cur

    aget-object v7, v7, v6

    invoke-static {v7}, Ljava/lang/Integer;->parseInt(Ljava/lang/String;)I

    move-result v9

    if-lez v9, :crew_cur

    move v10, v9

    :crew_cur
    invoke-static {v4}, Lcom/samsung/android/settings/display/SecDisplayUtils;->getCurrentDensity(Landroid/content/Context;)I

    move-result v9

    if-gtz v9, :crew_d

    invoke-interface {v5, v6}, Landroid/view/IWindowManager;->getInitialDisplayDensity(I)I

    move-result v9

    move v10, v3

    :crew_d
    mul-int/2addr v8, v1

    div-int/2addr v8, v3

    mul-int/2addr v9, v1

    div-int/2addr v9, v10

    move v7, v1

    const/4 v10, 0x1

    const/4 v11, -0x1

    invoke-interface/range {v5 .. v11}, Landroid/view/IWindowManager;->setForcedDisplaySizeDensity(IIIIZI)V
    :try_end_crew
    .catchall {:try_start_crew .. :try_end_crew} :crew_fail

    const/4 v0, 0x1

    return v0

    :crew_fail
    const/4 v0, 0x0

    return v0
.end method
"""

changed = []
for cls, edits in (
    (f"{CTRL}/ScreenResolutionPreferenceController", [("getAvailabilityStatus()I", AVAIL)]),
    (f"{CTRL}/SecScreenResolutionSingleChoiceController",
     [("getAvailabilityStatus()I", AVAIL), ("setSelectedValue(Ljava/lang/String;)Z", SETTER)]),
):
    f = one(cls)
    s = f.read_text()
    for sig, new in edits:
        m = method(s, sig)
        if MARK in m.group(0):
            continue
        body = m.group(0)
        if sig.startswith("getAvailabilityStatus") and not re.search(r"const/4 p0, 0x3\n", body):
            sys.exit(f"{cls}.{sig}: unexpected body (not the compiled-out stub)")
        if sig.startswith("setSelectedValue") and "getSelectedValue()" not in body:
            sys.exit(f"{cls}.{sig}: unexpected body (not the compiled-out stub)")
        s = s[:m.start()] + new + s[m.end():]
        changed.append(f"{cls.rsplit('/', 1)[1]}.{sig.split('(')[0]}")
    f.write_text(s)


# --- ScreenResolutionFragment: the FHD build removes the radio preference instead
# of preselecting the current resolution (ExtremeROM restores setValue here), so
# the radio has no value and "Apply" parses null. Preselect it.
DISP = "com/samsung/android/settings/display"
frag = one(f"{DISP}/ScreenResolutionFragment")
fs = frag.read_text()
if MARK + " radio" not in fs:
    m = method(fs, "final onCreate(Landroid/os/Bundle;)V")
    body = m.group(0)
    rx = re.compile(
        r"(?P<keep>    sget-object v\d+, Lcom/samsung/android/settings/Rune;->COMMON_CONFIG_PACKAGE_NAME_SMART_MANAGER:Ljava/lang/String;\n"
        r"(?:[ \t]*(?:\.line \d+)?\n)*)"
        r"    invoke-virtual \{p0, [pv]\d+\}, Lcom/android/settings/SettingsPreferenceFragment;->removePreference\(Ljava/lang/String;\)Z\n")
    hits = list(rx.finditer(body))
    if len(hits) != 1 or "screen_resolution_seekbar" not in body[:hits[0].start()] if hits else True:
        sys.exit(f"ScreenResolutionFragment.onCreate: {len(hits)} removePreference stub(s)")
    loc = re.search(r"^    \.locals (\d+)$", body, re.M)
    if not loc or int(loc.group(1)) < 3:
        sys.exit("ScreenResolutionFragment.onCreate: unexpected .locals")
    rp = list(root.glob("smali*/com/samsung/android/settings/widget/SecHorizontalRadioPreference.smali"))
    rps = rp[0].read_text() if len(rp) == 1 else ""
    R = "Lcom/samsung/android/settings/widget/SecHorizontalRadioPreference;"
    if re.search(r"^\.method public (?:final )?setValue\(Ljava/lang/String;\)V$", rps, re.M):
        setcall = f"    invoke-virtual {{v1, v2}}, {R}->setValue(Ljava/lang/String;)V\n"
    else:
        ml = list(root.glob("smali*/androidx/lifecycle/MutableLiveData.smali"))
        if not ml or not re.search(r"^\.method public (?:final )?setValue\(Ljava/lang/Object;\)V$", ml[0].read_text(), re.M):
            sys.exit("no way to set SecHorizontalRadioPreference value (setValue / MutableLiveData.setValue missing)")
        setcall = (f"    iget-object v1, v1, {R}->mCurrentValue:Landroidx/lifecycle/MutableLiveData;\n\n"
                   "    if-eqz v1, :crew_srb\n\n"
                   "    invoke-virtual {v1, v2}, Landroidx/lifecycle/MutableLiveData;->setValue(Ljava/lang/Object;)V\n")
    new = (hits[0].group("keep") +
           f"    {MARK} radio: keep it and preselect the current resolution\n"
           f"    iget-object v1, p0, Lcom/samsung/android/settings/display/ScreenResolutionFragment;->mScreenResolutionButton:{R}\n\n"
           "    if-eqz v1, :crew_srb\n\n"
           "    iget v2, p0, Lcom/samsung/android/settings/display/ScreenResolutionFragment;->mScreenResolution:I\n\n"
           "    invoke-static {v2}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;\n\n"
           "    move-result-object v2\n\n" + setcall + "\n    :crew_srb\n")
    body = body[:hits[0].start()] + new + body[hits[0].end():]
    fs = fs[:m.start()] + body + fs[m.end():]
    frag.write_text(fs)
    changed.append("ScreenResolutionFragment.onCreate(radio)")

# --- SecDisplayUtils.setDisplayMode: real multi-mode panels only. The S10+ panel
# exposes a single mode, so the FHD/HD widths stay 0 and this would only clear the
# forced size and re-apply the same mode; the controller's setter does the switch.
utl = one(f"{DISP}/SecDisplayUtils")
us = utl.read_text()
if MARK + " single-mode" not in us:
    m = method(us, "static setDisplayMode(Ljava/lang/String;Landroid/view/Display;)V")
    body = m.group(0)
    if "mWQHDWidth:I" not in body:
        sys.exit("SecDisplayUtils.setDisplayMode: unexpected body")
    lm = re.search(r"^    \.locals \d+\n", body, re.M)
    ins = (f"\n    {MARK} single-mode panel: forced size/density path only\n"
           "    sget v0, Lcom/samsung/android/settings/display/SecDisplayUtils;->mWQHDWidth:I\n\n"
           "    if-nez v0, :crew_dm\n\n    return-void\n\n    :crew_dm\n")
    body = body[:lm.end()] + ins + body[lm.end():]
    us = us[:m.start()] + body + us[m.end():]
    utl.write_text(us)
    changed.append("SecDisplayUtils.setDisplayMode(single-mode)")

print("  resolution: " + (", ".join(changed) if changed else "already patched"))
