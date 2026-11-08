SKIPUNZIP=1
# crew: KotlinRom (S9 One UI 9 on an Android 12 vendor) boot fixes, ported to the
# beyond2lte One UI 9 build. Every step is pattern-guarded: unknown inputs are
# logged and left at stock. Reproduces KotlinRom's patched files byte-for-byte.
#   1. sepolicy: drop netlink "nlmsg" xperm rules (kernel 6.x only) unless the
#      proven S23 FE 8.5 policy also carries them
#   2. libui: HIDL gralloc mapper gate (api_level > 35) -> SurfaceFlinger can map buffers
#   3. init: off the hardware watchdog
#   4. netbpfload/netd rc: a BPF failure can no longer hang (wait_for_prop) or loop the boot
#   5. CREW_BOOT_DEBUG=true (default): adb with root, no auth, from early boot

if [[ "${SOURCE_API_LEVEL:-0}" -lt 37 ]]; then
    LOG "- Source API ${SOURCE_API_LEVEL:-?} < 37, nothing to do"
    return 0
fi

LKC_SYS="$WORK_DIR/system/system"
LKC_TSV="$(dirname "$WORK_DIR")/crew_core_patched.tsv"
: > "$LKC_TSV"
LKC_ML_DIR="$FW_DIR/$(cut -d "/" -f 1 -s <<< "${MULTILIB_FIRMWARE:-}")_$(cut -d "/" -f 2 -s <<< "${MULTILIB_FIRMWARE:-}")"

LOG_STEP_IN "- sepolicy: netlink nlmsg extended permissions"
LKC_CILS="$(find "$LKC_SYS/etc/selinux" "$LKC_SYS/system_ext/etc/selinux" \
    "$WORK_DIR/system_ext/etc/selinux" "$WORK_DIR/product/etc/selinux" \
    -maxdepth 2 -name '*.cil' -type f 2>/dev/null | sort)"
LKC_PROVEN="$(find "$LKC_ML_DIR/system/system/etc/selinux" "$LKC_ML_DIR/system/system/system_ext/etc/selinux" \
    -maxdepth 2 -name '*.cil' -type f 2>/dev/null | sort)"
LKC_PROVEN_N=0
if [ -n "$LKC_PROVEN" ]; then
    # shellcheck disable=SC2086
    LKC_PROVEN_N="$(cat $LKC_PROVEN | grep -c -E '^\s*\((allowx|auditallowx|dontauditx|neverallowx)\s.*\(nlmsg\s' || true)"
fi
if [ -n "$LKC_PROVEN" ] && [ "$LKC_PROVEN_N" -gt 0 ]; then
    LOG "- proven 8.5 policy also has $LKC_PROVEN_N nlmsg rules (kernel supports them), kept"
elif [ -n "$LKC_CILS" ]; then
    # shellcheck disable=SC2086
    python3 "$MODPATH/crew_sepolicy_nlmsg.py" $LKC_CILS || ABORT "sepolicy nlmsg strip failed"
else
    LOGW "no system sepolicy cil found, skipped"
fi
LOG_STEP_OUT

LOG_STEP_IN "- libui: HIDL gralloc mapper gate"
if [ -f "$LKC_SYS/lib64/libui.so" ]; then
    LKC_R=0; python3 "$MODPATH/crew_libui_gate.py" "$LKC_SYS/lib64/libui.so" || LKC_R=$?
    case $LKC_R in
        0) printf 'lib64/libui.so\t%s\n' "$(sha256sum "$LKC_SYS/lib64/libui.so" | cut -d " " -f 1)" >> "$LKC_TSV" ;;
        3) ;;
        *) ABORT "libui gate patch failed" ;;
    esac
fi
LOG_STEP_OUT

LOG_STEP_IN "- init: hardware watchdog"
LKC_R=0; python3 "$MODPATH/crew_init_wdt.py" "$LKC_SYS/bin/init" || LKC_R=$?
case $LKC_R in
    0) printf 'bin/init\t%s\n' "$(sha256sum "$LKC_SYS/bin/init" | cut -d " " -f 1)" >> "$LKC_TSV" ;;
    3) ;;
    *) ABORT "init watchdog patch failed" ;;
esac
LOG_STEP_OUT

LOG_STEP_IN "- netbpfload/netd: no boot hang or zygote loop on BPF failure"
LKC_RC="$LKC_SYS/etc/init/netbpfload.rc"
if [ -f "$LKC_RC" ]; then
    sed -i -E \
        -e 's/^([[:space:]]*)wait_for_prop bpf\.progs_loaded 1[[:space:]]*$/\1# crew: no infinite wait if netbpfload fails\n\1#wait_for_prop bpf.progs_loaded 1/' \
        -e 's/^([[:space:]]*)reboot_on_failure reboot,netbpfload-missing[[:space:]]*$/\1#reboot_on_failure reboot,netbpfload-missing/' \
        "$LKC_RC"
    LOG "- $(grep -c '^[[:space:]]*#wait_for_prop bpf.progs_loaded\|^[[:space:]]*#reboot_on_failure reboot,netbpfload' "$LKC_RC") line(s) disabled in netbpfload.rc"
fi
LKC_RC="$LKC_SYS/etc/init/netd.rc"
if [ -f "$LKC_RC" ]; then
    sed -i -E 's/^([[:space:]]*)onrestart restart (zygote|zygote_secondary)[[:space:]]*$/\1# crew: netd crash must not take zygote down: onrestart restart \2/' "$LKC_RC"
    LOG "- $(grep -c '# crew: netd crash' "$LKC_RC") zygote restart(s) removed from netd.rc"
fi
LOG_STEP_OUT


LOG "- core files patched on purpose: $(cut -f1 "$LKC_TSV" | tr '\n' ' ')"
unset LKC_SYS LKC_TSV LKC_ML_DIR LKC_CILS LKC_PROVEN LKC_PROVEN_N LKC_RC LKC_R

# crew: legacy kernel: a failed netd1shot BPF self-test must not reboot the device
CREW_NETD_RC="$WORK_DIR/system/system/etc/init/netd.rc"
if [ -f "$CREW_NETD_RC" ] && grep -q '^[[:space:]]*reboot_on_failure reboot,netd1shot-fail' "$CREW_NETD_RC"; then
    sed -i 's|^\([[:space:]]*\)reboot_on_failure reboot,netd1shot-fail|\1# crew: legacy kernel: reboot_on_failure reboot,netd1shot-fail|' "$CREW_NETD_RC"
    LOG "- netd.rc: netd1shot reboot_on_failure disabled"
fi
unset CREW_NETD_RC

# crew: A17 ueventd only imports /vendor/etc/ueventd.rc (opened with O_NOFOLLOW); the legacy
# /vendor/ueventd.rc (Android 9 vendor) is ignored, leaving every vendor /dev node root 0600
# (tzdev -> TEEgris dies, init hangs at wait_for_prop vendor.tzdaemon Ready). The vendor image is
# full, so append the vendor rules to /system/etc/ueventd.rc (later rules win, like the import).
CREW_UEV_SYS="$WORK_DIR/system/system/etc/ueventd.rc"
if [ -f "$WORK_DIR/vendor/ueventd.rc" ] && ! grep -q '^# crew: vendor ueventd rules' "$CREW_UEV_SYS"; then
    rm -f "$WORK_DIR/vendor/etc/ueventd.rc"
    { printf '\n# crew: vendor ueventd rules (from /vendor/ueventd.rc)\n'; cat "$WORK_DIR/vendor/ueventd.rc"; } >> "$CREW_UEV_SYS"
    grep -q '^/dev/tzdev ' "$CREW_UEV_SYS" || ABORT "ueventd: vendor rules not appended"
    LOG "- system ueventd.rc: appended $(grep -c '^/' "$WORK_DIR/vendor/ueventd.rc") vendor rules"
fi
unset CREW_UEV_SYS

# crew: A17 plat policy dropped /dev/ion from file_contexts and most ion_device rules; the
# Android 12 vendor gralloc (allocator 2.0 / mapper 2.1) only has ION on 4.14 (no DMA-HEAP),
# so every allocation failed and RenderEngine aborted. Rules/contexts restored from 8.5.
CREW_SEP="$WORK_DIR/system/system/etc/selinux"
if ! grep -q '^;; crew ion$' "$CREW_SEP/plat_sepolicy.cil"; then
    { echo ";; crew ion"; cat "$MODPATH/crew_ion_rules.cil"; } >> "$CREW_SEP/plat_sepolicy.cil"
    cat "$MODPATH/crew_dev_fc.txt" >> "$CREW_SEP/plat_file_contexts"
    LOG "- sepolicy: $(grep -c . "$MODPATH/crew_ion_rules.cil") ion_device rules, $(grep -c . "$MODPATH/crew_dev_fc.txt") /dev contexts from 8.5"
fi
unset CREW_SEP

# crew: A17 plat policy lost most gpu_device / priv_app / platform_app rules the Android 12
# vendor relies on (GPU apps crash). Additive rules restored from 8.5, compile-tested at -c 31.
CREW_SEP="$WORK_DIR/system/system/etc/selinux"
if ! grep -q '^;; crew gaps$' "$CREW_SEP/plat_sepolicy.cil"; then
    { echo ";; crew gaps"; cat "$MODPATH/crew_gap_rules.cil"; } >> "$CREW_SEP/plat_sepolicy.cil"
    LOG "- sepolicy: $(grep -c . "$MODPATH/crew_gap_rules.cil") gpu/priv_app/platform_app rules from 8.5"
fi
unset CREW_SEP

# crew-usable-fixes
# Mali G76 + Android 12 vendor: HWUI Vulkan hits VK_ERROR_DEVICE_LOST (launcher crash) -> GL
SET_PROP "system" "ro.hwui.use_vulkan" "false"
SET_PROP "system" "debug.hwui.renderer" "skiagl"
# debug: RescueParty must not reboot the device while the port is being brought up
SET_PROP "system" "persist.sys.disable_rescue" "true"
# Environment Adaptive Display is unsupported on the S10 (NPE crash loop -> RescueParty reboot).
# The APK must stay (scoped platform APK, validator), so switch the feature off instead.
CREW_FF="$WORK_DIR/system/system/etc/floating_feature.xml"
if grep -q -E '<SEC_FLOATING_FEATURE_[A-Z_]*SUPPORT[A-Z_]*(ENVIRONMENT_ADAPTIVE_DISPLAY|_EAD)[A-Z_]*>' "$CREW_FF"; then
    sed -i -E 's#(<SEC_FLOATING_FEATURE_[A-Z_]*SUPPORT[A-Z_]*(ENVIRONMENT_ADAPTIVE_DISPLAY|_EAD)[A-Z_]*>)[^<]*#\1FALSE#g' "$CREW_FF"
    LOG "- floating feature: Environment Adaptive Display support off"
fi
unset CREW_FF
# Android 12 vendor serves Codec2 over HIDL only (plus OMX); A17 defaults to the AIDL Codec2 HAL and
# mediaserver waits forever for an AIDL IComponentStore -> every media call (wallpaper, FP enroll) hangs
SET_PROP "system" "media.c2.hal.selection" "hidl"

# crew-lib32-apex: the S10 vendor's 32-bit OMX/IVA services link /system/lib/libmedia.so, which needs
# 32-bit ICU (8.5 got it from its i18n APEX; A17's APEX is 64-bit only) and libminijail (S10 VNDK).
# Without them OMX never starts, mediaserver waits for IOmx, and every media call hangs (setup, wallpaper, FP enroll).
for CREW_L in libandroidicu.so libicuuc.so libicui18n.so libminijail.so; do
    if [ ! -e "$WORK_DIR/system/system/lib/$CREW_L" ]; then
        ADD_TO_WORK_DIR "$MODPATH" "system" "system/lib/$CREW_L" 0 0 644 "u:object_r:system_lib_file:s0" \
            || ABORT "Failed to add 32-bit $CREW_L"
    fi
done
LOG "- 32-bit media libs: ICU (8.5 i18n APEX) + libminijail (S10 VNDK) in /system/lib"
unset CREW_L
# record the crew-added 32-bit libs for the validator (accepted only with this exact hash)
CREW_TSV="$(dirname "$WORK_DIR")/crew_lib32_added.tsv"; : > "$CREW_TSV"
for CREW_L in libandroidicu.so libicuuc.so libicui18n.so libminijail.so; do
    if cmp -s "$MODPATH/system/lib/$CREW_L" "$WORK_DIR/system/system/lib/$CREW_L"; then
        printf '%s\t%s\n' "$CREW_L" "$(sha256sum "$WORK_DIR/system/system/lib/$CREW_L" | cut -d' ' -f1)" >> "$CREW_TSV"
    fi
done
unset CREW_TSV CREW_L

# crew-stune: A17 task_profiles only boost via uclamp; Singularity 4.14 EMS
# boosts via schedtune. Per-API files (loaded by first_api_level) mount
# /dev/stune and add a schedtune join next to every cpu-cgroup join.
LOG_STEP_IN "- crew: schedtune task profiles for 4.14 EMS"
CREW_STG="$(dirname "$WORK_DIR")/crew_stune"; rm -rf "$CREW_STG"; mkdir -p "$CREW_STG/system/etc/task_profiles" "$CREW_STG/system/etc/init"
CREW_APIS="28 29 30 31"  # libprocessgroup loads the one matching ro.product.first_api_level
python3 -I - "$WORK_DIR/system/system/etc/task_profiles.json" "$CREW_STG/system/etc/task_profiles" $CREW_APIS <<'PYEOF'
import json, sys, copy
src, out, apis = sys.argv[1], sys.argv[2], sys.argv[3:]
M = {"top-app": "top-app", "foreground": "foreground", "background": "background", "system-background": "background",
     "dex2oat": "background", "camera-daemon": "camera-daemon", "rt": "rt", "system": "", "": ""}
prof = []
for p in json.load(open(src)).get("Profiles", []):
    acts = p.get("Actions", [])
    cpu = [a for a in acts if a.get("Name") == "JoinCgroup" and a.get("Params", {}).get("Controller") == "cpu"]
    if not cpu or any(a.get("Params", {}).get("Controller") == "schedtune" for a in acts):
        continue
    path = cpu[0]["Params"].get("Path", "")
    if path not in M:
        continue
    q = copy.deepcopy(p)
    q["Actions"].append({"Name": "JoinCgroup", "Params": {"Controller": "schedtune", "Path": M[path]}})
    prof.append(q)
cg = {"Cgroups": [{"Controller": "schedtune", "Path": "/dev/stune", "Mode": "0755", "UID": "system", "GID": "system"}]}
for a in apis:
    json.dump({"Profiles": prof}, open(f"{out}/task_profiles_{a}.json", "w"), indent=2)
    json.dump(cg, open(f"{out}/cgroups_{a}.json", "w"), indent=2)
print("  stune profiles:", " ".join(p["Name"] for p in prof))
PYEOF
cat > "$CREW_STG/system/etc/init/crew_stune.rc" <<'RCEOF'
on init
    mkdir /dev/stune/top-app 0755 system system
    mkdir /dev/stune/foreground 0755 system system
    mkdir /dev/stune/background 0755 system system
    mkdir /dev/stune/rt 0755 system system
    mkdir /dev/stune/camera-daemon 0755 system system
on init
    mkdir /dev/cpuset/sf 0775 system system
    write /dev/cpuset/sf/cpus 0-7
    write /dev/cpuset/sf/mems 0
    chown system system /dev/cpuset/sf/tasks
    chown system system /dev/cpuset/sf/cgroup.procs
    chown system system /dev/cpuset/sf/cpus
    chmod 0664 /dev/cpuset/sf/tasks
    chmod 0664 /dev/cpuset/sf/cgroup.procs
    chmod 0664 /dev/cpuset/sf/cpus

on property:sys.boot_completed=1
    write /sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us 500
    write /sys/devices/system/cpu/cpufreq/policy6/schedutil/up_rate_limit_us 500
    write /dev/stune/top-app/schedtune.boost 10
    write /dev/stune/top-app/schedtune.prefer_perf 1
    write /dev/stune/top-app/schedtune.prefer_idle 1
    write /dev/stune/foreground/schedtune.prefer_idle 1
    write /dev/stune/foreground/schedtune.boost 10
    # crew: no cfq idle wait on UFS (faster app-launch I/O, keeps io priorities)
    write /sys/block/sda/queue/iosched/slice_idle 0
    write /sys/block/sda/queue/iosched/group_idle 0
    write /dev/stune/background/schedtune.boost 0
    write /sys/block/sda/queue/iostats 0
    write /sys/block/sda/queue/add_random 0
    write /sys/block/sda/queue/read_ahead_kb 128
    write /proc/sys/kernel/sched_schedstats 0
    write /proc/sys/vm/dirty_ratio 20
    write /proc/sys/vm/dirty_background_ratio 5
    write /proc/sys/vm/swappiness 100
    write /proc/sys/vm/vfs_cache_pressure 80
    write /sys/block/zram0/writeback_limit_enable 1
    write /sys/block/zram0/writeback_limit 0
    chmod 0444 /sys/block/zram0/writeback_limit_enable
    chmod 0444 /sys/block/zram0/writeback_limit
    chmod 0400 /sys/block/zram0/writeback
RCEOF
CREW_FC="$WORK_DIR/system/system/etc/selinux/plat_file_contexts"
CREW_L_TP="$(grep -E '^/system/etc/task_profiles/task_profiles_' "$CREW_FC" | awk '{print $NF}' | head -n 1)"; CREW_L_TP="${CREW_L_TP:-u:object_r:system_file:s0}"
CREW_L_CG="$(grep -E '^/system/etc/task_profiles/cgroups_' "$CREW_FC" | awk '{print $NF}' | head -n 1)"; CREW_L_CG="${CREW_L_CG:-u:object_r:system_file:s0}"
for a in $CREW_APIS; do
    ADD_TO_WORK_DIR "$CREW_STG" "system" "system/etc/task_profiles/task_profiles_$a.json" 0 0 644 "$CREW_L_TP"
    ADD_TO_WORK_DIR "$CREW_STG" "system" "system/etc/task_profiles/cgroups_$a.json" 0 0 644 "$CREW_L_CG"
done
ADD_TO_WORK_DIR "$CREW_STG" "system" "system/etc/init/crew_stune.rc" 0 0 644 "u:object_r:system_file:s0"
for CF in $(find "$WORK_DIR/configs" -maxdepth 1 -type f -name '*-system' 2> /dev/null); do  # crew-stune-dir
    grep -q -E 'system\\?/etc\\?/task_profiles\s' "$CF" && continue
    CREW_DL="$(sed -n -E 's#^(\S*system\\?/etc\\?/)init(\s)#\1task_profiles\2#p' "$CF" | head -n 1)"
    [ -n "$CREW_DL" ] && echo "$CREW_DL" >> "$CF" && LOG "- task_profiles dir entry -> ${CF##*/}: $CREW_DL"
done
unset CF CREW_DL
SET_PROP "product" "ro.hwui.use_vulkan" "false"
SET_PROP "product" "debug.sf.show_refresh_rate_overlay_render_rate" "false"
LOG "- stune api files: $CREW_APIS (labels $CREW_L_TP / $CREW_L_CG)"
for f in $(find "$WORK_DIR" -maxdepth 4 -name '*.prop'); do
    sed -i -e '/^debug.sf.show_refresh_rate_overlay_render_rate=/d' -e '/^ro.hwui.use_vulkan=true$/d' -e '/^ro.hwui.use_vulkan=$/d' "$f"
done
unset CREW_STG CREW_APIS CREW_FC CREW_L_TP CREW_L_CG f a
LOG_STEP_OUT

# crew-ui-perf: SystemUI smoothness on Mali G76 (GL RenderEngine, triple
# buffering, UI processes compiled with speed). Blur look untouched.
LOG_STEP_IN "- crew: UI perf props (GL RenderEngine, speed filters)"
SET_PROP "product" "debug.renderengine.backend" "skiaglthreaded"
SET_PROP "product" "ro.surface_flinger.max_frame_buffer_acquired_buffers" "3"
SET_PROP "product" "dalvik.vm.systemuicompilerfilter" "speed"
SET_PROP "product" "dalvik.vm.systemservercompilerfilter" "speed"
SET_PROP "product" "pm.dexopt.shared" "speed"
LOG_STEP_OUT

# crew-sead-off: sead (Environment Adaptive Display) is persistent and crashes
# in onCreate (getWhiteRGBOffsetArray: split() on null, no S10 panel RGB
# calibration) -> respawn loop ~10/s = lag + heat. Ship it disabled in its
# manifest (= pm disable at build time); APK stays for the validator.
LOG_STEP_IN "- crew: disable sead (EAD crash loop)"
CREW_SM="$(grep -rl 'package="com.samsung.android.sead"' "$APKTOOL_DIR" --include=AndroidManifest.xml 2> /dev/null | head -n 1)"
if [ -z "$CREW_SM" ] && type DECODE_APK > /dev/null 2>&1; then
    CREW_SA="$(find "$WORK_DIR/system/system/priv-app" "$WORK_DIR/system/system/app" -name '*.apk' 2> /dev/null | while read -r a; do unzip -p "$a" AndroidManifest.xml 2> /dev/null | grep -a -q 'c.o.m...s.a.m.s.u.n.g...a.n.d.r.o.i.d...s.e.a.d\|com.samsung.android.sead' && echo "$a" && break; done)"
    [ -n "$CREW_SA" ] && DECODE_APK "system" "${CREW_SA#"$WORK_DIR"/system/}"
    CREW_SM="$(grep -rl 'package="com.samsung.android.sead"' "$APKTOOL_DIR" --include=AndroidManifest.xml 2> /dev/null | head -n 1)"
fi
if [ -n "$CREW_SM" ]; then
    python3 -I - "$CREW_SM" <<'PYEOF' || LOGW "sead manifest edit failed"
import re, sys
f = sys.argv[1]; s = open(f).read()
m = re.search(r'<application\b[^>]*>', s)
if not m: sys.exit("no <application>")
tag = m.group(0); new = tag
new = re.sub(r'android:persistent="true"', 'android:persistent="false"', new)
if 'android:enabled=' in new: new = re.sub(r'android:enabled="[^"]*"', 'android:enabled="false"', new)
else: new = new.replace('<application', '<application android:enabled="false"', 1)
s = s.replace(tag, new, 1); open(f, 'w').write(s)
print("  sead: application enabled=false, persistent=false")
PYEOF
else
    LOGW "sead manifest not found/decodable - stays enabled"
fi
unset CREW_SM CREW_SA
LOG_STEP_OUT

# crew-perf2: no tracing daemons in release (no visual change)
LOG_STEP_IN "- crew: perf2 props"
SET_PROP "product" "persist.traced.enable" "0"
SET_PROP "product" "persist.traced_perf.enable" "0"
LOG_STEP_OUT

# crew-uptime (+ RAM Plus writeback off in crew_stune.rc): slowdown that builds up over hours = swap thrash on 8 GB.
# lmkd kills cached apps earlier under real thrash instead of crawling.
LOG_STEP_IN "- crew: lmkd anti-thrash props"
SET_PROP "product" "ro.lmk.use_psi" "true"
SET_PROP "product" "ro.lmk.thrashing_limit" "30"
SET_PROP "product" "ro.lmk.thrashing_limit_decay" "50"
SET_PROP "product" "ro.lmk.swap_free_low_percentage" "15"
SET_PROP "product" "ro.lmk.psi_partial_stall_ms" "70"
SET_PROP "product" "ro.lmk.psi_complete_stall_ms" "500"
LOG_STEP_OUT

# crew-gpis-sf: Samsung GPIS boost pins SurfaceFlinger to cores 4-7 during blur;
# on 9820 that stutters. Keep the sf cpuset (no EACCES) but leave SF on 0-7.
if [ -f "$WORK_DIR/system/system/etc/task_profiles.json" ]; then
python3 - "$WORK_DIR/system/system/etc/task_profiles.json" <<'CREWEOF'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); n=0
for pr in d.get("Profiles",[]):
    if pr.get("Name")=="GpisSfCpusetEnable":
        for a in pr.get("Actions",[]):
            if a.get("Params",{}).get("Name")=="GpisSfCpuset":
                a["Params"]["Value"]="0-7"; n+=1
json.dump(d,open(p,"w"),indent=2)
print("  GpisSfCpusetEnable -> 0-7:",n)
CREWEOF
fi

# crew-smooth: SF tweaks used by 9820 ports (ExtremeROM); no visual change.
LOG_STEP_IN "- crew-smooth: SurfaceFlinger tweaks"
SET_PROP "vendor" "debug.sf.latch_unsignaled" "1"
SET_PROP "vendor" "debug.sf.high_fps_late_app_phase_offset_ns" "0"
SET_PROP "vendor" "debug.sf.high_fps_late_sf_phase_offset_ns" "0"
SET_PROP "vendor" "ro.surface_flinger.use_content_detection_for_refresh_rate" "false"
SET_PROP "vendor" "ro.surface_flinger.enable_frame_rate_override" "false"
SET_PROP "vendor" "ro.surface_flinger.game_default_frame_rate_override" "60"
SET_PROP "vendor" "debug.hwui.use_hint_manager" "true"
LOG_STEP_OUT

# crew-dexopt: compile preinstalled apps (launcher etc.) at first boot / dirty flash
# instead of leaving them on "verify" until idle maintenance.
LOG_STEP_IN "- crew-dexopt: first-boot compile"
SET_PROP "product" "pm.dexopt.first-boot" "speed-profile"
SET_PROP "product" "pm.dexopt.boot-after-ota" "speed-profile"
SET_PROP "product" "pm.dexopt.boot-after-mainline-update" "speed-profile"
LOG_STEP_OUT

# crew-vds-jsqz: screen recording composed by HWC (smoother), camera JPEG squeezer node access
LOG_STEP_IN "- crew: HWC virtual display + /dev/jsqz"
SET_PROP "vendor" "debug.sf.enable_hwc_vds" "1"
grep -q '^/dev/jsqz' "$WORK_DIR/vendor/ueventd.rc" || \
    echo "/dev/jsqz                 0660   mediacodec     camera" >> "$WORK_DIR/vendor/ueventd.rc"
LOG_STEP_OUT
