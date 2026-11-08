# StellarRom logo on top of Settings > About phone > Software information.
# SecSettings is rebuilt for resources only (stock DEX kept byte-for-byte via
# the .code_stock marker read by scripts/apktool.sh) and added to the scoped
# ROM-key signature bridge so it keeps its platform identity.
if [[ "${TARGET_SETTINGS_LOGO:-false}" != "true" ]]; then
    return 0
fi
if [[ "${KEEP_SIGNED_APKS_STOCK:-false}" == "true" && "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    LOGW "Scoped platform rebuilds are off: SecSettings stays stock, no logo"
    return 0
fi

LOGO_SCAN="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/ScanPackageUtils.smali"
if ! grep -q '"com.samsung.android.sead"' "$LOGO_SCAN" 2> /dev/null; then
    LOGW "Scoped signature bridge not found in services.jar: SecSettings stays stock, no logo"
    return 0
fi

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || exit 1
LOGO_APK="$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
LOGO_XML="$LOGO_APK/res/xml/sec_software_info_settings.xml"
LOGO_MISSING=""
[ -f "$LOGO_XML" ] || LOGO_MISSING+=" res/xml/sec_software_info_settings.xml"
for LOGO_CLASS in com/android/settingslib/widget/LayoutPreference \
        com/samsung/android/settings/widget/SecInsetCategoryPreference \
        androidx/appcompat/widget/AppCompatImageView; do
    compgen -G "$LOGO_APK/smali*/$LOGO_CLASS.smali" > /dev/null || LOGO_MISSING+=" $LOGO_CLASS"
done
for LOGO_ATTR in roundedCornerColor colorPrimary tint tintMode; do
    grep -q "<attr name=\"$LOGO_ATTR\"" "$LOGO_APK/res/values/attrs.xml" 2> /dev/null || LOGO_MISSING+=" attr/$LOGO_ATTR"
done
if [ -n "$LOGO_MISSING" ]; then
    LOGW "SecSettings lacks:$LOGO_MISSING - keeping it stock, no logo"
    return 0
fi

LOG_STEP_IN "- Adding ROM logo to Software information"
mkdir -p "$LOGO_APK/res/drawable" "$LOGO_APK/res/layout"
cp -a "$MODPATH/res/drawable/rom_logo.png" "$LOGO_APK/res/drawable/rom_logo.png"
cat > "$LOGO_APK/res/layout/rom_logo.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout android:layout_width="fill_parent" android:background="?roundedCornerColor" android:layout_height="wrap_content" xmlns:android="http://schemas.android.com/apk/res/android" xmlns:app="http://schemas.android.com/apk/res-auto">
    <androidx.appcompat.widget.AppCompatImageView android:layout_width="fill_parent" android:layout_height="50.0dip" android:layout_gravity="center" android:src="@drawable/rom_logo" android:scaleType="centerInside" app:tint="?colorPrimary" app:tintMode="src_in" />
</FrameLayout>
EOF
python3 - "$LOGO_XML" "$LOGO_SCAN" <<'EOF'
import re
import sys

xml_path, smali_path = sys.argv[1:3]
xml = open(xml_path, encoding="utf-8").read()
if 'android:key="rom_logo"' not in xml:
    start = re.search(r"<PreferenceScreen\b[^>]*>", xml)
    if not start:
        sys.exit("PreferenceScreen not found in " + xml_path)
    xml = xml[:start.end()] + (
        '\n    <com.android.settingslib.widget.LayoutPreference android:layout="@layout/rom_logo"'
        ' android:selectable="false" android:key="rom_logo" />'
        "\n    <com.samsung.android.settings.widget.SecInsetCategoryPreference />") + xml[start.end():]
    open(xml_path, "w", encoding="utf-8").write(xml)

smali = open(smali_path, encoding="utf-8").read()
if '"com.android.settings"' not in smali:
    sead = smali.index('const-string v0, "com.samsung.android.sead"')
    goto = smali.index("    goto :cond_false\n", sead)
    smali = smali[:goto] + (
        '    const-string v0, "com.android.settings"\n\n'
        "    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n"
        "    move-result v0\n\n"
        "    if-nez v0, :cond_true\n\n") + smali[goto:]
    open(smali_path, "w", encoding="utf-8").write(smali)
EOF
touch "$(dirname "$LOGO_APK")/.$(basename "$LOGO_APK").code_stock"
LOG_STEP_OUT
unset LOGO_SCAN LOGO_APK LOGO_XML LOGO_MISSING LOGO_CLASS LOGO_ATTR
