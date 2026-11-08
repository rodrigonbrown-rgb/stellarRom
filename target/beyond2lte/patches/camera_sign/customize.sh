[[ "${TARGET_CAMERA_ROM_SIGNED:-false}" == "true" ]] || return 0

CAM="$WORK_DIR/system/system/priv-app/SamsungCamera/SamsungCamera.apk"
CAM_SCAN="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/ScanPackageUtils.smali"
[ -f "$CAM" ] || ABORT "SamsungCamera.apk not found in work dir" || exit 1
grep -q '"com.samsung.android.sead"' "$CAM_SCAN" 2> /dev/null || \
    ABORT "Scoped signature bridge missing in services.jar; cannot trust a ROM-signed camera" || exit 1

LOG_STEP_IN "- Re-signing SamsungCamera with the ROM platform key"
CAM_CERT="aosp"
$ROM_IS_OFFICIAL && CAM_CERT="impulse"
mkdir -p "$TMP_DIR"
CAM_TMP="$(mktemp -d "$TMP_DIR/camera_sign.XXXXXX")"
cp -a "$CAM" "$CAM_TMP/in.apk"
zip -q -d "$CAM_TMP/in.apk" "META-INF/MANIFEST.MF" "META-INF/*.SF" "META-INF/*.RSA" "META-INF/*.DSA" "META-INF/*.EC" > /dev/null 2>&1 || true
if unzip -l "$CAM_TMP/in.apk" | grep -qE 'META-INF/(MANIFEST\.MF|[^/]*\.(SF|RSA))$'; then
    ABORT "Could not strip the old SamsungCamera signature" || exit 1
fi
EVAL "signapk \"$SRC_DIR/security/${CAM_CERT}_platform.x509.pem\" \"$SRC_DIR/security/${CAM_CERT}_platform.pk8\" \"$CAM_TMP/in.apk\" \"$CAM_TMP/out.apk\"" || exit 1
mv -f "$CAM_TMP/out.apk" "$CAM"
rm -rf "$CAM_TMP"

# Already final: skip apktool's decode/rebuild of the camera.
: # crew-cam9 off: rm -rf "$APKTOOL_DIR/system/priv-app/SamsungCamera/SamsungCamera.apk"

python3 - "$CAM_SCAN" <<'PYEOF'
import sys
path = sys.argv[1]
smali = open(path, encoding="utf-8").read()
if '"com.sec.android.app.camera"' not in smali:
    sead = smali.index('const-string v0, "com.samsung.android.sead"')
    goto = smali.index("    goto :cond_false\n", sead)
    smali = smali[:goto] + (
        '    const-string v0, "com.sec.android.app.camera"\n\n'
        "    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n"
        "    move-result v0\n\n"
        "    if-nez v0, :cond_true\n\n") + smali[goto:]
    open(path, "w", encoding="utf-8").write(smali)
PYEOF
LOG_STEP_OUT
unset CAM CAM_SCAN CAM_CERT CAM_TMP
