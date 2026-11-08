#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 crew
#
# Installs the imported Vendor_Kernel vendor + kernel into the work dir after
# every patch and mod ran: same result as flashing that package next to the
# built system (the combination that booted One UI 8.5).

# [
source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1
# ]

VK="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")/vk"
if [ ! -f "$VK/.imported" ]; then
    LOGE "No imported Vendor_Kernel package in ${VK//$SRC_DIR\//} (run: unica import_vendor_kernel)"
    exit 1
fi

LOG "- Replacing /vendor with the package vendor"
mkdir -p "$WORK_DIR/vendor" "$WORK_DIR/configs"
EVAL "rsync -a --delete \"$VK/vendor/\" \"$WORK_DIR/vendor/\"" || exit 1
cp -a "$VK/fs_config-vendor" "$WORK_DIR/configs/fs_config-vendor"
cp -a "$VK/file_context-vendor" "$WORK_DIR/configs/file_context-vendor"
if [ -d "$APKTOOL_DIR/vendor" ]; then
    LOG "- Dropping decoded vendor APKs (package vendor is used as-is)"
    rm -rf "$APKTOOL_DIR/vendor"
fi

VK_PROP="$WORK_DIR/vendor/build.prop"
VK_DENSITY="${TARGET_LCD_DENSITY:-$(sed -n 's/^ro.sf.init.lcd_density=//p' "$VK_PROP" | head -n 1)}"
if [[ "$VK_DENSITY" =~ ^[0-9]+$ ]]; then
    LOG "- Setting ro.sf.lcd_density=$VK_DENSITY (native resolution)"
    if grep -q '^ro.sf.lcd_density=' "$VK_PROP"; then
        sed -i "s/^ro.sf.lcd_density=.*/ro.sf.lcd_density=$VK_DENSITY/" "$VK_PROP"
    else
        printf '\nro.sf.lcd_density=%s\n' "$VK_DENSITY" >> "$VK_PROP"
    fi
else
    LOGW "No ro.sf.init.lcd_density in package vendor; density left as shipped"
fi
unset VK_PROP VK_DENSITY

LOG "- Replacing kernel images"
rm -rf "$WORK_DIR/kernel"
mkdir -p "$WORK_DIR/kernel"
cp -a "$VK/kernel/"*.img "$WORK_DIR/kernel/"
LOG "  $(cd "$WORK_DIR/kernel" && ls -- *.img | tr '\n' ' ')"

# target kernel override: target/<codename>/kernel/{boot,dtbo,dtb}.img win over the zip's
for KO_IMG in boot dtbo dtb; do
    if [ -f "$SRC_DIR/target/$TARGET_CODENAME/kernel/$KO_IMG.img" ]; then
        mkdir -p "$WORK_DIR/kernel"
        cp -f "$SRC_DIR/target/$TARGET_CODENAME/kernel/$KO_IMG.img" "$WORK_DIR/kernel/$KO_IMG.img"
        echo "    - Using target kernel override: $KO_IMG.img"
    fi
done
unset KO_IMG

# Say which kernel actually ships: a stale override boot.img is silent otherwise.
KO_VER="$(strings -n 16 "$WORK_DIR/kernel/boot.img" 2> /dev/null | grep -m 1 '^Linux version ')"
LOGW "  Packaged kernel: ${KO_VER:-unknown (compressed Image?)}"
unset KO_VER
exit 0
