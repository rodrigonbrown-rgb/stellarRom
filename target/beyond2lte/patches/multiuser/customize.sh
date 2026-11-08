DECODE_APK "system" "system/framework/framework.jar"
LOG_STEP_IN "- Enabling multi-user support (UN1CA)"
python3 - "$APKTOOL_DIR/system/framework/framework.jar" <<'PYEOF' || LOGW "MultiUserSupportsHelper not patched"
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
hits = list(root.glob("smali*/com/samsung/android/core/pm/multiuser/MultiUserSupportsHelper.smali"))
if not hits:
    print("      ! MultiUserSupportsHelper.smali not found"); sys.exit(1)
f = hits[0]; s = f.read_text(encoding="utf-8")
if "# crew: multiuser" in s:
    print(f"      = {f.relative_to(root)} (already)"); sys.exit(0)
m = re.search(r"^\.method static constructor[^\n]*<clinit>\(\)V\n(?P<b>.*?)^\.end method$", s, re.M | re.S)
if not m:
    print("      ! <clinit> not found"); sys.exit(1)
b = m.group("b")
sp = re.search(r"^(\s*)sput-boolean (v\d+), Lcom/samsung/android/core/pm/multiuser/MultiUserSupportsHelper;->IS_TABLET:Z$", b, re.M)
if not sp:
    print("      ! IS_TABLET store not found"); sys.exit(1)
ins = f"{sp.group(1)}# crew: multiuser (UN1CA)\n{sp.group(1)}const/4 {sp.group(2)}, 0x1\n\n"
b = b[:sp.start()] + ins + b[sp.start():]
f.write_text(s[:m.start("b")] + b + s[m.end("b"):], encoding="utf-8")
print(f"      + {f.relative_to(root)}: IS_TABLET forced true -> DEFAULT_MAX_USERS=8, enabled")
PYEOF
SET_PROP "system" "fw.max_users" "8"
SET_PROP "system" "fw.show_multiuserui" "1"
LOG_STEP_OUT
