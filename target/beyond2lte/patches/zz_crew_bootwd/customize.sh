SKIPUNZIP=1
# crew: debug-only boot watchdog. Built only with `source buildenv.sh --debug`.
#
# One extra SELinux domain, crew_bootwd, is declared permissive so the script can
# read every process, dmesg and logcat and write /cache. The device itself stays
# enforcing: no other domain changes mode, and init only gains the transition.
# Validated against the merged policy (A17 plat + 31.0 mapping + G975F vendor):
# no neverallow violations beyond the ones the stock merge already has
# (init compiles with -N); `noatsecure` is deliberately left out (init.te:845).

if [[ "${DEBUG:-false}" != "true" ]]; then
    LOG "- Not a debug build, boot watchdog not installed"
    return 0
fi

ADD_TO_WORK_DIR "$MODPATH" "system" "system/bin/crew_bootwd.sh" 0 2000 755 "u:object_r:system_file:s0" \
    || ABORT "Failed to add crew_bootwd.sh"
ADD_TO_WORK_DIR "$MODPATH" "system" "system/etc/init/crew_bootwd.rc" 0 0 644 "u:object_r:system_file:s0" \
    || ABORT "Failed to add crew_bootwd.rc"

BOOTWD_PLAT_CIL="$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil"
[ -f "$BOOTWD_PLAT_CIL" ] || ABORT "plat_sepolicy.cil is missing"
if ! grep -q '^(type crew_bootwd)$' "$BOOTWD_PLAT_CIL"; then
    LOG "- Adding the permissive crew_bootwd domain to plat_sepolicy.cil"
    cat >> "$BOOTWD_PLAT_CIL" <<'EOF'
(type crew_bootwd)
(roletype r crew_bootwd)
(typeattributeset domain (crew_bootwd))
(typeattributeset coredomain (crew_bootwd))
(typepermissive crew_bootwd)
(allow init crew_bootwd (process (transition rlimitinh siginh signal sigkill sigstop)))
EOF
fi

# The edited CIL only takes effect if init compiles the policy on-device, i.e.
# no precompiled_sepolicy hash matches the system one.
BOOTWD_SYS_SHA="$(head -n 1 "$WORK_DIR/system/system/etc/selinux/plat_sepolicy_and_mapping.sha256" 2> /dev/null)"
for BOOTWD_PRE in "$WORK_DIR/odm/etc/selinux" "$WORK_DIR/vendor/etc/selinux"; do
    BOOTWD_PRE_SHA="$(head -n 1 "$BOOTWD_PRE/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256" 2> /dev/null)"
    if [ -n "$BOOTWD_SYS_SHA" ] && [ "$BOOTWD_SYS_SHA" = "$BOOTWD_PRE_SHA" ]; then
        ABORT "${BOOTWD_PRE#"$WORK_DIR"/}/precompiled_sepolicy matches the system policy: crew_bootwd would never load"
    fi
done

LOGW "Debug boot watchdog installed: a stalled boot reboots to recovery after ~3 min (~10 min once zygote runs)."
LOGW "Pull /cache/crew_bootwd from TWRP; touch /cache/crew_bootwd.noreboot to disable the reboot."

unset BOOTWD_PLAT_CIL BOOTWD_SYS_SHA BOOTWD_PRE BOOTWD_PRE_SHA
