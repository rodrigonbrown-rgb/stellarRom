if [[ $TARGET_SINGLE_SYSTEM_IMAGE == "qssi" || \
        $TARGET_SINGLE_SYSTEM_IMAGE == "essi" || \
        $TARGET_SINGLE_SYSTEM_IMAGE == "essi85" ]]; then
    LOG_STEP_IN "- Target device with 32-Bit HALs detected."

    MULTILIB_SOURCE="r11sxxx"
    if [[ "$TARGET_SINGLE_SYSTEM_IMAGE" == "essi85" ]]; then
        [ -n "${MULTILIB_FIRMWARE:-}" ] || \
            ABORT "MULTILIB_FIRMWARE is required for essi85"
        MULTILIB_SOURCE="$MULTILIB_FIRMWARE"
    fi

    # crew: API 37 donor + API 36 S23 FE 32-bit layer: keep the donor runtime/i18n
    # APEX (A16 linkerconfig needs fmt::v11, A17 libbase exports fmt::v12) and ship
    # the API 36 32-bit linker and bionic as regular /system files.
    CREW_ML_DIR=""
    CREW_ML_SDK=""
    if [[ "$TARGET_SINGLE_SYSTEM_IMAGE" == "essi85" ]]; then
        CREW_ML_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$MULTILIB_SOURCE")_$(cut -d "/" -f 2 -s <<< "$MULTILIB_SOURCE")"
        CREW_ML_SDK="$(sed -n 's/^ro.build.version.sdk=//p' "$CREW_ML_DIR/system/system/build.prop" 2> /dev/null | head -n 1)"
    fi

    if [ -n "$CREW_ML_SDK" ] && [[ "$CREW_ML_SDK" != "$SOURCE_API_LEVEL" ]]; then
        LOG_STEP_IN "- Split runtime: API $SOURCE_API_LEVEL runtime/i18n APEX kept, API $CREW_ML_SDK 32-bit layer from $MULTILIB_SOURCE"
        DELETE_FROM_WORK_DIR "system" "system/lib"
        ADD_TO_WORK_DIR "$MULTILIB_SOURCE" "system" "system/lib"
        for blob in system/bin/bootstrap/linker system/bin/bootstrap/linker_asan
        do
            DELETE_FROM_WORK_DIR "system" "$blob"
            ADD_TO_WORK_DIR "$MULTILIB_SOURCE" "system" "$blob"
            SET_METADATA "system" "$blob" 0 0 755 "u:object_r:system_linker_exec:s0"
        done

        mkdir -p "$TMP_DIR"
        CREW_RT32="$(mktemp -d "$TMP_DIR/crew-rt32.XXXXXX")"
        python3 - "$SRC_DIR/scripts/internal" \
            "$CREW_ML_DIR/system/system/apex/com.android.runtime.apex" \
            "$CREW_RT32" "$TOOLS_DIR/bin" <<'PYEOF' || ABORT "Could not extract the 32-bit linker/bionic from the multilib runtime APEX"
import struct, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import crew_runtime_abi_check as c
out = Path(sys.argv[3])
err = c.extract_apex(c.Tools([sys.argv[4]]), Path(sys.argv[2]), out / "p", out)
if err:
    sys.exit(err)
for rel in ("bin/linker", "lib/bionic/libc.so", "lib/bionic/libdl.so",
            "lib/bionic/libdl_android.so", "lib/bionic/libm.so"):
    f = out / "p" / rel
    h = f.read_bytes()[:20] if f.is_file() and not f.is_symlink() else b""
    if not (len(h) == 20 and h[:4] == b"\x7fELF" and h[4] == 1
            and struct.unpack_from("<H", h, 18)[0] == 40):
        sys.exit(f"not a regular ARM ELF32: {rel}")
    print(f"      32-bit {rel}")
PYEOF
        rm -f "$WORK_DIR/system/system/bin/linker" "$WORK_DIR/system/system/bin/linker_asan"
        cp -f "$CREW_RT32/p/bin/linker" "$WORK_DIR/system/system/bin/linker"
        ln -sf "linker" "$WORK_DIR/system/system/bin/linker_asan"
        SET_METADATA "system" "system/bin/linker" 0 0 755 "u:object_r:system_linker_exec:s0"
        SET_METADATA "system" "system/bin/linker_asan" 0 0 755 "u:object_r:system_linker_exec:s0"
        for CREW_BIONIC in libc libdl libdl_android libm
        do
            rm -f "$WORK_DIR/system/system/lib/$CREW_BIONIC.so"
            cp -f "$CREW_RT32/p/lib/bionic/$CREW_BIONIC.so" "$WORK_DIR/system/system/lib/$CREW_BIONIC.so"
            SET_METADATA "system" "system/lib/$CREW_BIONIC.so" 0 0 644 "u:object_r:system_lib_file:s0"
        done
        rm -rf "$CREW_RT32"
        unset CREW_RT32 CREW_BIONIC
        LOG_STEP_OUT
    else
        LOG_STEP_IN "- Adding multilib system runtime from $MULTILIB_SOURCE"
        DELETE_FROM_WORK_DIR "system" "system/lib"
        ADD_TO_WORK_DIR "$MULTILIB_SOURCE" "system" "system/lib"

        BLOBS_LIST="
        system/apex/com.android.i18n.apex
        system/apex/com.android.runtime.apex
        system/bin/bootstrap/linker
        system/bin/bootstrap/linker_asan
        "
        if [[ "$TARGET_SINGLE_SYSTEM_IMAGE" != "essi85" ]]; then
            BLOBS_LIST+=" system/apex/com.google.android.tzdata6.apex"
        fi
        for blob in $BLOBS_LIST
        do
            DELETE_FROM_WORK_DIR "system" "$blob"
            ADD_TO_WORK_DIR "$MULTILIB_SOURCE" "system" "$blob"
        done
        LOG_STEP_OUT

        LOG_STEP_IN "- Creating symlinks"
        ln -sf "/apex/com.android.runtime/bin/linker" "$WORK_DIR/system/system/bin/linker"
        ln -sf "/apex/com.android.runtime/bin/linker" "$WORK_DIR/system/system/bin/linker_asan"
        SET_METADATA "system" "system/bin/linker" 0 0 755 "u:object_r:system_linker_exec:s0"
        SET_METADATA "system" "system/bin/linker_asan" 0 0 755 "u:object_r:system_linker_exec:s0"

        ln -sf "/apex/com.android.runtime/lib/bionic/libc.so" "$WORK_DIR/system/system/lib/libc.so"
        ln -sf "/apex/com.android.runtime/lib/bionic/libdl.so" "$WORK_DIR/system/system/lib/libdl.so"
        ln -sf "/apex/com.android.runtime/lib/bionic/libdl_android.so" "$WORK_DIR/system/system/lib/libdl_android.so"
        ln -sf "/apex/com.android.runtime/lib/bionic/libm.so" "$WORK_DIR/system/system/lib/libm.so"
        SET_METADATA "system" "system/lib/libc.so" 0 0 644 "u:object_r:system_lib_file:s0"
        SET_METADATA "system" "system/lib/libdl.so" 0 0 644 "u:object_r:system_lib_file:s0"
        SET_METADATA "system" "system/lib/libdl_android.so" 0 0 644 "u:object_r:system_lib_file:s0"
        SET_METADATA "system" "system/lib/libm.so" 0 0 644 "u:object_r:system_lib_file:s0"
        LOG_STEP_OUT
    fi
    unset CREW_ML_DIR CREW_ML_SDK

    LOG_STEP_IN "- Setting props"
    SET_PROP "vendor" "ro.vendor.product.cpu.abilist" "arm64-v8a"
    SET_PROP "vendor" "ro.vendor.product.cpu.abilist32" ""
    SET_PROP "vendor" "ro.vendor.product.cpu.abilist64" "arm64-v8a"
    SET_PROP "vendor" "ro.zygote" "zygote64"
    SET_PROP "vendor" "dalvik.vm.dex2oat64.enabled" "true"
    for ABI_PART in system product odm; do
        for ABI_PREFIX in "ro.$ABI_PART.product.cpu" "ro.product.cpu"; do
            [[ "$ABI_PART" != "system" && "$ABI_PREFIX" == "ro.product.cpu" ]] && continue
            if [ -n "$(GET_PROP "$ABI_PART" "$ABI_PREFIX.abilist" 2> /dev/null)" ] || \
                    [ -n "$(GET_PROP "$ABI_PART" "$ABI_PREFIX.abilist32" 2> /dev/null)" ]; then
                SET_PROP "$ABI_PART" "$ABI_PREFIX.abilist" "arm64-v8a"
                SET_PROP "$ABI_PART" "$ABI_PREFIX.abilist32" ""
                SET_PROP "$ABI_PART" "$ABI_PREFIX.abilist64" "arm64-v8a"
            fi
        done
    done
    unset ABI_PART ABI_PREFIX
    LOG_STEP_OUT

    unset MULTILIB_SOURCE BLOBS_LIST blob
    LOG_STEP_OUT
else
    LOG "- Target device does not use 32-Bit HALs. Ignoring."
fi
