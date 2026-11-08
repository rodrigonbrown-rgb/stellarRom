SKIPUNZIP=1
# crew: Android 17 Tethering APEX on the 9820 kernel (reports 5.4.x, no BPF ring buffers).
# NetBpfLoad 25Q4/26Q3 hard gates bypassed; service-connectivity.jar ring-buffer
# consumers disabled. APEX rebuilt rootless (debugfs/fsck.erofs), ext4 payload,
# AVB hashtree with its own apex.key prop, platform-signed, replaces the CAPEX.

if [[ "${SOURCE_API_LEVEL:-0}" -lt 37 ]]; then
    LOG "- Source API ${SOURCE_API_LEVEL:-?} < 37, Tethering APEX left untouched"
    return 0
fi

TETH_APEX="$(find "$WORK_DIR/system/system/apex" -maxdepth 1 -type f \
    \( -name 'com.google.android.tethering*.apex' -o -name 'com.google.android.tethering*.capex' \
       -o -name 'com.android.tethering*.apex' -o -name 'com.android.tethering*.capex' \) | sort | head -n 1)"
[ -f "$TETH_APEX" ] || ABORT "Tethering APEX not found in /system/apex"

if [ -d "$WORK_DIR/system/system/etc/netbpfload_compat" ]; then
    DELETE_FROM_WORK_DIR "system" "system/etc/netbpfload_compat"
fi
for TETH_RC in "$WORK_DIR/system/system/etc/init/hw/init.rc" "$WORK_DIR/system/system/etc/init/netbpfload.rc"; do
    [ -f "$TETH_RC" ] && sed -i \
        -e '/netbpfload_compat\/bin \/apex\/com\.android\.tethering\/bin bind/d' \
        -e '/# crew: retain the APEX path\/namespace while bypassing only its kernel hard gates\./d' \
        "$TETH_RC"
done

TETH_TMP="$TMP_DIR/tethering_compat"
rm -rf "$TETH_TMP"
mkdir -p "$TETH_TMP"
TETH_X="$TETH_TMP/x"
TETH_PAYLOAD="$TETH_X/payload"

LOG_STEP_IN "- Unpacking ${TETH_APEX#"$WORK_DIR"/}"
python3 "$MODPATH/crew_apex.py" unpack "$TETH_APEX" "$TETH_X" --tools-bin "$TOOLS_DIR/bin" \
    || ABORT "Failed to unpack the Tethering APEX"
TETH_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$TETH_X/info.json")"
TETH_KEYPROP="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apex_key"])' "$TETH_X/info.json")"
[ -n "$TETH_NAME" ] || ABORT "Tethering APEX manifest has no name"
LOG_STEP_OUT

LOG_STEP_IN "- Bypassing NetBpfLoad 25Q4/26Q3 kernel hard gates"
[ -f "$TETH_PAYLOAD/bin/netbpfload" ] || ABORT "Tethering payload has no bin/netbpfload"
python3 "$MODPATH/crew_netbpfload_gate.py" "$TETH_PAYLOAD/bin/netbpfload" \
    || ABORT "Unknown NetBpfLoad: refusing to ship a loader that reboots on this kernel"
if [ -f "$TETH_PAYLOAD/lib64/libnetd_updatable.so" ]; then
    TETH_NETD_GATES="$(strings -n 12 "$TETH_PAYLOAD/lib64/libnetd_updatable.so" | grep -E 'requires kernel [0-9]' | sort -u | paste -sd ';')"
    LOG "  libnetd_updatable gates: ${TETH_NETD_GATES:-none}"
    if grep -q -E 'requires kernel 5\.(1[0-9])' <<< "$TETH_NETD_GATES"; then
        LOGW "libnetd_updatable has a kernel >= 5.10 gate: netd may abort, send this log line"
    fi
fi
LOG_STEP_OUT

LOG_STEP_IN "- netd.o: stats programs for the reported 5.4 kernel"
[ -f "$TETH_PAYLOAD/etc/bpf/mainline/netd.o" ] || ABORT "Tethering payload has no etc/bpf/mainline/netd.o"
python3 "$MODPATH/crew_netd_bpf_kver.py" "$TETH_PAYLOAD/etc/bpf/mainline/netd.o" \
    || ABORT "netd.o: unexpected kernel ranges, netd would abort on this kernel"
LOG_STEP_OUT

LOG_STEP_IN "- Disabling BPF ring-buffer consumers in service-connectivity.jar"
[ -f "$TETH_PAYLOAD/javalib/service-connectivity.jar" ] || ABORT "Tethering payload has no javalib/service-connectivity.jar"
python3 "$MODPATH/crew_conn_dexpatch.py" "$TETH_PAYLOAD/javalib/service-connectivity.jar" \
    || ABORT "service-connectivity.jar: getLocalNetEventListener / nativeInit*EventConsumer not found"
LOG_STEP_OUT

LOG_STEP_IN "- Rebuilding $TETH_NAME"
TETH_KEY=""
for TETH_K in "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
        $(find "$SRC_DIR/external" "$TOOLS_DIR" -path '*avb*' -name testkey_rsa4096.pem 2> /dev/null | head -n 1) \
        "$SRC_DIR/security/crew_apex_rsa4096.pem"; do
    [ -f "$TETH_K" ] && { TETH_KEY="$TETH_K"; break; }
done
if [ -z "$TETH_KEY" ]; then
    TETH_KEY="$SRC_DIR/security/crew_apex_rsa4096.pem"
    LOG "  generating ${TETH_KEY#"$SRC_DIR"/} (APEX payload key, kept for later builds)"
    openssl genrsa -out "$TETH_KEY" 4096 2> /dev/null || ABORT "openssl genrsa failed"
fi
LOG "  payload key: ${TETH_KEY#"$SRC_DIR"/}, apex.key=$TETH_KEYPROP"

TARGET_SYSTEM_AS_ROOT=true "$SRC_DIR/scripts/build_fs_image.sh" "ext4" -f \
    -o "$TETH_TMP/apex_payload.img" -p "system" \
    "$TETH_PAYLOAD" "$TETH_X/file_contexts" "$TETH_X/fs_config" > /dev/null \
    || ABORT "Failed to build the Tethering apex_payload.img"

TETH_SALT="$(sha256sum "$TETH_X/apex/apex_manifest.pb" | cut -d ' ' -f 1)"
EVAL "avbtool add_hashtree_footer --do_not_generate_fec --algorithm SHA256_RSA4096 --hash_algorithm sha256 --key \"$TETH_KEY\" --prop \"apex.key:$TETH_KEYPROP\" --salt \"$TETH_SALT\" --image \"$TETH_TMP/apex_payload.img\"" \
    || ABORT "avbtool add_hashtree_footer failed"
EVAL "avbtool extract_public_key --key \"$TETH_KEY\" --output \"$TETH_TMP/apex_pubkey\"" \
    || ABORT "avbtool extract_public_key failed"

python3 "$MODPATH/crew_apex.py" zip "$TETH_X" "$TETH_TMP/apex_payload.img" "$TETH_TMP/apex_pubkey" \
    "$TETH_TMP/unsigned.apex" || ABORT "Failed to assemble the Tethering APEX"
EVAL "signapk -a 4096 --align-file-size \"$SRC_DIR/security/aosp_platform.x509.pem\" \"$SRC_DIR/security/aosp_platform.pk8\" \"$TETH_TMP/unsigned.apex\" \"$TETH_TMP/signed.apex\"" \
    || ABORT "signapk failed for the Tethering APEX"
LOG_STEP_OUT

LOG_STEP_IN "- Verifying the rebuilt APEX"
python3 "$MODPATH/crew_apex.py" unpack "$TETH_TMP/signed.apex" "$TETH_TMP/v" --tools-bin "$TOOLS_DIR/bin" > /dev/null \
    || ABORT "Rebuilt Tethering APEX does not unpack"
python3 - "$TETH_X" "$TETH_TMP/v" <<'PYEOF' || ABORT "Rebuilt Tethering APEX differs from the patched tree"
import filecmp, json, sys
from pathlib import Path
a, b = Path(sys.argv[1]), Path(sys.argv[2])
strip = lambda p: sorted(l for l in p.read_text().splitlines() if "lost" not in l)
bad = []
for f in ("fs_config", "file_contexts"):
    if strip(a / f) != strip(b / f):
        bad.append(f)
ia, ib = json.loads((a / "info.json").read_text()), json.loads((b / "info.json").read_text())
if ib["fs"] != "ext4" or ia["apex_key"] != ib["apex_key"]:
    bad.append(f"fs={ib['fs']} apex.key={ib['apex_key']}")
c = filecmp.dircmp(a / "payload", b / "payload")
def walk(c, pre=""):
    out = [pre + x for x in c.diff_files + c.left_only + c.right_only]
    for n, s in c.subdirs.items():
        out += walk(s, pre + n + "/")
    return out
bad += walk(c)
if bad:
    sys.exit("    mismatch: " + ", ".join(bad[:10]))
print(f"    payload/metadata round-trip OK ({len(strip(b / 'fs_config'))} entries)")
PYEOF
python3 "$MODPATH/crew_conn_dexpatch.py" --check "$TETH_TMP/v/payload/javalib/service-connectivity.jar" | grep -q '\[already\]' \
    || ABORT "Rebuilt service-connectivity.jar is not patched"
if unzip -l "$TETH_TMP/signed.apex" | grep -q 'original_apex'; then
    ABORT "Rebuilt APEX unexpectedly compressed"
fi
mv -f "$TETH_TMP/signed.apex" "$TETH_APEX"
LOG "  ${TETH_APEX#"$WORK_DIR"/}: $(du -h "$TETH_APEX" | cut -f 1), sha256 $(sha256sum "$TETH_APEX" | cut -c 1-16)"
LOG_STEP_OUT

rm -rf "$TETH_TMP"
unset TETH_APEX TETH_RC TETH_TMP TETH_X TETH_PAYLOAD TETH_NAME TETH_KEYPROP TETH_NETD_GATES
unset TETH_KEY TETH_K TETH_SALT
