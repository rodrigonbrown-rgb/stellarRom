#
# Copyright (C) 2024 BlackMesa123
# Copyright (C) 2026 crew
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Device configuration file for Galaxy S10+ (Exynos) (beyond2lte)
TARGET_NAME="Galaxy S10+ (Exynos)"
TARGET_CODENAME="beyond2lte"
TARGET_ASSERT_MODEL=("SM-G975F" "SM-G975N")
TARGET_PLATFORM="exynos9820"
# Stock G975F plays the role stock N975F plays for d2s: every Impulse patch
# reads it unchanged. /vendor and the kernel are then replaced wholesale by the
# Vendor_Kernel package (scripts/import_vendor_kernel.sh + apply_vendor_kernel.sh).
TARGET_FIRMWARE="SM-G975F/AUT/356262101234561"
TARGET_EXTRA_FIRMWARES=("")
TARGET_API_LEVEL=31
TARGET_PRODUCT_FIRST_API_LEVEL=28
TARGET_VNDK_VERSION=31
TARGET_SYSTEM_AS_ROOT=true
TARGET_SINGLE_SYSTEM_IMAGE="essi85"
ESSI85_SOURCE="r14s"
TARGET_OS_FILE_SYSTEM="erofs"
TARGET_SUPER_PARTITION_SIZE=0
TARGET_SUPER_GROUP_NAME="none"
TARGET_SUPER_GROUP_SIZE=0
TARGET_HAS_SYSTEM_EXT=false
TARGET_BOOT_DEVICE_PATH="/dev/block/by-name"
# Same Exynos 9820/9825 repartition as d2s: identical physical ceilings.
TARGET_SYSTEM_PARTITION_SIZE=9437184000
TARGET_PRISM_PARTITION_SIZE=734003200
TARGET_OPTICS_PARTITION_SIZE=31457280

# Local vendor + kernel package (override: export VK_ZIP=/path/to/zip)
TARGET_VENDOR_KERNEL_ZIP="${VK_ZIP:-$HOME/Downloads/Vendor_Kernel(Unified)-1.3.zip}"
TARGET_VENDOR_KERNEL_MODEL="G975"

# Settings > About phone > Software information > Build number
TARGET_ROM_DISPLAY_ID="ExtremeRom-Revived-crew"
# ExtremeROM logo banner in Software information (rebuilds SecSettings
# resources only; its DEX stays byte-identical to stock)
TARGET_SETTINGS_LOGO=true

# SEC Product Feature: identical to d2s so the same patch set runs; only the
# cutout differs (S10+ pill on the right).
TARGET_AUDIO_SUPPORT_ACH_RINGTONE=false
TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION=true
TARGET_AUTO_BRIGHTNESS_TYPE="4"
TARGET_DISPLAY_CUTOUT_TYPE="right"
TARGET_DVFS_CONFIG_NAME="dvfs_policy_s5e9925_xx"
TARGET_FP_SENSOR_CONFIG="google_touch_display_ultrasonic"
TARGET_HAS_HW_MDNIE=true
TARGET_HAS_MASS_CAMERA_APP=false
TARGET_HAS_QHD_DISPLAY=true
TARGET_HFR_DEFAULT_REFRESH_RATE="60"
TARGET_HFR_MODE="0"
TARGET_HFR_SEAMLESS_BRT="none"
TARGET_HFR_SEAMLESS_LUX="none"
TARGET_HFR_SUPPORTED_REFRESH_RATE="60"
TARGET_IS_ESIM_SUPPORTED=false
TARGET_MDNIE_SUPPORTED_MODES="65303"
TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION="3"
TARGET_NFC_CHIP_VENDOR="SLSI"
TARGET_SUPPORT_HOTSPOT_6GHZ=false
TARGET_SUPPORT_HOTSPOT_DUALAP=false
TARGET_SUPPORT_HOTSPOT_ENHANCED_OPEN=false
TARGET_SUPPORT_HOTSPOT_WIFI_6=true
TARGET_SUPPORT_HOTSPOT_WPA3=false
TARGET_SUPPORT_WIFI_7=false

# The EternityROM 14.1.01.17 SamsungCamera in platform/*/camera is an apktool
# rebuild carrying Samsung's original META-INF, so its v1 signature is broken.
# Re-sign it with the ROM platform key and trust that key for the camera only.
TARGET_CAMERA_ROM_SIGNED=true
