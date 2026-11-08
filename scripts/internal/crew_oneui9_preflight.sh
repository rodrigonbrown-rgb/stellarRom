#!/usr/bin/env bash
# crew: One UI 9 (S741B) donor preflight -> ~/Desktop/crew_oneui9_preflight.tgz
cd "$(dirname "$0")/../.." || exit 1
FW=out/fw/SM-S741B_EUX; ML=out/fw/SM-S711B_EUX
R=out/crew_oneui9_preflight; rm -rf "$R"; mkdir -p "$R/tree"
[ -f "$FW/.extracted" ] || { echo "S741B not extracted"; exit 1; }
export PATH="$PWD/out/tools/bin:$PATH"
SYS=$FW/system/system
apk() { find "$FW" -name "$1" -type f 2>/dev/null | head -1; }
dexstr() { # <archive> <string...>
    local a="$1"; shift
    for s in "$@"; do
        printf '    %-48s %s\n' "$s" "$(unzip -Z1 "$a" 2>/dev/null | grep -E '^classes[0-9]*\.dex$' | while read -r d; do unzip -p "$a" "$d" | grep -a -c -F "$s"; done | awk '{s+=$1} END{print s+0}')"
    done
}
dexver() { unzip -Z1 "$1" 2>/dev/null | grep -E '^classes[0-9]*\.dex$' | sort -V | while read -r d; do printf '%s=%s ' "$d" "$(unzip -p "$1" "$d" | head -c 7 | tail -c 3)"; done; echo; }
{
echo "== firmware"; cat "$FW/.extracted"; echo; cat "$ML/.extracted"; echo
echo "== partitions (S741B | S711B)"; ls "$FW" | paste -sd' '; ls "$ML" | paste -sd' '
du -sh "$FW"/*/ 2>/dev/null
echo "== props"
for f in "$SYS/build.prop" "$FW/vendor/build.prop" "$FW/product/etc/build.prop" "$FW/odm/etc/build.prop"; do
  [ -f "$f" ] && grep -E '^ro\.(build\.version\.(sdk|release|oneui|security_patch)|vndk\.version|board\.(api_level|first_api_level)|vendor\.api_level|product\.first_api_level|product(\.vendor|\.system)?\.(device|model)|product\.cpu\.abilist[0-9]*|system\.product\.cpu\.abilist[0-9]*|vendor\.product\.cpu\.abilist[0-9]*|build\.display\.id|zygote)=' "$f" | sed "s|^|${f#$FW/}: |"
done
echo "== floating features"
grep -o -E '<SEC_FLOATING_FEATURE_(SYSTEM_CONFIG_SIOP_POLICY_FILENAME|SYSTEM_CONFIG_DVFS[A-Z_]*|LCD_CONFIG_[A-Z_]*|COMMON_CONFIG_DYN_RESOLUTION_CONTROL|SETTINGS_SUPPORT_FUNCTION_KEY_MENU|BIXBY_SUPPORT_LONG_KEY_SERVICE)>[^<]*' "$SYS/etc/floating_feature.xml" 2>/dev/null
echo "== apex"; ls "$SYS/apex" | paste -sd' '
echo "== vintf"; ls "$SYS/etc/vintf" | paste -sd' '
grep -h -o '<kernel version="[^"]*"' "$SYS"/etc/vintf/compatibility_matrix.*.xml 2>/dev/null | sort -u | paste -sd' '
for k in fkeymaster knoxguard keymaster keymint; do printf '  %-10s %s\n' "$k" "$(grep -l -i "$k" "$SYS"/etc/vintf/*.xml 2>/dev/null | xargs -r -n1 basename | paste -sd' ')"; done
echo "== system_ext vendor-ndk"; grep -A2 "<vendor-ndk>" "$SYS/system_ext/etc/vintf/manifest.xml" 2>/dev/null | grep -o "<version>[^<]*" | paste -sd" "; ls "$SYS/system_ext/apex" 2>/dev/null | paste -sd" "
echo "== init (aconfig / bpf)"
grep -rn -E 'aconfig|load-bpf-programs|bpfloader|netbpfload' "$SYS/etc/init" 2>/dev/null | head -25
echo "== dex versions"
for n in framework.jar services.jar ssrm.jar gamemanager.jar SystemUI.apk SecSettings.apk SamsungDeviceHealthManagerService.apk; do
  a=$(apk "$n"); [ -n "$a" ] && printf '%s (%s): %s\n' "$n" "${a#$FW/}" "$(dexver "$a")"
done
echo "== module targets (string hits in dex)"
a=$(apk framework.jar); echo "  framework.jar"; [ -n "$a" ] && dexstr "$a" "Landroid/app/Instrumentation;" "newApplication" "Lcom/samsung/android/rune/InputRune;" "PWM_KEY_COMBINATION_SCREENSHOT_SIDE_KEY" "MultiUserSupportsHelper" "IS_TABLET"
a=$(apk services.jar); echo "  services.jar"; [ -n "$a" ] && dexstr "$a" "Lcom/android/server/pm/ScanPackageUtils;" "KeyCombinationManager" "ASKSManagerService" "ro.build.official.release"
a=$(apk SystemUI.apk); echo "  SystemUI.apk"; [ -n "$a" ] && dexstr "$a" "IndicatorGardenAlgorithm" "calculateRightPadding" "cutoutSidePaddingD" "KeyguardStatusBarView"
a=$(apk SecSettings.apk); echo "  SecSettings.apk"; [ -n "$a" ] && dexstr "$a" "SecOutDoorModePreferenceController" "ModelNameGetter"
[ -f target/beyond2lte/patches/outdoor/dexpatch_outdoor.py ] && python3 target/beyond2lte/patches/outdoor/dexpatch_outdoor.py --check "$a"
a=$(apk SamsungDeviceHealthManagerService.apk); echo "  SDHMS"; [ -n "$a" ] && dexstr "$a" "SSRM Warning" "siop_default" "ssrm_default"
unzip -Z1 "$a" 2>/dev/null | grep -E '^assets/(siop|ssrm|dvfs)' | paste -sd' '
} > "$R/report.txt" 2>&1

# NetBpfLoad from the Tethering APEX
python3 - "$FW" "$R" <<'PYEOF' >> "$R/report.txt" 2>&1
import hashlib, sys, tempfile, shutil
from pathlib import Path
sys.path.insert(0, "scripts/internal")
import crew_runtime_abi_check as c
fw, out = Path(sys.argv[1]), Path(sys.argv[2])
t = c.Tools(["out/tools/bin"])
print("== tethering / netbpfload")
for arc in c.all_apexes(fw):
    if "tethering" not in arc.name.lower():
        continue
    tmp = Path(tempfile.mkdtemp(dir="out"))
    err = c.extract_apex(t, arc, tmp / "p", tmp)
    print(" ", arc.name, err or "extracted")
    for b in (tmp / "p").rglob("*bpf*"):
        if b.is_file() and not b.is_symlink():
            d = b.read_bytes()
            print(f"   {b.relative_to(tmp / 'p')} sha256={hashlib.sha256(d).hexdigest()} "
                  f"gate25Q4_hits={d.count(bytes.fromhex('280200546808009008614439c8010036'))}")
            if b.name.lower() in ("netbpfload", "bpfloader"):
                shutil.copy(b, out / ("s741b_" + b.name))
    shutil.rmtree(tmp, ignore_errors=True)
PYEOF

echo "== runtime/i18n ABI gate (S741B system vs S711B runtime+i18n)" >> "$R/report.txt"
CREW_ABI_TMP=out python3 scripts/internal/crew_runtime_abi_check.py "$FW" "$ML" \
    --tools-bin out/tools/bin --json "$R/abi.json" >> "$R/report.txt" 2>&1
echo "abi_rc=$?" >> "$R/report.txt"

# your current module scripts (to adapt the hash/count pins)
find target/beyond2lte platform/exynos9820 -maxdepth 3 \( -name '*.sh' -o -name '*.edify' -o -name module.prop \) \
    -print0 | xargs -0 -r cp --parents -t "$R/tree"
cp --parents unica/configs/essi85.sh unica/configs/version.sh unica/patches/_desixtification/customize.sh "$R/tree" 2>/dev/null
grep -rn -E 'ABORT|sha256sum|HEX_PATCH|_COUNT' target/beyond2lte platform/exynos9820 --include=customize.sh > "$R/pins.txt" 2>/dev/null

DESK=$(xdg-user-dir DESKTOP 2>/dev/null || echo ~/Desktop)
tar czf "$DESK/crew_oneui9_preflight.tgz" -C out crew_oneui9_preflight
echo; sed -n '/== firmware/,/== floating/p' "$R/report.txt" | head -30
grep -A12 '== runtime/i18n ABI gate' "$R/report.txt"
ls -la "$DESK/crew_oneui9_preflight.tgz"
