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
