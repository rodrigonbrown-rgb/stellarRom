DECODE_APK "system" "system/framework/framework.jar"
LOG_STEP_IN "- Screenshot chord: AOSP path (side-key rune off)"
python3 - "$APKTOOL_DIR/system/framework/framework.jar" <<'PYEOF' || LOGW "InputRune not patched, screenshot chord unchanged"
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
hits = list(root.glob("smali*/com/samsung/android/rune/InputRune.smali"))
if not hits:
    print("      ! InputRune.smali not found"); sys.exit(1)
f = hits[0]; s = f.read_text(encoding="utf-8")
FIELD = "Lcom/samsung/android/rune/InputRune;->PWM_KEY_COMBINATION_SCREENSHOT_SIDE_KEY:Z"
if "# crew: screenshot chord" in s:
    print(f"      = {f.relative_to(root)} (already)"); sys.exit(0)
m = re.search(r"^\.method static constructor[^\n]*<clinit>\(\)V\n(?P<b>.*?)^\.end method$", s, re.M | re.S)
if not m or f"sput-boolean" not in m.group("b") or FIELD not in m.group("b"):
    print("      ! <clinit> does not set PWM_KEY_COMBINATION_SCREENSHOT_SIDE_KEY"); sys.exit(1)
b = m.group("b")
rets = [x for x in re.finditer(r"^(\s*)return-void\s*$", b, re.M)]
if not rets:
    print("      ! no return-void in <clinit>"); sys.exit(1)
r = rets[-1]
ins = (f"{r.group(1)}# crew: screenshot chord -> AOSP path\n"
       f"{r.group(1)}const/4 v0, 0x0\n\n{r.group(1)}sput-boolean v0, {FIELD}\n\n")
b = b[:r.start()] + ins + b[r.start():]
f.write_text(s[:m.start("b")] + b + s[m.end("b"):], encoding="utf-8")
print(f"      + {f.relative_to(root)}: SCREENSHOT_SIDE_KEY forced false at end of <clinit>")
PYEOF
LOG_STEP_OUT
