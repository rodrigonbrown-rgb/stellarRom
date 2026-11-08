LOG "- Disabling persistent logcat (constant /data writes)"
for PF_P in persist.logd.logpersistd persist.logd.logpersistd.buffer persist.logd.logpersistd.size persist.logd.size; do
    SET_PROP "system" "$PF_P" --delete
done
SET_PROP "system" "dalvik.vm.systemuicompilerfilter" "speed"
unset PF_P
LOG "- Compiler tuning for smoother UI (system_server speed, 9820 dex2oat threads)"
SET_PROP "system" "dalvik.vm.systemservercompilerfilter" "speed"
SET_PROP "system" "dalvik.vm.dex2oat-threads" "6"
SET_PROP "system" "dalvik.vm.boot-dex2oat-threads" "8"

LOG "- Known-good UI port tweaks (crew)"
# Android 12+ phantom process killer kills background child processes (Termux,
# shells, some launchers' helpers) and causes app restarts on ports with less RAM headroom.
SET_PROP "system" "persist.sys.fflag.override.settings_enable_monitor_phantom_procs" "false"
# Pre-forked app zygote pool: faster cold app starts (stock AOSP feature).
SET_PROP "system" "persist.device_config.runtime_native.usap_pool_enabled" "true"
# No Skia atrace instrumentation in release builds.
SET_PROP "system" "debug.hwui.skia_atrace_enabled" "false"
# Don't let background dexopt use the big cores at full speed while the UI is in use.
SET_PROP "system" "dalvik.vm.background-dex2oat-threads" "2"
SET_PROP "system" "dalvik.vm.background-dex2oat-cpu-set" "0,1,2,3"
SET_PROP "system" "dalvik.vm.dex2oat-cpu-set" "0,1,2,3,4,5,6,7"

# crew: ExtremeROM exynos9820 miscs + unica settings mod props. Product build.prop
# (overrides vendor, survives apply_vendor_kernel's vendor resync).
LOG_STEP_IN "- ExtremeROM 9820 perf props (SF latch, app freezer)"
SET_PROP "product" "debug.hwui.use_hint_manager" "true"
SET_PROP "product" "debug.sf.latch_unsignaled" "1"
SET_PROP "product" "debug.sf.high_fps_late_app_phase_offset_ns" "0"
SET_PROP "product" "debug.sf.high_fps_late_sf_phase_offset_ns" "0"
SET_PROP "system" "persist.device_config.activity_manager_native_boot.use_freezer" "true"
LOG_STEP_OUT
