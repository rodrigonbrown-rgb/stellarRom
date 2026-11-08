SS_FILE="system/priv-app/SecSettings/SecSettings.apk"
SS_TREE="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
SS_CACHE="$APKTOOL_DIR/system/priv-app/SecSettings/.SecSettings.apk.dex_cache"
OD_PY="$SRC_DIR/target/$TARGET_CODENAME/patches/outdoor/dexpatch_outdoor.py"

DECODE_APK "system" "$SS_FILE"

LOG_STEP_IN "- Outdoor mode: SecOutDoorModePreferenceController.isAvailable() -> true"
if [ -f "$SS_CACHE/dex_container_v41" ]; then
    python3 - "$SS_TREE" <<'PYEOF' || LOGW "Outdoor: smali controller not found"
import glob, re, sys
hits = glob.glob(sys.argv[1] + '/smali*/com/samsung/android/settings/**/SecOutDoorModePreferenceController.smali', recursive=True)
if not hits: sys.exit(1)
for f in hits:
    s = open(f).read()
    s2, n = re.subn(r'(\.method public (?:final )?isAvailable\(\)Z\n).*?(\.end method)',
                    r'\1    .locals 0\n\n    const/4 p0, 0x1\n\n    return p0\n\2', s, flags=re.S)
    if n: open(f, 'w').write(s2); print('  patched', f.split('/smali')[-1])
PYEOF
else
    python3 "$OD_PY" "$SS_CACHE"/classes*.dex || LOGW "Outdoor: controller not found in SecSettings dex"
fi
LOG_STEP_OUT
