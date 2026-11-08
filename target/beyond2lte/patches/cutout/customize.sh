# PUNCHHOLE_VI type:b2 makes SystemUI load punch_hole_ic_b2*.json. They only
# survive when SystemUI is rebuilt; otherwise fall back to the source's circle.
if [[ "${KEEP_SIGNED_APKS_STOCK:-false}" == "true" && \
        "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    LOGW "SystemUI stays stock (scoped rebuilds off): using circle punch hole VI"
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LOCKSCREEN_CONFIG_PUNCHHOLE_VI" \
        "face,pos:0.862:0.0286,size:0.2084:0.0571,type:circle"
else
    LOG_STEP_IN "- Adding S10+ (b2) punch hole assets to SystemUI"
    DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk" || exit 1
    mkdir -p "$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/assets"
    cp -a "$MODPATH/assets/"*.json "$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/assets/"
    LOG_STEP_OUT
fi

CUTOUT_CORNER="$(grep -o -P '(?<=<SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_CORNER_ROUND>)[^<]+' \
    "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" 2> /dev/null || true)"
if [ -n "$CUTOUT_CORNER" ]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_CORNER_ROUND" "$CUTOUT_CORNER"
fi
unset CUTOUT_CORNER
