SKIPUNZIP=1
# crew: Android 17 (API 37) system on the beyond2lte Android 12 vendor / 9820 kernel.

if [[ "${SOURCE_API_LEVEL:-0}" -lt 37 ]]; then
    LOG "- Source API ${SOURCE_API_LEVEL:-?} < 37, nothing to do"
    return 0
fi

LOG_STEP_IN "- Checking cgroup/task-profile descriptors against the proven S23 FE set"
A17_ML_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$MULTILIB_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$MULTILIB_FIRMWARE")"
if [ -f "$A17_ML_DIR/system/system/etc/cgroups.json" ] && \
        [ -f "$A17_ML_DIR/system/system/etc/task_profiles.json" ] && \
        [ -f "$WORK_DIR/system/system/etc/cgroups.json" ]; then
    python3 "$MODPATH/crew_cgroups.py" "$WORK_DIR/system/system/etc" "$A17_ML_DIR/system/system/etc" \
        || ABORT "cgroup descriptor merge failed"
else
    LOGW "cgroup descriptors not found (source or ${A17_ML_DIR#"$FW_DIR"/}), kept source files"
fi
LOG_STEP_OUT

LOG_STEP_IN "- Aligning the SLMK swap watermark with Android 17 RAM Plus"
SET_PROP "vendor" "ro.slmk.swap_free_low_percentage" "10"
SET_PROP "vendor" "ro.slmk.2nd.swap_free_low_percentage" "10"
LOG_STEP_OUT

LOG_STEP_IN "- Disabling unsupported Codec2 resource accounting"
A17_C2_64="$WORK_DIR/system/system/lib64/libsfplugin_ccodec.so"
A17_C2_REQ_FROM="3f2303d5ff0302d1fd7b05a9f53300f9f44f07a9fd430191f30300aa340040f9"
A17_C2_REQ_TO="e0031f2ac0035fd6fd7b05a9f53300f9f44f07a9fd430191f30300aa340040f9"
A17_C2_GLB_FROM="3f2303d5ff8304d1fd7b0ca9fc6f0da9fa670ea9f85f0fa9f65710a9f44f11a9fd030391f30308aaa0fafff000f03491"
A17_C2_GLB_TO="1f7d00a91f0900f9e0031f2ac0035fd6fa670ea9f85f0fa9f65710a9f44f11a9fd030391f30308aaa0fafff000f03491"
if [ -f "$A17_C2_64" ]; then
    A17_C2_HEX="$(od -An -v -tx1 "$A17_C2_64" | tr -d ' \n')"
    for A17_PAIR in "$A17_C2_REQ_FROM:$A17_C2_REQ_TO:queryRequiredResources" \
            "$A17_C2_GLB_FROM:$A17_C2_GLB_TO:queryGlobalResources"; do
        IFS=: read -r A17_FROM A17_TO A17_WHAT <<< "$A17_PAIR"
        if [[ "$A17_C2_HEX" == *"$A17_TO"* ]]; then
            LOG "  $A17_WHAT: already patched"
        elif [ "$(grep -o "$A17_FROM" <<< "$A17_C2_HEX" | wc -l)" = "1" ]; then
            HEX_PATCH "$A17_C2_64" "$A17_FROM" "$A17_TO" || ABORT "Codec2 $A17_WHAT patch failed"
            A17_C2_HEX="$(od -An -v -tx1 "$A17_C2_64" | tr -d ' \n')"
        else
            LOGW "Codec2 $A17_WHAT: pattern not found in this build, left at stock (video may fail to start)"
        fi
    done
fi
for A17_POLICY in "$WORK_DIR"/vendor/etc/seccomp_policy/*c2*policy*; do
    [ -f "$A17_POLICY" ] || continue
    if grep -q -x 'mremap: arg3 == 3' "$A17_POLICY"; then
        sed -i 's/^mremap: arg3 == 3$/mremap: arg3 == 3 || arg3 == MREMAP_MAYMOVE/' "$A17_POLICY"
        LOG "  ${A17_POLICY#"$WORK_DIR"/}: allowed MREMAP_MAYMOVE"
    fi
done
LOG_STEP_OUT

unset A17_ML_DIR A17_C2_64 A17_C2_REQ_FROM A17_C2_REQ_TO A17_C2_GLB_FROM A17_C2_GLB_TO
unset A17_C2_HEX A17_PAIR A17_FROM A17_TO A17_WHAT A17_POLICY
