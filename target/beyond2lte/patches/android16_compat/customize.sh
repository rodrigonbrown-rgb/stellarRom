TARGET_COMPAT_SOURCE="$FW_DIR/$TARGET_FIRMWARE_PATH"
TARGET_NATIVE_DENSITY="$(sed -n 's/^ro.sf.init.lcd_density=//p' \
    "$TARGET_COMPAT_SOURCE/vendor/build.prop")"
if ! [[ "$TARGET_NATIVE_DENSITY" =~ ^[0-9]*$ ]]; then
    ABORT "Unexpected d2s native display density: $TARGET_NATIVE_DENSITY"
fi
SET_PROP "vendor" "ro.sf.lcd_density" "$TARGET_NATIVE_DENSITY"
unset TARGET_NATIVE_DENSITY

TARGET_FCM_LEVEL="$(sed -n 's/.*target-level="\([^"]*\)".*/\1/p' \
    "$TARGET_COMPAT_SOURCE/vendor/etc/vintf/manifest.xml" | head -n 1)"

if [[ "$TARGET_FCM_LEVEL" != "3" ]]; then
    ABORT "Unexpected d2s target FCM level: ${TARGET_FCM_LEVEL:-missing}"
fi

for TARGET_FCM_MATRIX_LEVEL in 3 4; do
    TARGET_FCM_MATRIX="system/etc/vintf/compatibility_matrix.$TARGET_FCM_MATRIX_LEVEL.xml"
    if [ ! -f "$TARGET_COMPAT_SOURCE/system/$TARGET_FCM_MATRIX" ]; then
        ABORT "Target firmware is missing $TARGET_FCM_MATRIX"
    fi

    LOG "- Restoring d2s framework compatibility matrix level $TARGET_FCM_MATRIX_LEVEL"
    ADD_TO_WORK_DIR "$TARGET_COMPAT_SOURCE" "system" "$TARGET_FCM_MATRIX" \
        0 0 644 "u:object_r:system_file:s0"
done

LOG "- Removing unsupported Knox Matrix/Fkeymaster consumers"
for KNOX_MATRIX_FILE in \
    "system/bin/fabric_crypto" \
    "system/etc/init/fabric_crypto.rc" \
    "system/etc/permissions/FabricCryptoLib.xml" \
    "system/etc/permissions/privapp-permissions-com.samsung.android.kmxservice.xml" \
    "system/etc/vintf/manifest/fabric_crypto_manifest.xml" \
    "system/framework/FabricCryptoLib.jar" \
    "system/lib64/com.samsung.security.fabric.cryptod-V1-cpp.so" \
    "system/lib64/vendor.samsung.hardware.security.fkeymaster-V1-cpp.so" \
    "system/lib64/vendor.samsung.hardware.security.fkeymaster-V1-ndk.so" \
    "system/priv-app/KmxService"
do
    DELETE_FROM_WORK_DIR "system" "$KNOX_MATRIX_FILE"
done

FKEYMASTER_MATRIX="$WORK_DIR/system/system/etc/vintf/compatibility_matrix.device.xml"
FKEYMASTER_MATRIX_COUNT="$(grep -c \
    '<name>vendor.samsung.hardware.security.fkeymaster</name>' \
    "$FKEYMASTER_MATRIX" 2> /dev/null || true)"
if [ "${FKEYMASTER_MATRIX_COUNT:-0}" -ge 1 ]; then
    sed -i '/^[[:space:]]*<hal format="aidl">[[:space:]]*$/ {
        :fkeymaster_hal
        N
        /<\/hal>/!b fkeymaster_hal
        /<name>vendor\.samsung\.hardware\.security\.fkeymaster<\/name>/d
    }' "$FKEYMASTER_MATRIX"
else
    LOG "- No framework Fkeymaster requirement in this source"
fi

LOG "- Removing unsupported KnoxGuard consumer"
for KNOX_GUARD_FILE in \
    "system/etc/permissions/privapp-permissions-com.samsung.android.kgclient.xml" \
    "system/etc/permissions/signature-permissions-com.samsung.android.kgclient.xml" \
    "system/priv-app/KnoxGuard"
do
    DELETE_FROM_WORK_DIR "system" "$KNOX_GUARD_FILE"
done

KNOX_GUARD_MATRIX_COUNT="$(grep -c \
    '<name>vendor.samsung.hardware.tlc.kg</name>' \
    "$FKEYMASTER_MATRIX" 2> /dev/null || true)"
if [ "${KNOX_GUARD_MATRIX_COUNT:-0}" -ge 1 ]; then
    sed -i \
        -e '/vendor\/samsung\/interfaces\/tlc\/kg\/2\.0\/aidl\/vendor\.samsung\.hardware\.tlc\.kg-matrix\.xml/d' \
        -e '/^[[:space:]]*<hal format="aidl">[[:space:]]*$/ {
            :knoxguard_hal
            N
            /<\/hal>/!b knoxguard_hal
            /<name>vendor\.samsung\.hardware\.tlc\.kg<\/name>/d
        }' \
        "$FKEYMASTER_MATRIX"
else
    LOG "- No framework KnoxGuard requirement in this source"
fi

KNOX_GUARD_CONFIGS=(
    "system/etc/broadcast_allowlist.xml"
    "system/etc/deviceidle/reviewed_allowlist.xml"
    "system/etc/irremovable_list.txt"
    "system/etc/permissions/platform.xml"
    "system/etc/sysconfig/allowed-system-preload-apps.xml"
    "system/etc/sysconfig/required-packages.xml"
    "system/etc/sysconfig/safe-mode-allow-list.xml"
)
for KNOX_GUARD_CONFIG in "${KNOX_GUARD_CONFIGS[@]}"; do
    KNOX_GUARD_CONFIG_PATH="$WORK_DIR/system/$KNOX_GUARD_CONFIG"
    [ -f "$KNOX_GUARD_CONFIG_PATH" ] || continue
    sed -i '/com\.samsung\.android\.kgclient/d' "$KNOX_GUARD_CONFIG_PATH"
done

# crew-knoxguard-systemserver: never start KnoxGuardService (same as the
# 8.5 smali patch, matched by pattern instead of line context so it survives
# donor updates). isFactoryBinary() if-nez -> goto past StartKnoxGuard.
LOG "- Disabling the unsupported KnoxGuard system service"
DECODE_APK "system" "system/framework/services.jar" || ABORT "Failed to decode services.jar"
python3 - "$APKTOOL_DIR/system/framework/services.jar" <<'KGEOF' || ABORT "KnoxGuard SystemServer edit failed (context above)"
import re, sys
from pathlib import Path
hits = list(Path(sys.argv[1]).glob("smali*/com/android/server/SystemServer.smali"))
if len(hits) != 1:
    sys.exit(f"SystemServer.smali: {len(hits)} candidates")
f = hits[0]; s = f.read_text()
done = re.compile(r'\n    goto :\w+\n\n    const-string(?:/jumbo)? [vp]\d+, "StartKnoxGuard"')
pat = re.compile(
    r'(?P<blk>    invoke-static \{\}, Landroid/os/FactoryTest;->isFactoryBinary\(\)Z\n\n'
    r'    move-result (?P<r>[vp]\d+)\n\n'
    r'    if-nez (?P=r), (?P<lbl>:\w+)\n)'
    r'(?=\n    const-string(?:/jumbo)? [vp]\d+, "StartKnoxGuard")')
m = list(pat.finditer(s))
if len(m) == 1:
    s = s[:m[0].start()] + f"    goto {m[0]['lbl']}\n" + s[m[0].end():]
    f.write_text(s)
    print(f"      {f.name}: StartKnoxGuard skipped (goto {m[0]['lbl']})")
elif not m and done.search(s):
    print(f"      {f.name}: StartKnoxGuard already skipped")
else:
    i = s.find('"StartKnoxGuard"')
    if i < 0:
        print("      no StartKnoxGuard in SystemServer (service not started here)")
        sys.exit(0)
    print(f"      {len(m)} pattern match(es); context:")
    print(s[max(0, i - 900):i + 600])
    sys.exit(1)
KGEOF

SET_PROP "system" "ro.config.iccc_version" --delete

ACONFIG_INIT_RC="$WORK_DIR/system/system/etc/init/aconfigd.rc"
[ -f "$ACONFIG_INIT_RC" ] || ABORT "aconfigd.rc is missing"
if ! grep -q 'mount tmpfs tmpfs /metadata nodev noexec nosuid' "$ACONFIG_INIT_RC"; then
    if grep -q '^on early-init$' "$ACONFIG_INIT_RC"; then
        sed -i '0,/^on early-init$/{/^on early-init$/a\
    # crew: emulate the missing modern metadata partition for generated flags.\
    mount tmpfs tmpfs /metadata nodev noexec nosuid mode=0775,uid=0,gid=1000,size=64m
}' "$ACONFIG_INIT_RC"
    else
        printf '\non early-init\n    # crew: emulate the missing modern metadata partition for generated flags.\n    mount tmpfs tmpfs /metadata nodev noexec nosuid mode=0775,uid=0,gid=1000,size=64m\n' \
            >> "$ACONFIG_INIT_RC"
    fi
fi
[ "$(grep -c 'mount tmpfs tmpfs /metadata nodev noexec nosuid' "$ACONFIG_INIT_RC")" = "1" ] || \
    ABORT "Failed to add the /metadata tmpfs to aconfigd.rc"
# A fresh tmpfs root is labeled tmpfs, but aconfigd may only search metadata_file:
# without this, early_system_aconfigd_platform_init is denied at early-init and
# the boot flag storage is never written (init.rc only relabels it at post-fs).
if ! grep -q '^    restorecon /metadata$' "$ACONFIG_INIT_RC"; then
    sed -i '/^    mount tmpfs tmpfs \/metadata nodev noexec nosuid/a\
    restorecon /metadata' "$ACONFIG_INIT_RC"
fi
[ "$(grep -c '^    restorecon /metadata$' "$ACONFIG_INIT_RC")" = "1" ] || \
    ABORT "Failed to relabel the /metadata tmpfs in aconfigd.rc"

LOG "- Restoring the d2s HIDL health compatibility service"
for TARGET_HEALTH_FILE in \
    "bin/hw/android.hardware.health@2.1-service-samsung" \
    "etc/init/android.hardware.health@2.1-service-samsung.rc" \
    "etc/vintf/manifest/android.hardware.health@2.1-samsung.xml" \
    "lib/android.hardware.health@2.1.so" \
    "lib64/android.hardware.health@2.1.so"
do
    ADD_TO_WORK_DIR "$TARGET_COMPAT_SOURCE" "vendor" "$TARGET_HEALTH_FILE"
done

LOG_STEP_IN "- Installing the d2s HIDL audio 6.0 compatibility bridge"
if [ -z "${MULTILIB_FIRMWARE:-}" ]; then
    ABORT "MULTILIB_FIRMWARE is required for the d2s audio bridge"
fi

AUDIO_BRIDGE_SOURCE="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$MULTILIB_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$MULTILIB_FIRMWARE")"
AUDIO_BRIDGE_MARKER="S711BXXSGGZF2/S711BOXMGGZF2/S711BXXSGGZF2"
if [ "$(cat "$AUDIO_BRIDGE_SOURCE/.extracted" 2> /dev/null)" != \
        "$AUDIO_BRIDGE_MARKER" ]; then
    ABORT "Unexpected d2s audio bridge firmware in $AUDIO_BRIDGE_SOURCE"
fi

while read -r AUDIO_BRIDGE_SHA256 AUDIO_BRIDGE_FILE; do
    [ -n "$AUDIO_BRIDGE_FILE" ] || continue
    AUDIO_BRIDGE_INPUT="$AUDIO_BRIDGE_SOURCE/vendor/$AUDIO_BRIDGE_FILE"
    if [ ! -f "$AUDIO_BRIDGE_INPUT" ]; then
        ABORT "Audio bridge input is missing: $AUDIO_BRIDGE_INPUT"
    fi
    if [ "$(sha256sum "$AUDIO_BRIDGE_INPUT" | cut -d " " -f 1)" != \
            "$AUDIO_BRIDGE_SHA256" ]; then
        ABORT "Audio bridge input hash changed: $AUDIO_BRIDGE_FILE"
    fi

    ADD_TO_WORK_DIR "$AUDIO_BRIDGE_SOURCE" "vendor" "$AUDIO_BRIDGE_FILE" || \
        ABORT "Failed to install audio bridge file: $AUDIO_BRIDGE_FILE"
    if [ "$(sha256sum "$WORK_DIR/vendor/$AUDIO_BRIDGE_FILE" | cut -d " " -f 1)" != \
            "$AUDIO_BRIDGE_SHA256" ]; then
        ABORT "Installed audio bridge hash mismatch: $AUDIO_BRIDGE_FILE"
    fi
done <<'EOF'
57092f6b3e4af8877d4e23bd32aea197f3b5df9bb7c61f74d3ce3f99ca16aeef lib/hw/android.hardware.audio@6.0-impl.so
0c76d753d51005140b6d029923a53ab8c3b0a559c5536288ddecfd45f3ba275b lib/hw/android.hardware.audio.effect@6.0-impl.so
109bfdee3c58e6b7d297523aeb4b71b4d6782be843855c21aa6da191b1c50e20 lib/android.hardware.audio.common@6.0.so
73cf8256fb62e128cd47b3e1ae2c5013c6c0ca6c4495ac3b93d22476a1de8606 lib/android.hardware.audio.common@6.0-util.so
1f336b8025d87ff702d489d35c4fac1468263530b90102af74e3c713c35656c5 lib/android.hardware.audio@6.0.so
53a08a73458bfc64a0612f8e4fcd4cf63d91121872da1238c8ceb9b726ddf4d5 lib/android.hardware.audio@6.0-util.so
1c8fef364f95e9142ff0f43ab1f76a8278fcd17752383a36765f2d62e0e5ceb1 lib/android.hardware.audio.effect@6.0.so
e606e14965234e9e81d761a530b4b8ccacc66853d029087fce9a93f70de00f6a lib/android.hardware.audio.effect@6.0-util.so
8a34942d275bc565cdbd811755cc15aaa7fc8d75f891678fe2db10378644054e lib/soundfx/libswspatializer.so
444f4f4bf395eed954eab0f7a6396be1e34a0884a6ceccd0efe337cf1899d15f lib/spatializer-aidl-cpp.so
b5bf81305153f730f34f99e3162511817c66ac491ba760c9f06d80c23c56b798 lib64/soundfx/libswspatializer.so
57b159e54bdba0727617481ad891933a51090d0325aefe5c0e7e657d10f6d633 lib64/spatializer-aidl-cpp.so
EOF

AUDIO_MANIFEST="$WORK_DIR/vendor/etc/vintf/manifest.xml"
sed -i \
    -e '/<name>android.hardware.audio<\/name>/,/<\/hal>/ { s/<version>5\.0<\/version>/<version>6.0<\/version>/; s/@5\.0::IDevicesFactory/@6.0::IDevicesFactory/; }' \
    -e '/<name>android.hardware.audio.effect<\/name>/,/<\/hal>/ { s/<version>5\.0<\/version>/<version>6.0<\/version>/; s/@5\.0::IEffectsFactory/@6.0::IEffectsFactory/; }' \
    "$AUDIO_MANIFEST"
LOG_STEP_OUT
if [ ! -f "$WORK_DIR/system/system/lib64/libaudiohal@6.0.so" ] && \
        ! ls "$WORK_DIR"/system/system/lib64/libaudiohal*6.0*.so > /dev/null 2>&1; then
    LOGW "This source has no libaudiohal HIDL 6.0 client: the 6.0 audio bridge may not be used (no sound)"
fi

# crew: NetBpfLoad kernel gates and the BPF ring-buffer consumers are handled
# by target/beyond2lte/patches/tethering_compat (rebuilt Tethering APEX).

LOG "- Updating legacy d2s ueventd sysfs rules"
sed -i \
    -e 's|^/sys/kernel/clat/xlat_v4_addrs[[:space:]].*|/sys/kernel/clat xlat_v4_addrs 0660 clat clat|' \
    -e 's|^/sys/kernel/clat/xlat_addrs[[:space:]].*|/sys/kernel/clat xlat_addrs 0660 clat clat|' \
    -e 's|^/sys/kernel/clat/xlat_plat[[:space:]].*|/sys/kernel/clat xlat_plat 0660 clat clat|' \
    -e '/^\/sys\/bus\/iio\/devices\/iio:device\*[[:space:]][[:space:]]*0664[[:space:]][[:space:]]*system[[:space:]][[:space:]]*radio[[:space:]]*$/d' \
    "$WORK_DIR/vendor/ueventd.rc"

unset TARGET_COMPAT_SOURCE TARGET_FCM_LEVEL TARGET_FCM_MATRIX
unset TARGET_FCM_MATRIX_LEVEL TARGET_HEALTH_FILE
unset KNOX_MATRIX_FILE FKEYMASTER_MATRIX FKEYMASTER_MATRIX_COUNT
unset KNOX_GUARD_FILE KNOX_GUARD_MATRIX_COUNT
unset KNOX_GUARD_CONFIG KNOX_GUARD_CONFIGS KNOX_GUARD_CONFIG_PATH
unset ACONFIG_INIT_RC
unset AUDIO_BRIDGE_SOURCE AUDIO_BRIDGE_MARKER AUDIO_BRIDGE_SHA256
unset AUDIO_BRIDGE_FILE AUDIO_BRIDGE_INPUT AUDIO_MANIFEST
