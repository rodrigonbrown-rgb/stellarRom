#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 crew
#
# Imports a local ExtremeROM-Nexus "Vendor_Kernel" flashable package into
# <target fw>/vk/ the way its installer lays it down on the device:
#   images/vendor.new.dat.br + transfer.list -> vk/vendor (+ fs_config/file_context)
#   common/vendor/** then models/<MODEL>/vendor/** -> vendor overlays
#   models/<MODEL>/{boot,dtbo,dtb}.img -> vk/kernel
# common/{system,product,prism,optics} patch the package's own system: skipped.
# The stock firmware dir is untouched; apply_vendor_kernel.sh installs vk/.

# [
source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1

FORCE=false
WORK=""
MNT=""

CLEANUP()
{
    if [ -n "$MNT" ] && mountpoint -q "$MNT" 2> /dev/null; then
        sudo umount "$MNT" &> /dev/null || true
    fi
    [ -n "$WORK" ] && rm -rf "$WORK"
}

RESOLVE_ZIP()
{
    local NAME
    local CANDIDATE
    NAME="$(basename "$1")"
    for CANDIDATE in "$1" "$SRC_DIR/$NAME" "$HOME/Downloads/$NAME" "$HOME/$NAME" "$HOME/Desktop/$NAME"; do
        if [ -f "$CANDIDATE" ]; then
            readlink -f "$CANDIDATE"
            return 0
        fi
    done
    CANDIDATE="$(find "$HOME" -maxdepth 4 -type f -name "$NAME" 2> /dev/null | head -n 1)"
    [ -n "$CANDIDATE" ] || return 1
    readlink -f "$CANDIDATE"
}
# ]

[[ "${1:-}" == "-f" || "${1:-}" == "--force" ]] && FORCE=true

if [[ -z "${TARGET_VENDOR_KERNEL_ZIP:-}" || "$TARGET_VENDOR_KERNEL_ZIP" == "none" ]]; then
    LOGE "TARGET_VENDOR_KERNEL_ZIP is not set for $TARGET_CODENAME"
    exit 1
fi
FW="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
VK="$FW/vk"
if [ ! -f "$FW/.extracted" ]; then
    LOGE "Stock target firmware is not extracted yet: ${FW//$SRC_DIR\//}"
    exit 1
fi
if ! ZIP="$(RESOLVE_ZIP "$TARGET_VENDOR_KERNEL_ZIP")"; then
    LOGE "Package not found: $TARGET_VENDOR_KERNEL_ZIP (export VK_ZIP=/path/to.zip or copy it into $SRC_DIR)"
    exit 1
fi
MODEL="${TARGET_VENDOR_KERNEL_MODEL:-none}"
[[ "$MODEL" == "none" ]] && MODEL="$(cut -d "/" -f 1 <<< "$TARGET_FIRMWARE" | sed -e 's/^SM-//' -e 's/[A-Z]$//')"

ID="$(basename "$ZIP")|$(stat -c '%s|%Y' "$ZIP")|$MODEL|$(cat "$FW/.extracted")"
if ! $FORCE && [[ "$(cat "$VK/.imported" 2> /dev/null)" == "$ID" ]]; then
    LOG "- $(basename "$ZIP") ($MODEL) already imported"
    exit 0
fi

trap CLEANUP EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rm -rf "$VK"
mkdir -p "$VK/kernel" "$OUT_DIR"
WORK="$(mktemp -d "$OUT_DIR/vk_import.XXXXXX")"
MNT="$WORK/mnt"
mkdir -p "$MNT" "$WORK/pkg"

LOG "- Package: $ZIP"
unzip -Z1 "$ZIP" > "$WORK/list" || { LOGE "Cannot read $ZIP"; exit 1; }
MODEL_DIR=""
for M in "$MODEL" "${MODEL}F" "SM-${MODEL}F"; do
    grep -qx "models/$M/boot.img" "$WORK/list" && { MODEL_DIR="models/$M"; break; }
done
if [ -z "$MODEL_DIR" ]; then
    LOGE "No models/$MODEL/boot.img in the package. Model trees:"
    sed -n 's|^\(models/[^/]*\)/.*|\1|p' "$WORK/list" | sort -u >&2
    exit 1
fi
for f in images/vendor.new.dat.br images/vendor.transfer.list; do
    grep -qx "$f" "$WORK/list" || { LOGE "Missing $f in the package"; exit 1; }
done
LOG "- Model tree: $MODEL_DIR"

EVAL "unzip -q -o \"$ZIP\" \"images/vendor.*\" \"$MODEL_DIR/*\" -d \"$WORK/pkg\"" || exit 1
if grep -q "^common/vendor/." "$WORK/list"; then
    EVAL "unzip -q -o \"$ZIP\" \"common/vendor/*\" -d \"$WORK/pkg\"" || exit 1
fi
if unzip -p "$ZIP" "META-INF/com/google/android/updater-script" 2> /dev/null \
        | grep -nE 'package_extract|block_image_update|delete|symlink|set_metadata|run_program' > "$WORK/steps"; then
    LOG "- Package installer steps (reference):"
    head -n 40 "$WORK/steps" | while IFS= read -r l; do LOG "    $l"; done
fi

LOG "- vendor.new.dat.br -> vendor.img"
EVAL "brotli --decompress --force --output=\"$WORK/vendor.new.dat\" \"$WORK/pkg/images/vendor.new.dat.br\"" || exit 1
rm -f "$WORK/pkg/images/vendor.new.dat.br"
python3 - "$WORK/pkg/images/vendor.transfer.list" "$WORK/vendor.new.dat" "$WORK/vendor.img" <<'PYEOF' || exit 1
import sys

transfer_list, new_dat, output = sys.argv[1:4]
BLOCK = 4096


def rangeset(text):
    values = [int(x) for x in text.split(",")]
    if values[0] != len(values) - 1:
        raise SystemExit("bad rangeset: " + text)
    return [(values[i], values[i + 1]) for i in range(1, len(values), 2)]


lines = [line.strip() for line in open(transfer_list, encoding="utf-8")]
commands, end = [], 0
for line in (lines[2:] if int(lines[0]) == 1 else lines[4:]):
    if not line:
        continue
    op, _, arg = line.partition(" ")
    if op not in ("new", "zero", "erase"):
        raise SystemExit("transfer list is not a full image (op: %s)" % op)
    ranges = rangeset(arg)
    commands.append((op, ranges))
    end = max(end, max(b for _, b in ranges))
with open(new_dat, "rb") as src, open(output, "wb") as dst:
    for op, ranges in commands:
        if op != "new":
            continue
        for first, last in ranges:
            dst.seek(first * BLOCK)
            left = (last - first) * BLOCK
            while left:
                chunk = src.read(min(left, 1 << 22))
                if not chunk:
                    raise SystemExit("vendor.new.dat is truncated")
                dst.write(chunk)
                left -= len(chunk)
    dst.truncate(end * BLOCK)
print("    %d blocks" % end)
PYEOF
rm -f "$WORK/vendor.new.dat"

if [[ "$(READ_BYTES_AT "$WORK/vendor.img" "1080" "2")" == "ef53" ]]; then
    VENDOR_FS="ext4"
elif [[ "$(READ_BYTES_AT "$WORK/vendor.img" "1024" "4")" == "e0f5e1e2" ]]; then
    VENDOR_FS="erofs"
else
    LOGE "vendor.img is neither ext4 nor erofs"
    exit 1
fi
LOG "- vendor.img filesystem: $VENDOR_FS"

if ! sudo -n true &> /dev/null; then
    LOG "\033[0;33m! Asking user for sudo password\033[0m"
    sudo -v 2> /dev/null || { LOGE "Root permissions are required to unpack vendor.img"; exit 1; }
fi
if [[ "$VENDOR_FS" == "erofs" ]]; then
    EVAL "sudo env \"PATH=$PATH\" fuse.erofs \"$WORK/vendor.img\" \"$MNT\"" || exit 1
else
    EVAL "sudo mount -o ro,loop \"$WORK/vendor.img\" \"$MNT\"" || exit 1
fi
mkdir -p "$VK/vendor"
EVAL "sudo cp -a -T \"$MNT\" \"$VK/vendor\"" || exit 1
sudo chown -hR "$(whoami):$(whoami)" "$VK/vendor"
[ -d "$VK/vendor/lost+found" ] && rm -rf "$VK/vendor/lost+found"

# Same fs_config/file_context generation as scripts/extract_fw.sh
sudo find "$MNT" -print0 | sudo xargs -0 -r -n 1 -P "$(nproc)" \
    stat -c "%n %u %g %a capabilities=0x0" > "$VK/fs_config-vendor"
sudo find "$MNT" -print0 | sudo xargs -0 -r -n 1 -P "$(nproc)" \
    sh -c 'echo "$1 $(getfattr -n security.selinux --only-values -h --absolute-names "$1")"' "sh" \
    > "$VK/file_context-vendor"
sort -o "$VK/fs_config-vendor" "$VK/fs_config-vendor"
sort -o "$VK/file_context-vendor" "$VK/file_context-vendor"
sed -i "s|$MNT|/vendor|g" "$VK/file_context-vendor"
sed -i -e "s|$MNT | |g" -e "s|$MNT|vendor|g" "$VK/fs_config-vendor"
sed -i -e "s|\.|\\\.|g" -e "s|\+|\\\+|g" -e "s|\[|\\\[|g" \
    -e "s|\]|\\\]|g" -e "s|\*|\\\*|g" "$VK/file_context-vendor"
EVAL "sudo umount \"$MNT\"" || exit 1
rm -f "$WORK/vendor.img"

for OVERLAY in "$WORK/pkg/common/vendor" "$WORK/pkg/$MODEL_DIR/vendor"; do
    [ -n "$(find "$OVERLAY" -type f -print -quit 2> /dev/null)" ] || continue
    LOG "- Applying ${OVERLAY#"$WORK/pkg/"} overlay"
    (cd "$OVERLAY" && find . -type f | sort | sed 's|^\./|    vendor/|') | while IFS= read -r l; do LOG "$l"; done
    cp -a -T "$OVERLAY" "$VK/vendor" || exit 1
    # Files the base image did not have inherit their parent dir's label.
    python3 - "$VK" "$OVERLAY" <<'PYEOF' || exit 1
import os
import re
import sys

vk, overlay = sys.argv[1:3]
fs_path = os.path.join(vk, "fs_config-vendor")
fc_path = os.path.join(vk, "file_context-vendor")
esc = lambda p: re.sub(r"([.+\[\]*])", r"\\\1", p)
fs_lines = open(fs_path, encoding="utf-8").read().splitlines()
fc_lines = open(fc_path, encoding="utf-8").read().splitlines()
known = {line.split(" ", 1)[0] for line in fs_lines if line.strip()}
labels = {k: v for k, _, v in (line.rpartition(" ") for line in fc_lines) if k}


def label_for(entry):
    parent = os.path.dirname(entry)
    while parent:
        if esc("/" + parent) in labels:
            return labels[esc("/" + parent)]
        parent = os.path.dirname(parent)
    return "u:object_r:vendor_file:s0"


new_fs, new_fc = [], []
for root, dirs, files in os.walk(overlay):
    dirs.sort()
    for name in dirs + sorted(files):
        full = os.path.join(root, name)
        entry = "vendor/" + os.path.relpath(full, overlay)
        if entry in known:
            continue
        mode = "0 2000 755" if os.path.isdir(full) or entry.startswith("vendor/bin/") else "0 0 644"
        label = label_for(entry)
        new_fs.append("%s %s capabilities=0x0" % (entry, mode))
        new_fc.append("%s %s" % (esc("/" + entry), label))
        labels[esc("/" + entry)] = label
        known.add(entry)
if new_fs:
    open(fs_path, "w", encoding="utf-8").write("\n".join(sorted(fs_lines + new_fs)) + "\n")
    open(fc_path, "w", encoding="utf-8").write("\n".join(sorted(fc_lines + new_fc)) + "\n")
    print("    %d new entries given default metadata" % len(new_fs))
PYEOF
done

for IMG in boot dtbo dtb; do
    if [ -f "$WORK/pkg/$MODEL_DIR/$IMG.img" ]; then
        cp -a "$WORK/pkg/$MODEL_DIR/$IMG.img" "$VK/kernel/$IMG.img"
        LOG "- Kernel: $IMG.img ($(stat -c %s "$VK/kernel/$IMG.img") bytes)"
    fi
done

LOG "- Checking the imported vendor"
python3 - "$VK/vendor" "$VENDOR_FS" "${TARGET_VNDK_VERSION:-}" "$TARGET_CODENAME" > "$WORK/info" <<'PYEOF' || exit 1
import os
import re
import sys

vendor, vendor_fs, want_vndk, codename = sys.argv[1:5]
prop = {}
for line in open(os.path.join(vendor, "build.prop"), encoding="utf-8", errors="replace"):
    key, sep, value = line.strip().partition("=")
    if sep and not key.startswith("#"):
        prop.setdefault(key.strip(), value.strip())
manifest = os.path.join(vendor, "etc/vintf/manifest.xml")
level = re.search(r'target-level="(\d+)"', open(manifest, errors="replace").read()) if os.path.isfile(manifest) else None
device, vndk = prop.get("ro.product.vendor.device", ""), prop.get("ro.vndk.version", "")
for msg in ("vendor: %s / %s / %s" % (prop.get("ro.product.vendor.model", "?"), device or "?",
                                      prop.get("ro.vendor.build.fingerprint", "?")),
            "vndk=%s fcm=%s density=%s/%s" % (vndk or "?", level.group(1) if level else "?",
                                              prop.get("ro.sf.lcd_density", "?"),
                                              prop.get("ro.sf.init.lcd_density", "?"))):
    print("    " + msg, file=sys.stderr)
print("vendor_image_fs=%s\nvndk=%s\nfcm_level=%s" % (vendor_fs, vndk, level.group(1) if level else ""))
errors = []
if not device or not (device.startswith(codename) or codename.startswith(device)):
    errors.append("vendor device is '%s', expected %s (wrong model tree?)" % (device, codename))
if want_vndk and vndk and vndk != want_vndk:
    errors.append("vendor ro.vndk.version=%s but TARGET_VNDK_VERSION=%s" % (vndk, want_vndk))
for err in errors:
    print("  ! " + err, file=sys.stderr)
sys.exit(1 if errors else 0)
PYEOF
mv -f "$WORK/info" "$VK/info"
echo -n "$ID" > "$VK/.imported"
LOG "- $(basename "$ZIP") ($MODEL_DIR) imported into ${VK//$SRC_DIR\//}"
exit 0
