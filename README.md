# Luma Mobile on the Google Pixel 6a (bluejay)

An unofficial, work-in-progress port of [Luma](https://simplyluma.com) to the Google Pixel 6a
(codename `bluejay`, Google Tensor G1 / `gs101`). Luma's own ARM nightly OS image runs **unchanged**;
this repository only provides the phone-specific layer: a kernel, a device tree, a boot image with
an initramfs that starts Luma, and a few device services.

> **Status: development / debug build.** It boots to the Luma phone shell with touch, GPU acceleration,
> Wi-Fi and Bluetooth. There is **no audio, no microphone, no camera and no modem (calls/SMS/data)** yet.
> Do not use it as your only phone.

| Works | Partly | Not yet |
|---|---|---|
| Boot from flash to the Luma shell (slot A, stock/other OS kept in slot B) | Touch (works, edges not calibrated) | Audio, microphone (needs the AoC DSP driver) |
| Display (simple framebuffer, 1080x2400) | GPU only via a stop-gap patch to Mesa (see below) | Cameras |
| GPU: Mali-G78 with OpenGL ES 3.1 (panfrost), also inside flatpaks | On-screen keyboard: GTK/Qt/Chromium apps need the settings in this repo | Modem, calls, SMS, mobile data |
| Wi-Fi (BCM4389 over PCIe), Bluetooth (BCM4389 over UART) | | Suspend, sensors, GPS, Vulkan |
| USB networking + SSH (debug build) | | Android apps (container is present but untested) |

---

## ⚠️ Read this first

- **Unlocking the bootloader erases the phone.** Back up everything.
- **The Pixel 6a has bootloader anti-rollback.** Never flash an *older* bootloader than the one your
  phone is running, and never boot a slot whose bootloader is older. This guide flashes the **same**
  bootloader version to the other slot before using it.
- Never write `vbmeta`, `persist`, `efs`, `modem_userdata`, partition tables, and never relock the
  bootloader while this is installed.
- Writing `userdata` erases all user data of the OS in the other slot too (they share `userdata`).
- Everything here is at your own risk. You can always go back with Google's factory image
  (`flash-all.sh`) as long as you respect the anti-rollback rule.

## What you need

- A Pixel 6a that can be OEM-unlocked, a USB-C data cable.
- A Linux PC (tested on an x86_64 Arch-based distro) with: `git`, `ostree`, `clang`, `lld`, `llvm`,
  `pahole`, `lz4`, `zstd`, `cpio`, `python3`, `e2fsprogs`, `dosfstools`, `curl`, `bison`, `flex`, `make`.
  About 40 GB of free disk space.
- `sudo` for one step (building the disk image).

## 1. Host tools (no root)

```sh
git clone <this repository> luma-pixel6a-port && cd luma-pixel6a-port
mkdir -p hosttools && cd hosttools
curl -LO https://dl.google.com/android/repository/platform-tools-latest-linux.zip && unzip platform-tools-latest-linux.zip
git clone https://android.googlesource.com/platform/system/tools/mkbootimg
git clone https://android.googlesource.com/platform/external/avb
# a `bc` is needed by the kernel build; build one into hosttools/local/bin if your system has none
mkdir -p local/bin
printf '#!/bin/sh\nexec python3 %s/mkbootimg/mkbootimg.py "$@"\n' "$PWD" > local/bin/mkbootimg
printf '#!/bin/sh\nexec python3 %s/mkbootimg/unpack_bootimg.py "$@"\n' "$PWD" > local/bin/unpack_bootimg
printf '#!/bin/sh\nexec python3 %s/avb/avbtool.py "$@"\n' "$PWD" > local/bin/avbtool
chmod +x local/bin/*; cd ..
mkdir -p hosttools/ssh && ssh-keygen -t ed25519 -N '' -f hosttools/ssh/bluejay_ed25519   # debug SSH key
source env.sh
```

## 2. Sources

```sh
mkdir -p sources
# Kernel: the nura / postmarketOS gs101 tree, pinned commit
curl -L -o sources/linux.tar.gz \
  https://gitlab.nura.eco/soc/tensor-exynos/linux/-/archive/e8f42849a581ea8e915ad0f10c25951e696dc6b5/linux-e8f42849a581ea8e915ad0f10c25951e696dc6b5.tar.gz
tar -xzf sources/linux.tar.gz -C sources
# Luma (for the shared disk-image builder and reference)
git clone -b devices/pixel9 https://github.com/SimplyLuma/luma.git luma
```

Download Google's factory image **that matches the bootloader on your phone** from
<https://developers.google.com/android/images#bluejay> (check `fastboot getvar version-bootloader`),
verify its SHA-256 and unzip it into `sources/stock-<build>/`. It provides the bootloader for the other
slot and the Wi-Fi/Bluetooth firmware.

The busybox and dropbear binaries for the debug initramfs come from Alpine Linux aarch64 packages:
download `busybox-static`, `dropbear`, `musl`, `zlib`, `utmps-libs`, `skalibs-libs` from
`https://dl-cdn.alpinelinux.org/alpine/v3.22/main/aarch64/` and extract each into
`sources/alpine/x/<package-version>/`.

## 3. Kernel and boot images

```sh
scripts/build-kernel.sh                 # applies kernel/patches + kernel/patches-omarchy, builds into build/kernel
scripts/build-boot.sh my-first-build    # -> build/candidates/my-first-build/{boot.img,vendor_boot.img}
```

`build-boot.sh` makes an Android header-v4 `boot.img` (kernel) and `vendor_boot.img` (device tree,
initramfs, command line), each padded to 64 MiB with an AVB hash footer (test key), like the stock ones.

## 4. The Luma OS and the userdata image

```sh
ostree --repo=build/ostree-repo init --mode=archive
ostree --repo=build/ostree-repo remote add --gpg-import=luma/config/os/keys/luma-os-release.asc \
  luma https://dl.simplyluma.com/os/repo
ostree --repo=build/ostree-repo pull luma luma/1/aarch64/nightly     # slow: ~1.5 h, ~120k objects
COMMIT=$(ostree --repo=build/ostree-repo rev-parse luma:luma/1/aarch64/nightly)
sudo COMMIT=$COMMIT TAG=dev1 OUT=$PWD/build/userdata-dev1 SRC_REPO=$PWD/build/ostree-repo \
  REF=luma/1/aarch64/nightly bash scripts/compose/build-release-image.sh
```

The builder must run in a real terminal (it asks for your sudo password). It creates
`build/userdata-dev1/luma-bluejay-dev1-userdata.sparse`: a disk with `LumaBoot` and `LumaRoot`
(4096-byte sectors) holding the nightly deployment and a user `luma` with password `1234`
(**change it after the first boot**).

## 5. Unlock and prepare the phone (once)

1. In Android: Developer options → enable **OEM unlocking** and USB debugging.
2. `adb reboot bootloader`, then `fastboot flashing unlock` and confirm on the phone (**erases the phone**).
3. Check which slot Android uses: `fastboot getvar current-slot`. Luma goes into the **other** slot.
   The commands below assume Android is in **B** and Luma goes into **A**; swap `a`/`b` if needed.
4. Flash the **same** bootloader version your phone runs, plus the matching radio, to the other slot:

```sh
fastboot --slot=other flash bootloader sources/stock-<build>/bootloader-bluejay-<version>.img
fastboot --slot=other flash radio      sources/stock-<build>/radio-bluejay-<version>.img
```

## 6. Install

```sh
fastboot flash userdata      build/userdata-dev1/luma-bluejay-dev1-userdata.sparse
fastboot flash boot_a        build/candidates/my-first-build/boot.img
fastboot flash vendor_boot_a build/candidates/my-first-build/vendor_boot.img
fastboot erase dtbo_a
fastboot --set-active=a
fastboot reboot
```

The first boot takes about a minute. The phone signs in by itself (or asks for `1234`).
If Luma fails to start, the bootloader falls back to the other slot after three tries; you can also
go back with `fastboot --set-active=b`.

## 7. Firmware (Wi-Fi and Bluetooth)

Firmware is **not** redistributed. Copy it from the stock `vendor.img` of your factory image
(`/firmware/fw_bcmdhd.bin`, `/firmware/bcmdhd_clm.blob`, `/firmware/bcmdhd.cal`,
`/firmware/brcm/BCM.hcd`) to the phone under the names the Linux drivers expect:

```text
/var/lib/luma-bluejay/firmware/brcm/brcmfmac4389c1-pcie.bin                       <- fw_bcmdhd.bin
/var/lib/luma-bluejay/firmware/brcm/brcmfmac4389c1-pcie.clm_blob                  <- bcmdhd_clm.blob
/var/lib/luma-bluejay/firmware/brcm/brcmfmac4389c1-pcie.google,gs101-bluejay.txt  <- bcmdhd.cal
/var/lib/luma-bluejay/firmware/brcm/BCM.hcd                                       <- brcm/BCM.hcd
```

`debugfs -R 'dump /firmware/<file> <out>' vendor.img` extracts them without root. Reboot afterwards.

## 8. Using the debug build

- Root SSH over USB: `scripts/bluejay-ssh.sh` (IPv6 link-local on the USB NCM link, key only).
- New boot images without touching buttons: `scripts/deploy-candidate.sh <name>`.
- The Android container is off by default: `~/android.sh start|stop|status` (copy `scripts/android.sh`).
- On-screen keyboard in flatpak apps: run once on the phone
  `flatpak override --system --env=GTK_IM_MODULE=wayland --env=QT_IM_MODULE=wayland --env=QT_IM_MODULES=wayland`,
  install `device/shell-extension/luma-bluejay-osk@luma.local` into
  `/usr/local/share/gnome-shell/extensions/`, enable it and log in again. Chromium browsers also need
  `--enable-wayland-ime --wayland-text-input-version=3`.

## Known issues

- One spontaneous reboot after ~5 minutes was seen once; cause not yet known.
- The GPU works through a stop-gap: Mesa 26.2.5 has no Mali-G78 entry, so the initramfs patches one
  table entry of `libgallium` in RAM (only for the exact Fedora 44 build) and builds local flatpak GL
  extensions the same way. The proper fix is the Mesa patch referenced below.
- `/proc/cmdline` is bind-mounted with `ostree=` during early boot so systemd can mount `/var`.

## Credits and licences

- Kernel: [nura / postmarketOS gs101 tree](https://gitlab.nura.eco/soc/tensor-exynos/linux) (GPL-2.0).
- GPU, Wi-Fi and Bluetooth patches from
  [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile) (GPL-2.0),
  see `kernel/patches-omarchy/PROVENANCE.md`; the gs101 PCIe PHY tables follow Google's GPL
  `pcie-exynos-gs101-rc-cal.c`.
- Mesa G78 entry: [derekross/omarchy-mobile PR #8](https://github.com/derekross/omarchy-mobile/pull/8).
- Disk-image builder adapted from [SimplyLuma/luma](https://github.com/SimplyLuma/luma) (`devices/pixel9`).
- Luma is a product of its own authors; this port is not affiliated with them.

## Licensing

| Path | Licence |
|---|---|
| Everything not listed below (scripts, initramfs, tools, shell extension, docs) | [The Unlicense](LICENSE) (public domain) |
| `kernel/` (Linux patches and kernel configuration) | GPL-2.0-only, as the Linux kernel ([text](LICENSES/GPL-2.0-only.txt)); imported patches keep their authors |
| `scripts/compose/`, `initramfs-debug/hooks/20-luma-bluejay-device.sh` | Apache-2.0, derived from [SimplyLuma/luma](https://github.com/SimplyLuma/luma) ([text](LICENSES/Apache-2.0.txt)) |

Files carry SPDX identifiers where they differ from the default. No firmware or Google binaries are included.

Development notes (in Italian) with every step and finding are in `NOTES.md`.
