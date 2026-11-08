#!/system/bin/sh
# crew: debug-only boot watchdog (target/beyond2lte/patches/zz_crew_bootwd).
#
# Runs from early-init in the permissive crew_bootwd domain. Every 5 s it
# appends a line of boot-stage properties to /cache/crew_bootwd/progress.txt,
# so the last line shows where init stopped. If the boot stalls it snapshots
# dmesg/logcat/props/processes and reboots to recovery (TWRP), where the
# snapshot can be pulled with: adb pull /cache/crew_bootwd
#
#  - stall before zygote: snapshot "stall1" at STALL1 s, then reboot
#  - zygote up but no boot_completed: snapshot "stall2" at STALL2 s, then reboot
#  - touch /cache/crew_bootwd.noreboot in TWRP to keep the device up instead

STALL1=180
STALL2=600
OUT=/cache/crew_bootwd

# Keep init's own /dev/kmsg lines: 4.14 rate-limits them by default.
echo on > /proc/sys/kernel/printk_devkmsg 2> /dev/null
echo "crew_bootwd: started" > /dev/kmsg

i=0
until grep -q " /cache " /proc/mounts; do
    sleep 1
    i=$((i + 1))
    [ $i -ge 600 ] && exit 0
done

if [ -d "$OUT" ]; then
    rm -rf "$OUT.prev"
    mv "$OUT" "$OUT.prev"
fi
mkdir -p "$OUT"
echo "crew_bootwd: armed, writing $OUT" > /dev/kmsg

STAGE_PROPS="ro.crypto.state vendor.tzdaemon vendor.tzts_daemon
init.svc.tz_service init.svc.tzts_service init.svc.system_aconfigd_platform_init
init.svc.scs init.svc.vold init.svc.vendor.keymaster-4-0 vold.post_fs_data_done
init.svc.casefolding_remover ro.casefolding.adjusted apexd.status
keystore.module_hash.sent bpf.progs_loaded init.svc.zygote init.svc.surfaceflinger
sys.boot_completed"

progress()
{
    line="$(cut -d ' ' -f 1 /proc/uptime)s"
    for p in $STAGE_PROPS; do
        line="$line $p=$(getprop "$p")"
    done
    echo "$line" >> "$OUT/progress.txt"
}

snapshot()
{
    d="$OUT/$1"
    mkdir -p "$d"
    echo "crew_bootwd: snapshot $1" > /dev/kmsg
    cat /proc/uptime > "$d/uptime.txt"
    cat /sys/fs/selinux/enforce > "$d/enforce.txt" 2>&1
    getprop > "$d/props.txt" 2>&1
    ps -A -o PID,PPID,USER,LABEL,S,WCHAN,ARGS > "$d/ps.txt" 2>&1 || ps -A > "$d/ps.txt" 2>&1
    for p in /proc/[0-9]*; do
        echo "${p#/proc/} wchan=$(cat "$p/wchan" 2> /dev/null) $(tr '\0' ' ' < "$p/cmdline" 2> /dev/null)"
    done > "$d/wchan.txt"
    cat /proc/mounts > "$d/mounts.txt"
    ls -laZ / /data /data/misc /data/vendor /metadata /metadata/aconfig /cache \
        /mnt/vendor/efs/tee /dev/socket > "$d/ls.txt" 2>&1
    dmesg > "$d/dmesg.txt" 2>&1
    timeout 30 logcat -d -b all -v threadtime > "$d/logcat.txt" 2>&1
    sync
}

start_s=$(cut -d . -f 1 /proc/uptime)
while :; do
    progress
    if [ "$(getprop sys.boot_completed)" = "1" ]; then
        snapshot booted
        exit 0
    fi
    now=$(( $(cut -d . -f 1 /proc/uptime) - start_s ))
    if [ "$(getprop init.svc.zygote)" = "running" ]; then
        limit=$STALL2; tag=stall2
    else
        limit=$STALL1; tag=stall1
    fi
    if [ $now -ge $limit ]; then
        snapshot $tag
        if [ -e /cache/crew_bootwd.noreboot ]; then
            echo "crew_bootwd: $tag, noreboot flag set" > /dev/kmsg
            exit 0
        fi
        echo "crew_bootwd: $tag, rebooting to recovery" > /dev/kmsg
        setprop sys.powerctl reboot,recovery
        exit 0
    fi
    sleep 5
done
