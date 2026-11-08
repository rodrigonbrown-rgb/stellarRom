# ArtisanROM perf bits safe for this tree.
# surfaceflinger P010 hex patch removed: validate_work_dir requires a
# source-identical /system/bin/surfaceflinger (boot-critical core).
LOG_STEP_IN "- ArtisanROM perf: 64-bit dex2oat"
SET_PROP "system" "dalvik.vm.dex2oat64.enabled" "true"
LOG_STEP_OUT
