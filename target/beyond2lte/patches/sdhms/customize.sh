SD_SCAN="$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/pm/ScanPackageUtils.smali"
SD_APK="$APKTOOL_DIR/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk"
if [[ "${KEEP_SIGNED_APKS_STOCK:-false}" == "true" && "${ENABLE_SCOPED_PLATFORM_APK_REBUILDS:-false}" != "true" ]]; then
    LOGW "Scoped platform rebuilds are off: SDHMS stays stock"
elif ! grep -q '"com.samsung.android.sead"' "$SD_SCAN" 2> /dev/null; then
    LOGW "Scoped signature bridge not found in services.jar: SDHMS stays stock"
elif [ ! -f "$WORK_DIR/system/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk" ]; then
    LOGW "SDHMS not present in source"
else
    DECODE_APK "system" "system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk"
    LOG_STEP_IN "- Disabling the SSRM Warning dialog"
    python3 - "$SD_APK" "$SD_SCAN" <<'PYEOF' || LOGW "SSRM dialog method not found, SDHMS stays stock"
import pathlib, re, sys
apk, scan = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
patched = 0
for f in apk.glob("smali*/**/*.smali"):
    s = f.read_text(encoding="utf-8")
    if '"SSRM Warning"' not in s:
        continue
    out, pos = [], 0
    for m in re.finditer(r"^\.method [^\n]*\)V\n.*?^\.end method\n", s, re.M | re.S):
        body = m.group(0)
        if '"SSRM Warning"' in body and "# crew: ssrm" not in body:
            lm = re.search(r"^(\s*)\.locals \d+\n", body, re.M)
            if lm:
                body = body[:lm.end()] + "\n    # crew: ssrm warning disabled\n    return-void\n" + body[lm.end():]
                patched += 1
        elif "# crew: ssrm" in body:
            patched += 1
        out.append(s[pos:m.start()]); out.append(body); pos = m.end()
    out.append(s[pos:])
    f.write_text("".join(out), encoding="utf-8")
    print(f"      {f.relative_to(apk)}")
if not patched:
    sys.exit(1)
t = scan.read_text(encoding="utf-8")
if '"com.sec.android.sdhms"' not in t:
    sead = t.index('const-string v0, "com.samsung.android.sead"')
    goto = t.index("    goto :cond_false\n", sead)
    t = t[:goto] + ('    const-string v0, "com.sec.android.sdhms"\n\n'
        "    invoke-virtual {v0, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\n\n"
        "    move-result v0\n\n"
        "    if-nez v0, :cond_true\n\n") + t[goto:]
    scan.write_text(t, encoding="utf-8")
print(f"      {patched} alert method(s) disabled, com.sec.android.sdhms added to the scoped bridge")
PYEOF
    LOG_STEP_OUT
fi
unset SD_SCAN SD_APK
