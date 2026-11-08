SKIPUNZIP=1
# crew: Settings > Display > Screen resolution (WQHD+/FHD+/HD+) on the QHD S10+.
# The FHD S23 FE SecSettings keeps the UI/entries/getScreenResolution(), but its
# availability and setter are compiled out; see crew_resolution_smali.py. The
# switch uses IWindowManager forced size + density (the classic, framework-agnostic
# path), so framework/gamemanager/surfaceflinger stay stock.
if [[ "${TARGET_HAS_QHD_DISPLAY:-false}" != "true" ]]; then
    return 0
fi
if [[ "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    LOGW "Scoped platform rebuilds are off: SecSettings stays stock, no resolution switch"
    return 0
fi
RES_SCAN="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/ScanPackageUtils.smali"
if ! grep -q '"com.android.settings"' "$RES_SCAN" 2> /dev/null; then
    LOGW "SecSettings is not in the scoped signature bridge (rom_logo off?): no resolution switch"
    return 0
fi

LOG_STEP_IN "- Enabling screen resolution switch (WQHD+/FHD+/HD+)"
DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || exit 1
RES_APK="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
python3 "$MODPATH/crew_resolution_smali.py" "$RES_APK" || ABORT "SecSettings resolution smali edit failed"

# The edited dex is reassembled from smali, which drops outdoor mode's in-place
# dex patch if its controller lives there: apply the same edit at smali level.
python3 - "$RES_APK" <<'PYEOF' || ABORT "Outdoor smali edit failed"
import glob, re, sys
hits = glob.glob(sys.argv[1] + '/smali*/com/samsung/android/settings/**/SecOutDoorModePreferenceController.smali', recursive=True)
for f in hits:
    s = open(f).read()
    if '# crew-outdoor' in s:
        continue
    s2, n = re.subn(r'(\.method public (?:final )?isAvailable\(\)Z\n).*?(\.end method)',
                    r'\1    .locals 0\n\n    # crew-outdoor\n    const/4 p0, 0x1\n\n    return p0\n\2', s, flags=re.S)
    if n:
        open(f, 'w').write(s2); print('  outdoor (smali):', f.split('/smali')[-1])
PYEOF
touch "$(dirname "$RES_APK")/.$(basename "$RES_APK").code_patched"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL" "WQHD,FHD,HD"
LOG_STEP_OUT
unset RES_SCAN RES_APK

# crew-res-framework: A17 CoreRune hardcodes multi/dynamic resolution to false
# (S26 FE is FHD-only), so the UN1CA equals() patch has nothing to hit. Force
# both flags on through a fresh <clinit> register; GameManager gets the UN1CA edit.
LOG_STEP_IN "- crew: framework dynamic resolution (CoreRune + GameManager)"
python3 -I - "$APKTOOL_DIR/system/framework/framework.jar" <<'PYEOF' || ABORT "CoreRune resolution patch failed"
import glob, re, sys
hits = glob.glob(sys.argv[1] + '/smali*/com/samsung/android/rune/CoreRune.smali')
if not hits: sys.exit("CoreRune.smali not found (framework.jar not decoded)")
f = hits[0]; s = open(f).read()
if '# crew-res' in s: print('  CoreRune: already patched'); sys.exit(0)
m = re.search(r"\.method [^\n]*<clinit>\(\)V\n\s*\.(?:locals|registers) (\d+)", s)
if not m: sys.exit("CoreRune <clinit> .locals not found")
n = int(m.group(1)); r = f'v{n}'
s = s[:m.start(1)] + str(n + 1) + s[m.end(1):]
cnt = 0
for fld in ('FW_SUPPORT_MULTI_RESOLUTION', 'FW_DYNAMIC_RESOLUTION_CONTROL'):
    pat = re.compile(r'sput-boolean v\d+, (Lcom/samsung/android/rune/CoreRune;->' + fld + r':Z)')
    s, k = pat.subn(lambda mm: f'const/16 {r}, 0x1  # crew-res\n\n    sput-boolean {r}, {mm.group(1)}', s)
    cnt += k
if cnt < 2: sys.exit(f"CoreRune: only {cnt}/2 flags found")
open(f, 'w').write(s); print('  CoreRune: FW_SUPPORT_MULTI_RESOLUTION + FW_DYNAMIC_RESOLUTION_CONTROL -> true via', r)
PYEOF
CREW_GM="$APKTOOL_DIR/system/framework/gamemanager.jar"
if [ ! -d "$CREW_GM" ] && type DECODE_APK > /dev/null 2>&1; then
    DECODE_APK "system" "system/framework/gamemanager.jar"
fi
if [ -d "$CREW_GM" ]; then
    python3 -I - "$CREW_GM" <<'PYEOF' || LOGW "GameManager: dynamic resolution equals() not found, stays stock"
import glob, re, sys
fs = glob.glob(sys.argv[1] + '/smali*/**/GameManagerService$DisplayListener.smali', recursive=True)
if not fs: sys.exit(1)
pat = re.compile(r'(const-string (v\d+), ""\n\n\s*invoke-virtual \{)(v\d+), \2(\}, Ljava/lang/String;->equals\(Ljava/lang/Object;\)Z)')
done = 0
for f in fs:
    s = open(f).read()
    if '# crew-res' in s: done = 1; continue
    s2, k = pat.subn(lambda m: m.group(1) + m.group(3) + ', ' + m.group(3) + m.group(4) + '  # crew-res', s)
    if k: open(f, 'w').write(s2); done += k; print('  GameManager:', f.split('/smali')[-1], k, 'edit(s)')
sys.exit(0 if done else 1)
PYEOF
else
    LOGW "GameManager: gamemanager.jar not decoded, stays stock"
fi
unset CREW_GM
LOG_STEP_OUT
