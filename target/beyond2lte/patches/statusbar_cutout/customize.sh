SB_DIR="$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk"
SB_MARK="$APKTOOL_DIR/system_ext/priv-app/SystemUI/.SystemUI.apk.dex_autoallow"
SB_TSV="$SRC_DIR/scripts/internal/dex_allowed_additions/system_ext/priv-app/SystemUI/SystemUI.apk.tsv"
rm -f "$SB_MARK" "$SB_TSV"
if [[ "${KEEP_SIGNED_APKS_STOCK:-false}" == "true" && "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    LOGW "Scoped platform rebuilds are off: SystemUI stays stock, no status bar cutout fix"
else
    DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk"
    LOG_STEP_IN "- Right punch-hole status bar padding"
    if python3 "$MODPATH/port_statusbar_cutout.py" "$SB_DIR" "$SB_MARK"; then
        LOG "- Extended SystemUI DEX: $(tr '\n' ' ' < "$SB_MARK")"
    else
        rm -f "$SB_MARK"
        LOGW "Status bar cutout port failed, SystemUI keeps stock padding (see above)"
    fi
    LOG_STEP_OUT
    # crew: lockscreen carrier text width + no marquee (right punch hole)
    LOG_STEP_IN "- Lockscreen carrier text: full left width, ellipsis instead of marquee"
    if python3 "$MODPATH/port_keyguard_carrier.py" "$SB_DIR" "$SB_MARK"; then
        LOG "- Extended SystemUI DEX: $(tr '\n' ' ' < "$SB_MARK")"
    else
        LOGW "Lockscreen carrier text fix failed, kept stock (see above)"
    fi
    LOG_STEP_OUT
fi
unset SB_DIR SB_MARK SB_TSV
