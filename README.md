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

It's based on the latest One UI 9 firmware for the Galaxy S24 FE, with extra fixes and features for the best possible experience on the S10+ out of the box.

It uses the UN1CA build system, which downloads and extracts the firmware automatically, applies the required patches and generates a flashable zip for the target device.

Any form of contribution, suggestion, bug report or feature request is welcome.

# Supported devices
| Device | Model | Codename | SoC | Status |
|---|---|---|---|---|
| Galaxy S10+ | SM-G975F | beyond2lte | Exynos 9820 | Bringup |

# Features
- Based on One UI 9 (Android 17 QPR0) Galaxy S24 FE firmware (S721BXXUEEZIF)
- StellarRom branding in Settings (logo and build number)
- Singularity kernel (upstreamed 4.14, KernelSU-Next)
- One UI 9 camera
- Now Brief support
- Screenshot fix
- Lockscreen and status bar cutout fix for the S10+ dual front camera
- Outdoor mode
- Screen resolution changer (WQHD+ / FHD+ / HD+)
- RAM Plus (4 GB)
- docomo boot and shutdown animations (Galaxy S7 edge SC-02H, Galaxy S10+ SC-04L selectable)
- More coming soon

# Bugs
- Face unlock is not working yet (module included but disabled)
- Boot animation is off-center at FHD+ (centered at WQHD+)

See the <a href="https://github.com/rodrigonbrown-rgb/stellarRom/issues">⚠ Issues</a> tab for more.

# Building
```bash
git clone -b bringup/A17_qpr0_9820 --recurse-submodules https://github.com/rodrigonbrown-rgb/stellarRom.git
cd stellarRom
source buildenv.sh beyond2lte
run_cmd make_rom
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
- **[ExtremeXT](https://github.com/ExtremeXT)** for ExtremeROM Nexus and the Exynos 9820 vendor/kernel package
- **[Creeeeger](https://github.com/Creeeeger)** for the One UI 9820 kernel base and facePort
- **[ananjaser1211](https://github.com/ananjaser1211)** for samloader and One UI porting work
- All the UN1CA project contributors and testers ❤️

# Kernel source
- Singularity (Exynos 9820), based on [Creeeeger/9820_kernel](https://github.com/Creeeeger/9820_kernel)
