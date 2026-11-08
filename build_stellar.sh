#!/bin/bash
# StellarRom release build (no debug) for beyond2lte. usage: ./build_stellar.sh [NAME]
R="$(cd "$(dirname "$0")" && pwd)"; N=${1:-RC1}; cd "$R" || exit 1
unset DEBUG; source ./buildenv.sh beyond2lte
[ "${DEBUG:-false}" = "true" ] && { echo "!! DEBUG is on, aborting"; exit 1; }
export KEEP_SIGNED_APKS_STOCK=true ENABLE_SCOPED_PLATFORM_APK_REBUILDS=true PATCH_DRIFT_POLICY=skip
# Exynos 9820 vendor/kernel package (Vendor_Kernel(Unified)-1.3.zip, path from VK_ZIP), imported once
if [ ! -f out/.stellar_vk_imported ]; then
    ./scripts/import_vendor_kernel.sh || { echo "!! vendor import failed (set VK_ZIP to the zip path)"; exit 1; }
    mkdir -p out && touch out/.stellar_vk_imported
fi
# rsync quick-check (size+mtime) keeps stale files across base switches -> wipe work_dir when the base changes
STAMP=out/target/beyond2lte/.crew_src_stamp; KEY="$(grep -h '^ESSI85_SOURCE' target/beyond2lte/config.sh)|$(cat out/fw/*/.extracted 2>/dev/null | tr '\n' ' ')"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$KEY" ]; then echo "base changed -> clean work_dir + apktool"; rm -rf out/target/beyond2lte/work_dir out/target/beyond2lte/apktool; mkdir -p out/target/beyond2lte; echo "$KEY" > "$STAMP"; fi
./scripts/make_rom.sh --force 2>&1 | tee "out/build_$N.log"; RC=${PIPESTATUS[0]}
[ $RC -eq 0 ] || { echo "BUILD FAILED rc=$RC"; exit 1; }
W=$R/out/target/beyond2lte/work_dir; S=$W/system/system
echo "== release checks (all must be 0)"
echo "  crew debug files:   $(ls $S/bin/crew_* $S/etc/init/crew_* 2>/dev/null | wc -l)"
echo "  crew_bootwd policy: $(grep -c crew_bootwd $S/etc/selinux/plat_sepolicy.cil)"
echo "  debug props:        $(grep -c -E '^(ro\.adb\.secure=0|ro\.debuggable=1|ro\.secure=0|persist\.sys\.usb\.config=adb)$' $S/build.prop)"
echo "== fixes present (all must be >=1)"
echo "  ueventd $(grep -c 'crew: vendor ueventd rules' $S/etc/ueventd.rc)  ion $(grep -c '^;; crew ion$' $S/etc/selinux/plat_sepolicy.cil)  gaps $(grep -c '^;; crew gaps$' $S/etc/selinux/plat_sepolicy.cil)  c2 $(grep -c '^media.c2.hal.selection=hidl' $S/build.prop)  icu32 $(ls $S/lib/libandroidicu.so 2>/dev/null | wc -l)"
echo "== output: $(ls -t "$R"/out/*.zip | head -1)"
