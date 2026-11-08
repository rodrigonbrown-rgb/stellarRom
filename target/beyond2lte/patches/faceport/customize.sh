# crew: face unlock on One UI 9 with the S10 legacy face stack (based on facePort by Creeeeger)
#  - framework.jar: legacy com.samsung.android.bio.face + FaceManager -> SemBioFaceManager facade (ro.crew.legacy_face)
#  - system: faced + its libs, BioFaceService (signed with the ROM platform key), SELinux for faced / "samsung.face"
#  - keeps android.hardware.biometrics.face.xml (FaceManager must exist for Settings/BiometricSetting)
CREW_FP_SYS="$WORK_DIR/system/system"
CREW_FP_STAGE="$(mktemp -d)"

DECODE_APK "system" "system/framework/framework.jar" || exit 1
python3 "$MODPATH/faceport_fw.py" "$APKTOOL_DIR/system/framework/framework.jar" "$MODPATH/smali_add" "$WORK_DIR/system/system/framework/framework.jar" || exit 1
# crew: legacy bio/face package replaces One UI 9's stripped one -> stock members are removed by design,
# the lossless DEX inventory check can never pass for framework.jar (other jars stay checked)
echo "faceport: legacy com.samsung.android.bio.face replaces the stripped One UI 9 package (members removed by design)" \
    > "$APKTOOL_DIR/system/framework/.framework.jar.dex_exempt"

cp -a "$MODPATH/blobs/system/." "$CREW_FP_STAGE/"
# crew: One UI only installs system packages listed for a user type ("Package is not in allowed list")
mkdir -p "$CREW_FP_STAGE/etc/sysconfig"
printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<config>' '    <allowed-system-preload package="com.samsung.android.bio.face.service"/>' \
    '    <install-in-user-type package="com.samsung.android.bio.face.service">' \
    '        <install-in user-type="FULL" />' '        <install-in user-type="SYSTEM" />' '        <install-in user-type="PROFILE" />' \
    '    </install-in-user-type>' '</config>' \
    > "$CREW_FP_STAGE/etc/sysconfig/preinstalled-packages-com.samsung.android.bio.face.service.xml"
python3 "$MODPATH/faceport_libs.py" "$CREW_FP_STAGE" "$CREW_FP_SYS" || exit 1

echo "- faceport: adding faced, face libs, init + permissions"
install -D -m 0755 "$CREW_FP_STAGE/bin/faced" "$CREW_FP_SYS/bin/faced"
SET_METADATA "system" "system/bin/faced" 0 2000 755 "u:object_r:faced_exec:s0"
for CREW_F in $(cd "$CREW_FP_STAGE" && find lib64 -type f -name '*.so' | sort); do
    install -D -m 0644 "$CREW_FP_STAGE/$CREW_F" "$CREW_FP_SYS/$CREW_F"
    SET_METADATA "system" "system/$CREW_F" 0 0 644 "u:object_r:system_lib_file:s0"
done
for CREW_F in etc/init/faced.rc etc/permissions/biofaceservice.xml etc/sysconfig/preinstalled-packages-com.samsung.android.bio.face.service.xml; do
    install -D -m 0644 "$CREW_FP_STAGE/$CREW_F" "$CREW_FP_SYS/$CREW_F"
    SET_METADATA "system" "system/$CREW_F" 0 0 644 "u:object_r:system_file:s0"
done

# crew: dirs the ROM doesn't ship (lib64/hw) need their own fs_config/file_context entry or e2fsdroid fails
for CREW_D in $(cd "$CREW_FP_STAGE" && find bin lib64 etc -type d | sort); do
    grep -q "^system/$CREW_D " "$WORK_DIR/configs/fs_config-system" && \
        grep -q "^/system/$CREW_D " "$WORK_DIR/configs/file_context-system" && continue
    case "$CREW_D" in lib64*) CREW_L="system_lib_file" ;; *) CREW_L="system_file" ;; esac
    SET_METADATA "system" "system/$CREW_D" 0 0 755 "u:object_r:$CREW_L:s0"
done

# BioFaceService ships with its original Samsung platform signature (stock S10 firmware copy):
# android.uid.system is anchored to the stock framework-res cert, so it must not be re-signed.
CREW_FP_APK="priv-app/BioFaceService/BioFaceService.apk"
echo "- faceport: adding BioFaceService (original Samsung signature)"
install -D -m 0644 "$CREW_FP_STAGE/$CREW_FP_APK" "$CREW_FP_SYS/$CREW_FP_APK"
SET_METADATA "system" "system/priv-app/BioFaceService" 0 0 755 "u:object_r:system_file:s0"
SET_METADATA "system" "system/$CREW_FP_APK" 0 0 644 "u:object_r:system_file:s0"

# crew: BiometricSetting loads assets/punch_hole_ic_<type>.json from LOCKSCREEN_CONFIG_PUNCHHOLE_VI (type:b2 on S10+).
# Same S10+ files and same rebuild rule as the cutout module uses for SystemUI (else cutout switches the FF to circle).
CREW_CUT="$(dirname "$MODPATH")/cutout/assets"
if [[ "${KEEP_SIGNED_APKS_STOCK:-false}" == "true" && "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    echo "- faceport: BiometricSetting stays stock (cutout uses circle punch hole VI)"
elif ls "$CREW_CUT"/punch_hole_ic_b2*.json > /dev/null 2>&1; then
    echo "- faceport: adding S10+ (b2) punch hole assets to BiometricSetting"
    DECODE_APK "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" || exit 1
    mkdir -p "$APKTOOL_DIR/system/priv-app/BiometricSetting/BiometricSetting.apk/assets"
    cp -a "$CREW_CUT"/punch_hole_ic_b2*.json "$APKTOOL_DIR/system/priv-app/BiometricSetting/BiometricSetting.apk/assets/"
else
    echo "- faceport: WARNING no b2 punch hole assets in $CREW_CUT"
fi

python3 "$MODPATH/faceport_sepolicy.py" "$WORK_DIR" "$MODPATH/crew_face.cil" || exit 1
SET_PROP "system" "ro.crew.legacy_face" "true"
rm -rf "$CREW_FP_STAGE"
