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
