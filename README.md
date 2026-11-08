<h1 align="center">StellarRom</h1>
<p align="center">
  <a href="LICENSE"><img loading="lazy" src="https://img.shields.io/github/license/rodrigonbrown-rgb/stellarRom?style=for-the-badge&logo=github"/></a>
  <a href="https://github.com/rodrigonbrown-rgb/stellarRom/commits"><img loading="lazy" src="https://img.shields.io/github/last-commit/rodrigonbrown-rgb/stellarRom?style=for-the-badge"/></a>
  <a href="https://github.com/rodrigonbrown-rgb/stellarRom/stargazers"><img loading="lazy" src="https://img.shields.io/github/stars/rodrigonbrown-rgb/stellarRom?style=for-the-badge"/></a>
</p>
<p align="center">StellarRom is a One UI 9 custom firmware for the Samsung Galaxy S10+.</p>

<p align="center">
  <a href="CHANGELOG.md">📝 Changelog</a>
  <a href="MAINTAINERS">🧑‍💻 Maintainers</a>
  <a href="https://github.com/rodrigonbrown-rgb/stellarRom/issues">⚠ Issues</a>
</p>

# What is StellarRom?
StellarRom is a work-in-progress custom firmware that brings Samsung One UI 9 (Android 17 QPR0) to the Galaxy S10+ (SM-G975F, beyond2lte, Exynos 9820).

It's based on the latest and greatest iteration of Samsung's UX and also includes additional features, fixes and tweaks to ensure the best possible experience on the S10+ out of the box.

It is based on the UN1CA build system, which allows automatic downloading/extraction of the firmware, applying the required patches and generating a flashable zip package for the target device.

Any form of contribution, suggestion, bug report or feature request for the project will be welcome.

# Supported devices
| Device | Model | Codename | SoC | Status |
|---|---|---|---|---|
| Galaxy S10+ | SM-G975F | beyond2lte | Exynos 9820 | Bringup |

# Features
- Based on the latest stable One UI 9 (Android 17 QPR0) Galaxy S24 FE firmware (S721BXXUEEZIF)
- All software features from S24 FE
- Full CSC support
- Moderately Debloated
- Heavily DeKnoxed
- Galaxy AI support (on-device AI models included)
- Completely upstreamed kernel (Singularity, Linux 4.14.357, KernelSU-Next)
- One UI 9 camera with S10+ fixes
- Multi-User support
- AppLock support
- EroFS partitions
- High end animations
- Native/live blur support
- Bluetooth library patch included (based on [BluetoothLibraryPatcher](https://github.com/3arthur6/BluetoothLibraryPatcher))
- [KnoxPatch](https://github.com/salvogiangri/KnoxPatch) implemented in system frameworks
- StellarRom branding in Settings (logo and build number)
- Lockscreen and status bar cutout fix for the S10+ dual front camera
- Screenshot fix
- docomo boot and shutdown animations (Galaxy S7 edge SC-02H / Galaxy S10+ SC-04L)
- Custom boot sound
- Extra mods (OutDoor mode, more coming soon)
- Performance and thermal tuning for Exynos 9820
- Countless other small optimizations
- More that will be added in the future

# Bugs
- Face unlock is not working yet (module included but disabled)
- Boot animation is off-center at FHD+ (centered at WQHD+)

See the <a href="https://github.com/rodrigonbrown-rgb/stellarRom/issues">⚠ Issues</a> tab for more.

# Building
1. Clone the source with its submodules:
```bash
git clone -b bringup/A17_qpr0_9820 --recurse-submodules https://github.com/rodrigonbrown-rgb/stellarRom.git
cd stellarRom
```
2. Download the Exynos 9820 vendor package `Vendor_Kernel(Unified)-1.3.zip` (from ExtremeROM Nexus, also in this repo's [Releases](https://github.com/rodrigonbrown-rgb/stellarRom/releases)) and point `VK_ZIP` to it (default: `~/Downloads/Vendor_Kernel(Unified)-1.3.zip`):
```bash
export VK_ZIP="$HOME/Downloads/Vendor_Kernel(Unified)-1.3.zip"
```
3. Build (release build, the zip lands in `out/`):
```bash
./build_stellar.sh RC1
```

# Installation
> ⚠ Back up everything first. Requires an unlocked bootloader and TWRP for beyond2lte.

1. StellarRom needs the enlarged system partition (12 GB, same layout as the Note10+ d2s). Flash the repartitioner, then the cleaner.
2. Flash the StellarRom zip in TWRP.
3. Format Data (type `yes`).
4. Reboot.

# Licensing
This project is licensed under the terms of the [GNU General Public License v3.0](LICENSE). External dependencies might be distributed under a different license, such as:
- [android-tools](https://github.com/nmeum/android-tools), licensed under the [Apache License 2.0](https://github.com/nmeum/android-tools/blob/master/LICENSE)
- [apktool](https://github.com/iBotPeaches/Apktool), licensed under the [Apache License 2.0](https://github.com/iBotPeaches/Apktool/blob/master/LICENSE.md)
- [erofs-utils](https://github.com/sekaiacg/erofs-utils/), dual license ([GPL-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/GPL-2.0), [Apache-2.0](https://github.com/sekaiacg/erofs-utils/blob/dev/LICENSES/Apache-2.0))
- [img2sdat](https://github.com/xpirt/img2sdat), licensed under the [MIT License](https://github.com/xpirt/img2sdat/blob/master/LICENSE)
- [platform_build](https://android.googlesource.com/platform/build/) (ext4_utils, f2fs_utils, signapk), licensed under the [Apache License 2.0](https://source.android.com/docs/setup/about/licenses)
- [smali](https://github.com/google/smali), [multiple licenses](https://github.com/google/smali/blob/main/third_party/NOTICE)

# Accountability
```cpp
#include <std_disclaimer.h>

/*
* Your warranty is now void.
*
* I am not responsible for bricked devices, dead SD cards,
* thermonuclear war, or you getting fired because the alarm app failed.
* Please do some research if you have any concerns about doing this to your device.
* YOU are choosing to make these modifications.
*/
```

# Credits
- **[salvogiangri](https://github.com/salvogiangri)** for the UN1CA build system and One UI patches
- **[Ocin4Ever](https://github.com/Ocin4Ever)** for EternityROM and smali help
- **[ExtremeXT](https://github.com/ExtremeXT)** for ExtremeROM Nexus, ExtremeKernel (Singularity base) and the Exynos 9820 vendor/kernel package
- **[Creeeeger](https://github.com/Creeeeger)** for facePort
- **[ananjaser1211](https://github.com/ananjaser1211)** for samloader and One UI porting work
- All the UN1CA project contributors and testers ❤️

# Kernel source
- Singularity (Exynos 9820), based on ExtremeKernel by ExtremeXT: https://github.com/ExtremeXT/M62-backport
