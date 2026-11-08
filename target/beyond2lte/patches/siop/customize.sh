SI_SCAN="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/ScanPackageUtils.smali"
SI_APK="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk"
SI_NAME="$(sed -n 's|.*<SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME>\([^<]*\)</.*|\1|p' "$WORK_DIR/system/system/etc/floating_feature.xml" | head -n 1)"
if ! grep -q '"com.sec.android.sdhms"' "$SI_SCAN" 2> /dev/null || [ ! -d "$SI_APK/assets" ]; then
    LOGW "SDHMS is not being rebuilt (sdhms module/bridge missing), keeping stock SIOP"
elif [ -z "$SI_NAME" ]; then
    LOGW "No SIOP policy name in floating_feature.xml, keeping stock SIOP"
else
    LOG_STEP_IN "- Installing S10+ SIOP policy as assets/$SI_NAME.xml"
    for SI_A in siop_default siop_model ssrm_default; do
        [ -f "$SI_APK/assets/$SI_A" ] && { LOG "- Deleting encrypted assets/$SI_A"; rm -f "$SI_APK/assets/$SI_A"; }
    done
    cp -a "$MODPATH/siop_default.xml" "$SI_APK/assets/siop_default.xml"
    cp -a "$MODPATH/siop_default.xml" "$SI_APK/assets/ssrm_default.xml"
    cp -a "$MODPATH/siop_model.xml" "$SI_APK/assets/$SI_NAME.xml"
    LOG "- assets: $(ls "$SI_APK/assets" | grep -E 'siop|ssrm' | tr '\n' ' ')"
    LOG_STEP_OUT
fi
unset SI_SCAN SI_APK SI_NAME SI_A

# crew-siop-dynamic-name: install the policy under whatever name the active
# floating feature asks for (S23 FE = siop_r11s_exynos2200, S26 FE differs)
CREW_FF="$WORK_DIR/system/system/etc/floating_feature.xml"
CREW_SIOP_ASSETS="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/assets"
CREW_SIOP_NAME="$(grep -o '<SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME>[^<]*' "$CREW_FF" 2> /dev/null | cut -d '>' -f 2)"
CREW_SIOP_SRC="$(find "$CREW_SIOP_ASSETS" -maxdepth 1 -name 'siop_*.xml' ! -name 'siop_default.xml' ! -name 'siop_model.xml' 2> /dev/null | sort | head -n 1)"
if [ -n "$CREW_SIOP_NAME" ] && [ -n "$CREW_SIOP_SRC" ] && [ ! -f "$CREW_SIOP_ASSETS/$CREW_SIOP_NAME.xml" ]; then
    cp -a "$CREW_SIOP_SRC" "$CREW_SIOP_ASSETS/$CREW_SIOP_NAME.xml"
    LOG "- SIOP policy also installed as assets/$CREW_SIOP_NAME.xml (floating feature)"
else
    LOG "- SIOP policy name: ${CREW_SIOP_NAME:-<unset>} (src: ${CREW_SIOP_SRC##*/})"
fi
unset CREW_FF CREW_SIOP_ASSETS CREW_SIOP_NAME CREW_SIOP_SRC

# crew-siop-remap: the active policy is the source device one; its CPU/GPU
# limits are not 9820 steps, so SDHMS rejects the whole doc (no thermal control).
# Floor every limiter value to the Singularity big-cluster / Mali tables.
CREW_FF="$WORK_DIR/system/system/etc/floating_feature.xml"
CREW_SIOP_ASSETS="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk/assets"
CREW_SIOP_NAME="$(grep -o '<SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME>[^<]*' "$CREW_FF" 2> /dev/null | cut -d '>' -f 2)"
if [ -f "$CREW_SIOP_ASSETS/$CREW_SIOP_NAME.xml" ]; then
    python3 -I - "$CREW_SIOP_ASSETS/$CREW_SIOP_NAME.xml" <<'PYEOF' || LOGW "SIOP remap failed, policy left as is"
import re, sys
f = sys.argv[1]; s = open(f).read()
T = {"CPUFreqMax": [3016000, 2912000, 2808000, 2730000, 2600000, 2530000, 2470000, 2340000, 2236000, 2080000, 1976000,
                    1820000, 1664000, 1560000, 1456000, 1378000, 1248000, 1144000, 1040000, 936000, 819000, 728000, 624000, 520000],
     "GPUFreqMax": [988000, 910000, 806000, 754000, 702000, 650000, 572000, 433000, 377000, 325000, 260000, 156000]}
ch = {}
def floor(tab, v):
    if v <= 0 or v in tab: return v
    lower = [x for x in tab if x <= v]
    return max(lower) if lower else min(tab)
def fix_tag(m):
    tag = m.group(0); name = re.search(r'name="([^"]+)"', tag).group(1)
    def fix_val(vm):
        out = []
        for p in re.split(r'([:,])', vm.group(2)):
            p = p.strip()
            if re.fullmatch(r'\d+', p):
                n = floor(T[name], int(p))
                if n != int(p): ch[f"{name} {p}"] = n
                p = str(n)
            out.append(p)
        return vm.group(1) + ''.join(out) + '"'
    return re.sub(r'(value=")([^"]*)"', fix_val, tag)
s = re.sub(r'<limiter\b[^>]*name="(?:CPUFreqMax|GPUFreqMax)"[^>]*>', fix_tag, s)
open(f, 'w').write(s)
print("  siop remap:", ", ".join(f"{k}->{v}" for k, v in sorted(ch.items())) or "nothing to change")
PYEOF
else
    LOGW "SIOP policy ${CREW_SIOP_NAME:-<unset>}.xml not in SDHMS assets, remap skipped"
fi
unset CREW_FF CREW_SIOP_ASSETS CREW_SIOP_NAME
