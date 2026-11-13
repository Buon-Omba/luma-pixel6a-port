# AGENTS.md — how this port was built (for AI agents)

This file is for an AI agent continuing or reproducing the Luma port to the Google Pixel 6a
(`bluejay`, gs101). It records the architecture, the order of work, every non-obvious finding,
and the open items. Humans should read `README.md`. Detailed chronological notes (Italian) are in
`NOTES.md`; treat them as the log, this file as the summary.

## Ground rules that were followed

- The OS is Luma's ARM nightly (`luma/1/aarch64/nightly`, signed by "Luma OS Release",
  key `7D3DAFCE2BCA13A2B68F2761C8CE1A1B51D96CE2`), **unchanged**. Everything device-specific lives in
  the boot image (kernel, DTB, initramfs, hooks) or in files the initramfs writes to `/etc` each boot.
- Stock/other OS stays in one slot (here B); Luma goes into the other (A). Never write `vbmeta`,
  `persist`, `efs*`, `modem_userdata`, partition tables; never relock.
- The phone owner approves risky writes. Ask before: unlocking, bootloader flashes, `devinfo` writes.
- Firmware, calibration data, device dumps and keys never go into git (`.gitignore`).
- Keep provenance for every imported patch (`kernel/patches-omarchy/PROVENANCE.md`).
- Use one time zone (UTC) in logs and notes.

## Architecture

```
fastboot partitions (slot A)          userdata (whole partition)
  boot_a        : Image.lz4             GPT with 4096-byte sectors (Luma builder):
  vendor_boot_a : DTB + initramfs        p1 LumaBoot (FAT, empty)
                  + cmdline              p2 LumaRoot (ext4, ostree sysroot, grown online at boot)
  dtbo_a        : erased
```

Boot flow (`initramfs-debug/init` + `luma-boot.sh`):
1. mount proc/sys/dev/configfs/pstore, `/run` as tmpfs; load modules (coldplug from a pruned tree);
   enable DECON refresh (`luma-devmem 0x1c300030 0x3061`, from nura); USB gadget NCM+ACM; dropbear.
2. 20 s window: `touch /run/stay` over SSH keeps the debug initramfs.
3. Find `userdata` by PARTNAME, parse the nested GPT (busybox `hexdump` cannot read 8-byte ints:
   two 4-byte reads), `losetup -o <LumaRoot offset>` to the end of `userdata`, mount ext4.
4. Read `ostree=` from the BLS entry in `/sysroot/boot/loader/entries` (not baked into the boot image,
   so deployments can change), copy the deployment's `prepare-root.conf`, bind a fake `/proc/cmdline`
   with `ostree=`, run the deployment's own `ostree-prepare-root` through its `ld-linux-aarch64.so.1`
   (composefs is enabled: root becomes an erofs+overlay).
5. Run `/luma/hooks/*.sh` (device files into `/sysroot/etc`, modules tmpfs over `/usr/lib/modules`,
   firmware to `/run`, Mesa G78 stop-gap, debug SSH).
6. `mount --move` `/run`, `/dev`, `/proc`, `/sys`; kill debug daemons; `switch_root` to systemd.

## Order of work and what each step needed

| Step | Result | Key fix |
|---|---|---|
| Kernel from nura (`tensor-exynos/linux` @e8f42849, 7.3-rc6) + config fragment | builds | add SELinux, binder/binderfs, dma-buf heaps, overlay/erofs built-in, pstore, netfilter set |
| v1 boot | hung at Google logo, ABL fell back after 3 tries | **remove `earlycon`/`console=ttySAC0`** (UART off) |
| v2 | kernel+init alive (proved by `reboot("bootloader")` from init) | `nvmem-reboot-mode` works; tiny no-libc `luma-reboot` |
| v3 | USB gadget | `CONFIG_TYPEC_TCPCI_MAXIM=y` (PHY/dwc3 wait for the Type-C role/orientation switch) |
| v4 | framebuffer, touch, PMIC regulators | `EXYNOS_MBOX=y`, `EXYNOS_ACPM_CLK=y` (ACPM → S2MPG10/11 regulators); modules uncompressed (`# CONFIG_MODULE_COMPRESS is not set`, busybox modprobe cannot read zstd) |
| v5–v8 | Luma reaches systemd and GDM | busybox applet links (all 305); `/run` must be a tmpfs to move; root key under `/etc/ssh`; **keep `ostree=` in `/proc/cmdline` for systemd generators** (`var.mount`, `ostree-remount`) |
| v8 | GDM runs | `LumaRoot` is 10 GB → `/var` full → `luma-app-baseline` (flatpak import) fails → GDM dependency fails. `resize2fs` online on the loop (it spans to the end of userdata) |
| v9–v10 | clean boot | mask `bootloader-update` and `greenboot-healthcheck` (GRUB-only); growfs unit |
| v10–v11 | GPU | omarchy-mobile PR #3 (G78 in panfrost, `GPU_QUIRK_FORCE_AARCH64_PGTABLE`) merged with nura's partial gs101 entry; Mesa stop-gap (below) |
| v12–v14 | Wi-Fi | omarchy-mobile PR #143 commits 1–33 + 9080c4a7 + gs101 PHY variant + DT; extend `soc@0` ranges to 2 GiB (PCIe window at 0x60000000); firmware to `/run` before systemd |
| v15 | flatpak apps start | unmount the fake `/proc/cmdline` after `var.mount`: a bind over `/proc` makes procfs "not fully visible" and **bwrap cannot mount proc** |
| v16–v18 | Bluetooth | omarchy-mobile PR #6 (APM CMU mux fix, APM USI1 UART, hci_bcm) + `btbcm patchram_nowait=1` (18e52ffa15): the BCM4389 loader does not ACK each Write RAM record |
| v19 | GPU in flatpaks | local flatpak GL extensions `*.Platform.GL.bluejay` + `FLATPAK_GL_DRIVERS=bluejay:default` |
| v20 | slot A stays bootable | mark `successful` in `devinfo` like Google's bootctrl HAL |
| v21 | firewalld works | conntrack helpers (SIP, H323, IRC, NETBIOS_NS, SNMP, PPTP, SANE, AMANDA) as modules |

## Findings worth knowing before touching gs101

- **ABL** passes a DTB with `sec_dram`/`sec_pt` reserved regions added, replaces `console=` with
  `console=null`, appends `bootconfig`. `fastboot boot` uses the **active slot's flashed vendor_boot**,
  so it cannot test a new DTB; test by writing slot A instead.
- **devinfo** (`/dev/sdd1`, on the 4th UFS LUN): 128 bytes, magic `DEVI` (0x49564544), version ≥ 3.3;
  slot data at offset 48 + 4·i: `retry_count`, then flags bit0 unbootable, bit1 successful, bit2 active,
  bit3 fastboot_ok. Without `successful`, ABL decrements retries each boot and falls back after 3.
  `fastboot --set-active` resets it. Source: AOSP `device/google/gs-common/bootctrl/aidl`.
- **ramoops** at the stock location (0xfd3ff000, 4 MiB) is described but came back empty after a
  spontaneous reset; do not rely on it yet.
- **PCIe Wi-Fi**: gs201's `pcie_1` (GEN4A_1, HSI2) has the same addresses as gs101's. The gs101 PHY
  differs from gs201 only in tables: no 38.4 MHz input-clock block, own TX/RX tuning, no PCS 0x184 /
  0x190 writes (Google's `pcie-exynos-gs101-rc-cal.c`, `google-modules/soc/gs`
  `android-gs-raviole-6.1-android16` @204078758737). Stock bluejay: 1 lane, Gen2, I/A on,
  WL_REG_ON gpp14-2, host wake gpa7-0, PHY rails LDO17M/LDO19M (from the CP2A `dtbo`, board 0x20506).
- **Bluetooth** lines on bluejay equal raven's: BT_REG_ON gpp16-2, dev wake gpp14-3, host wake gpa6-6.
  btbcm has no name for the 4389 and loads `brcm/BCM.hcd`.
- **Mesa**: Mesa 26.2.5 has no `PAN_PROD_ID(9,2,2)` (G78). The G78 shares the G57 `(9,0,3)` entry's
  parameters, so the stop-gap tool `luma-g78-gallium` rewrites that one `gpu_prod_id` in a RAM copy
  of `libgallium` (matched by content: header + 9 tail words, exactly one hit required, plus an
  SHA-256 allow-list for the host copy). PanVK in 26.2.5 is built only for arch 6/7/10/12/13/14, so
  **no Vulkan on v9**.
- **On-screen keyboard (mutter 50.4)**: for `zwp_text_input_v3` version-1 clients the panel opens only
  when an already-focused client re-enables. Qt (Telegram) enables once per window; GTK in flatpaks
  defaulted to IBus via the portal (no text-input at all); Chromium needs
  `--enable-wayland-ime --wayland-text-input-version=3`. Fix in this repo: global flatpak env
  overrides + `device/shell-extension/luma-bluejay-osk@luma.local`, which opens the keyboard when a
  recent touch focuses a text field.
- **Host networking**: the ostree pull is latency bound (~22 objects/s, HTTP/1.1, 8 parallel
  requests); no from-scratch static delta exists. The PC's MediaTek Wi-Fi with power save on did not
  answer the phone's ARP, which looked like a phone firewall problem; tracing with an nftables
  `meta nftrace` rule in a private table showed the phone accepting and replying.

## How to verify a build (do this every time)

1. `scripts/deploy-candidate.sh <name>` (reboots to fastboot over SSH, flashes A, waits for SSH).
2. `systemctl --failed` is empty; GDM active; `luma` on seat0.
3. `dmesg | grep luma-bluejay` shows every hook.
4. GPU: `python3 egl-renderer.py` prints Panfrost and a correct readback.
5. Wi-Fi associated with real HTTPS traffic; Bluetooth `btmgmt find` returns devices.
6. Three plain `systemctl reboot` in a row stay on slot A (`luma-bluejay-slot-ok.sh` dry-run).

## Open items (in priority order)

1. Spontaneous reset after ~5 min once (memory pressure / panfrost shrinker in the log, empty pstore).
2. Audio and microphones: all go through the AoC DSP; only gs201 AoC drivers exist in omarchy-mobile.
3. Modem (Samsung S5123 over PCIe, `pcie_0`), cameras (IMX363/386/355, no gs101 CSIS driver).
4. Suspend/resume, sensors, GPS, real Bluetooth address, display driver (DECON/DSIM + S6E3FC3 panel).
5. Copy firmware from the phone's own `vendor` partition at first boot instead of by hand.
6. Upstream: Mesa G78 entry; Luma: mask GRUB-only units on phones, keyboard fix for v1 text-input
   clients; replace the `/proc/cmdline` bind with a proper `ostree=` source; SELinux labels for files
   the hooks write (the debug build boots with `enforcing=0`).
7. A release variant without the debug initramfs, SSH and `enforcing=0`.
