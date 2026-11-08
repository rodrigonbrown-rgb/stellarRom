AS_DIR="$APKTOOL_DIR/system/framework/framework.jar"
AS_MARK="$APKTOOL_DIR/system/framework/.framework.jar.dex_autoallow"
AS_TSV="$SRC_DIR/scripts/internal/dex_allowed_additions/system/system/framework/framework.jar.tsv"
rm -f "$AS_MARK" "$AS_TSV"
DECODE_APK "system" "system/framework/framework.jar"
LOG_STEP_IN "- Per-app S24 Ultra spoof (Galaxy Store, Good Lock)"
if python3 "$MODPATH/port_appspoof.py" "$AS_DIR" "$AS_MARK" "$WORK_DIR/system/system/framework/framework.jar" "$APKTOOL_DIR/system/framework/.framework.jar.dex_cache/logical_dex_map.tsv"; then
    LOG "- Extended framework.jar DEX: $(tr '\n' ' ' < "$AS_MARK")"
else
    rm -f "$AS_MARK"
    LOGW "App spoof port failed, framework.jar unchanged (see above)"
fi
LOG_STEP_OUT
unset AS_DIR AS_MARK AS_TSV
