# crew: telemetry + carrier installer bloat (no UI/feature impact). Keep SCPM/OMC/KLMS/Fota/SOAgent.
# (dalvik.vm.systemuicompilerfilter=speed already ships in the S24 FE base)
for CREW_N in 'DiagMonAgent*' 'DeviceQualityAgent*' 'knoxanalyticsagent' 'Ignite-*' 'TEEgrisTui*'; do
    for CREW_P in $(cd "$WORK_DIR" && find system product system_ext prism -maxdepth 4 -type d -name "$CREW_N" 2>/dev/null); do
        case "$(basename "$(dirname "$CREW_P")")" in
            app|priv-app) DELETE_FROM_WORK_DIR "${CREW_P%%/*}" "${CREW_P#*/}" ;;
        esac
    done
done

# crew: TEEgris Trusted-UI keypad (Pay/Pass/Wallet only, dead with tripped Knox) - always running, ~75 MB, 10s epoll wakeups
DELETE_FROM_WORK_DIR "system" "system/etc/sysconfig/preinstalled-packages-com.samsung.sec.android.teegris.tui_service.xml"
