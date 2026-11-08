#!/usr/bin/env python3
# Per-app device spoof in framework.jar: selected packages see an S24 Ultra in
# android.os.Build (MODEL/DEVICE/PRODUCT) and in SystemProperties.get() for
# ro.product.*.model/.device/.name. Every other process is untouched.
import re, shutil, subprocess, sys, tempfile
from pathlib import Path

CLS = "Lcom/android/internal/util/crew/CrewSpoof;"
MODEL, DEVICE, PRODUCT = "SM-S928B", "e3q", "e3qxxx"
PKGS = ["com.sec.android.app.samsungapps", "com.samsung.android.goodlock"]

backups = {}
def die(m):
    # never leave a half-applied hook behind (a hook without CrewSpoof = bootloop)
    for path, old in backups.items():
        path.write_text(old, encoding="utf-8")
    print("  ! " + m + ("  (reverted)" if backups else "")); sys.exit(2)

root = Path(sys.argv[1]); out_list = Path(sys.argv[2])
src_jar = Path(sys.argv[3]) if len(sys.argv) > 3 else None
dex_map = Path(sys.argv[4]) if len(sys.argv) > 4 else None
LIMIT = 65536          # dex method/field/type id limit
MARGIN = 24            # headroom we require after our additions
dirs = sorted(d for d in root.iterdir() if d.is_dir() and d.name.startswith("smali"))
def find(rel):
    for d in dirs:
        f = d / rel
        if f.is_file():
            return d, f
    return None, None

d_ins, f_ins = find("android/app/Instrumentation.smali")
d_sp, f_sp = find("android/os/SystemProperties.smali")
d_ssp, f_ssp = find("com/samsung/android/os/SemSystemProperties.smali")
if not f_ins:
    die("Instrumentation not found in framework.jar")

# Per-dex id usage (methods/fields/types) from the stock jar, so we never
# push a nearly-full dex over the 64K reference limit.
usage = {}
if src_jar and dex_map and src_jar.is_file() and dex_map.is_file() and shutil.which("baksmali"):
    for line in dex_map.read_text().splitlines()[1:]:
        f = line.split("\t")
        if len(f) != 4:
            continue
        counts = {}
        for kind in ("methods", "fields", "types"):
            r = subprocess.run(["baksmali", "list", kind, f"{src_jar}/{f[1]}"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            counts[kind] = len([l for l in r.stdout.splitlines() if l.strip()]) if r.returncode == 0 else LIMIT
        usage[f[2]] = counts
if not usage:
    die("cannot measure dex usage (baksmali/map/jar missing), skipping spoof to stay safe")
def room(d, methods, fields=0, types=0):
    u = usage.get(d.name)
    return bool(u) and u["methods"] + methods + MARGIN <= LIMIT and \
        u["fields"] + fields + MARGIN <= LIMIT and u["types"] + types + MARGIN <= LIMIT
for d in dirs:
    if d.name in usage:
        u = usage[d.name]; print(f"      {d.name}: methods={u['methods']} fields={u['fields']} types={u['types']}")
existing = next((d / "com/android/internal/util/crew/CrewSpoof.smali" for d in dirs
                 if (d / "com/android/internal/util/crew/CrewSpoof.smali").is_file()), None)

def pkg_checks():
    s = ""
    for p in PKGS:
        s += f'''    const-string v0, "{p}"

    invoke-virtual {{v0, p0}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-nez v0, :yes

'''
    return s

def prop_case(suffix, value, nxt):
    return f'''    const-string v0, "{suffix}"

    invoke-virtual {{p0, v0}}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z

    move-result v1

    if-eqz v1, :{nxt}

    const-string v0, "{value}"

    return-object v0

    :{nxt}
'''

CLASS_SMALI = f'''.class public final {CLS}
.super Ljava/lang/Object;
.source "CrewSpoof.java"


# static fields
.field private static volatile sActive:Z


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {{p0}}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method private static isTarget(Ljava/lang/String;)Z
    .locals 1

    if-nez p0, :check

    const/4 v0, 0x0

    return v0

    :check
{pkg_checks()}    const/4 v0, 0x0

    return v0

    :yes
    const/4 v0, 0x1

    return v0
.end method

.method private static setField(Ljava/lang/String;Ljava/lang/String;)V
    .locals 2

    :try_start_0
    const-class v0, Landroid/os/Build;

    invoke-virtual {{v0, p0}}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;

    move-result-object v0

    const/4 v1, 0x1

    invoke-virtual {{v0, v1}}, Ljava/lang/reflect/Field;->setAccessible(Z)V

    const/4 v1, 0x0

    invoke-virtual {{v0, v1, p1}}, Ljava/lang/reflect/Field;->set(Ljava/lang/Object;Ljava/lang/Object;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {{:try_start_0 .. :try_end_0}} :catch_0

    return-void

    :catch_0
    move-exception v0

    return-void
.end method

.method public static apply(Landroid/content/Context;)V
    .locals 2

    if-nez p0, :has_ctx

    return-void

    :has_ctx
    :try_start_0
    invoke-virtual {{p0}}, Landroid/content/Context;->getPackageName()Ljava/lang/String;

    move-result-object v0
    :try_end_0
    .catch Ljava/lang/Throwable; {{:try_start_0 .. :try_end_0}} :catch_0

    invoke-static {{v0}}, {CLS}->isTarget(Ljava/lang/String;)Z

    move-result v1

    if-nez v1, :spoof

    return-void

    :spoof
    const/4 v1, 0x1

    sput-boolean v1, {CLS}->sActive:Z

    const-string v0, "MODEL"

    const-string v1, "{MODEL}"

    invoke-static {{v0, v1}}, {CLS}->setField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "DEVICE"

    const-string v1, "{DEVICE}"

    invoke-static {{v0, v1}}, {CLS}->setField(Ljava/lang/String;Ljava/lang/String;)V

    const-string v0, "PRODUCT"

    const-string v1, "{PRODUCT}"

    invoke-static {{v0, v1}}, {CLS}->setField(Ljava/lang/String;Ljava/lang/String;)V

    return-void

    :catch_0
    move-exception v0

    return-void
.end method

.method public static prop(Ljava/lang/String;)Ljava/lang/String;
    .locals 2

    sget-boolean v0, {CLS}->sActive:Z

    if-eqz v0, :none

    if-eqz p0, :none

    const-string v0, "ro.product."

    invoke-virtual {{p0, v0}}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v1

    if-eqz v1, :none

{prop_case(".model", MODEL, "not_model")}{prop_case(".device", DEVICE, "not_device")}{prop_case(".name", PRODUCT, "none")}    const/4 v0, 0x0

    return-object v0
.end method
'''

def inject(text, sig_re, code_fn, maxlocals):
    """Insert code at the first instruction of one method; per-method idempotent.
    sig_re may be preceded by hidden-API flags (whitelist, blacklist, core-platform-api...)."""
    m = re.search(r"^\.method " + sig_re + r"\n(?P<body>.*?)^\.end method$", text, re.M | re.S)
    if not m:
        return None
    body = m.group("body")
    if "# crew: appspoof" in body:
        return text
    lm = re.search(r"^(\s*)\.locals (\d+)\n", body, re.M)
    if not lm or int(lm.group(2)) > maxlocals:
        return None
    n = int(lm.group(2))
    new_locals, code = code_fn(n)
    lines = body[lm.end():].split("\n")
    i = 0
    while i < len(lines):
        t = lines[i].strip()
        if t == "":
            i += 1; continue
        if t.startswith(".annotation"):
            while i < len(lines) and lines[i].strip() != ".end annotation":
                i += 1
            i += 1; continue
        if t.startswith(".param"):
            if i + 1 < len(lines) and lines[i + 1].strip().startswith(".annotation"):
                while i < len(lines) and lines[i].strip() != ".end param":
                    i += 1
            i += 1; continue
        break
    head = body[:lm.start()] + f"{lm.group(1)}.locals {new_locals}\n" + "\n".join(lines[:i])
    tail = "\n".join(lines[i:])
    nb = head + ("\n" if head and not head.endswith("\n") else "") + "\n    # crew: appspoof\n" + code + tail
    return text[:m.start("body")] + nb + text[m.end("body"):]

def write(path, text):
    backups.setdefault(path, path.read_text(encoding="utf-8"))
    path.write_text(text, encoding="utf-8")

added = {}   # dex name -> extra method refs we introduce (each hook adds 1 method + 1 type)
def reserve(d):
    n = added.get(d.name, 0)
    if n == 0 and not room(d, 1, 0, 1):
        return False
    added[d.name] = n + 1
    return True

# Instrumentation.newApplication(ClassLoader, String, Context): p3 = context  (required)
if not reserve(d_ins):
    die(f"{d_ins.name} (Instrumentation) is full, cannot hook newApplication")
t = inject(f_ins.read_text(encoding="utf-8"),
    r"public (?:[a-z-]+ )*newApplication\(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;\)Landroid/app/Application;",
    lambda n: (n, f"    invoke-static {{p3}}, {CLS}->apply(Landroid/content/Context;)V\n\n"), 12)
if t is None:
    die("Instrumentation.newApplication(ClassLoader,String,Context) not found / unexpected")
write(f_ins, t)

# Property getters (optional, each only if its dex has room): p0 = key
PROP_HOOK = lambda n: (n + 1,
    f"    invoke-static {{p0}}, {CLS}->prop(Ljava/lang/String;)Ljava/lang/String;\n\n"
    f"    move-result-object v{n}\n\n    if-eqz v{n}, :crew_sp_orig\n\n    return-object v{n}\n\n    :crew_sp_orig\n")
GETTERS = (r"public static (?:[a-z-]+ )*get\(Ljava/lang/String;\)Ljava/lang/String;",
           r"public static (?:[a-z-]+ )*get\(Ljava/lang/String;Ljava/lang/String;\)Ljava/lang/String;")
hooked = []
for label, d, f in (("SystemProperties", d_sp, f_sp), ("SemSystemProperties", d_ssp, f_ssp)):
    if not f:
        print(f"      - {label}: not in framework.jar"); continue
    if not reserve(d):
        print(f"      - {label}: {d.name} is full, not hooked (Build fields still spoofed)"); continue
    t = f.read_text(encoding="utf-8"); ok = 0
    for sig in GETTERS:
        r = inject(t, sig, PROP_HOOK, 12)
        if r is not None:
            t = r; ok += 1
    if ok:
        write(f, t); hooked.append((label, d, f))
    else:
        added[d.name] -= 1
        print(f"      - {label}: get() not found, skipped")

# new class: reuse, else the dex with the most free method ids
if existing:
    d_cls = existing.parents[5]
else:
    cands = [d for d in dirs if room(d, 16, 2, 12)]
    if not cands:
        die("no framework dex has room for CrewSpoof")
    d_cls = min(cands, key=lambda d: usage[d.name]["methods"])
    dst = d_cls / "com/android/internal/util/crew/CrewSpoof.smali"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(CLASS_SMALI, encoding="utf-8")
    existing = dst

files = [f_ins, existing] + [f for _, _, f in hooked]
if shutil.which("smali"):
    with tempfile.TemporaryDirectory() as t:
        r = subprocess.run(["smali", "a", "-a", "34", "-o", f"{t}/t.dex"] + [str(f) for f in files],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if r.returncode != 0:
            for p, old in backups.items():
                p.write_text(old, encoding="utf-8")
            if existing.is_file() and "CrewSpoof" in existing.name and existing not in backups:
                existing.unlink()
            die("smali check failed, reverted:\n" + r.stdout[-3000:])

dex_touched = {d_ins.name, d_cls.name} | {d.name for _, d, _ in hooked}
out_list.write_text("".join(sorted(x + "\n" for x in dex_touched)), encoding="utf-8")
print(f"  + Instrumentation ({d_ins.name}), CrewSpoof ({d_cls.name}), props: "
      + (", ".join(f"{l} ({d.name})" for l, d, _ in hooked) or "none"))
print(f"  + spoof {MODEL}/{DEVICE}/{PRODUCT} for: {', '.join(PKGS)}")
