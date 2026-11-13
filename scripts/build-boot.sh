#!/bin/bash
# Assembla boot.img + vendor_boot.img (header v4, stile nura/Linaro) per Pixel 6a (bluejay).
# Solo host: non contatta né scrive il telefono.
# Uso: scripts/build-boot.sh <nome-candidato>   → build/candidates/<nome>/{boot.img,vendor_boot.img,SHA256SUMS,manifest.env}
set -euo pipefail
P=$(cd "$(dirname "$0")/.." && pwd)
source "$P/env.sh"
NAME=${1:?nome candidato}
K=$P/build/kernel
OUT=$P/build/candidates/$NAME
AL=$P/sources/alpine/x
STOCK=$P/sources/stock/img
KEY=$P/hosttools/avb/test/data/testkey_rsa4096.pem
PART_BYTES=67108864          # boot_b e vendor_boot_b: 64 MiB (uguale allo stock)
BOOT_ROLLBACK=1751673600     # rollback index del boot stock BP2A.250705.008
CMDLINE=${CMDLINE:-"clk_ignore_unused regulator_ignore_unused console=tty0 loglevel=7 printk.devkmsg=on log_buf_len=1024K enforcing=0 firmware_class.path=/run/luma-bluejay/firmware"}

[ -e "$OUT" ] && { echo "esiste già: $OUT"; exit 1; }
for f in "$K/arch/arm64/boot/Image.lz4" "$K/arch/arm64/boot/dts/exynos/google/gs101-bluejay.dtb" "$KEY"; do
  [ -f "$f" ] || { echo "manca $f"; exit 1; }
done
mkdir -p "$OUT"; W=$(mktemp -d "$P/build/.ramfs.XXXX"); trap 'rm -rf "$W"' EXIT

# --- initramfs di debug
R=$W/root
mkdir -p $R/{bin,sbin,usr/bin,usr/sbin,lib,usr/lib,etc/luma,etc/dropbear,proc,sys,dev,run,tmp,root,sys/fs/pstore}
cp "$AL"/busybox-static-*/bin/busybox.static $R/bin/busybox
for a in $(cat "$P/initramfs-debug/applets"); do ln -sf busybox $R/bin/$a; done
cp "$AL"/musl-*/lib/ld-musl-aarch64.so.1 $R/lib/
cp -P "$AL"/zlib-*/usr/lib/libz.so* "$AL"/utmps-libs-*/usr/lib/libutmps.so* "$AL"/skalibs-libs-*/usr/lib/libskarnet.so* $R/usr/lib/
cp "$AL"/dropbear-*/usr/sbin/dropbear $R/usr/sbin/
install -m 0755 "$P/initramfs-debug/luma-reboot" $R/bin/luma-reboot
install -m 0755 "$P/initramfs-debug/luma-devmem" $R/bin/luma-devmem
install -m 0755 "$P/initramfs-debug/luma-g78-gallium" $R/bin/luma-g78-gallium
# moduli del kernel (strip) per il coldplug
KR=$(cat $K/include/config/kernel.release)
# Albero completo dei moduli per Luma (hook 10 lo monta su /usr/lib/modules) in /luma/modules
make -s -C "$P/build/linux-src" O="$K" ARCH=arm64 LLVM=1 INSTALL_MOD_PATH=$R/luma INSTALL_MOD_STRIP=1 modules_install >/dev/null
mv $R/luma/lib/modules $R/luma/modules && rmdir $R/luma/lib
rm -f $R/luma/modules/*/build $R/luma/modules/*/source
# Copia per l'initramfs (hardlink): senza Wi-Fi e Bluetooth, il cui firmware arriva solo con LumaRoot;
# li carica poi udev di Luma.
mkdir -p $R/lib/modules && cp -al $R/luma/modules/$KR $R/lib/modules/$KR
rm -rf $R/lib/modules/$KR/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac $R/lib/modules/$KR/kernel/drivers/bluetooth
depmod -b $R "$KR"
install -m 0755 "$P/initramfs-debug/init" $R/init
install -m 0644 "$P/initramfs-debug/luma-boot.sh" $R/luma-boot.sh
mkdir -p $R/luma && install -m 0755 "$P/initramfs-debug/luma-bluejay-flatpak-gl.sh" $R/luma/
install -m 0755 "$P/initramfs-debug/luma-bluejay-slot-ok.sh" $R/luma/
mkdir -p $R/luma/hooks; for h in "$P"/initramfs-debug/hooks/*.sh; do [ -f "$h" ] && install -m 0755 "$h" $R/luma/hooks/; done
cp "$P/hosttools/ssh/bluejay_ed25519.pub" $R/etc/luma/authorized_keys
printf 'root:x:0:0:root:/root:/bin/sh\n' > $R/etc/passwd
printf 'root:x:0:\n' > $R/etc/group
printf '/bin/sh\n' > $R/etc/shells
( cd $R && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet ) > $W/initramfs.cpio
zstd -q -19 $W/initramfs.cpio -o $W/initramfs.cpio.zst

# --- immagini v4 (indirizzi = default mkbootimg = stock: kernel 0x10008000, ramdisk 0x11000000, dtb 0x11f00000)
cp "$K/arch/arm64/boot/dts/exynos/google/gs101-bluejay.dtb" $W/dtb.img
mkbootimg --header_version 4 \
  --kernel "$K/arch/arm64/boot/Image.lz4" \
  --dtb $W/dtb.img \
  --vendor_ramdisk $W/initramfs.cpio.zst \
  --vendor_cmdline "$CMDLINE" \
  --pagesize 4096 \
  --vendor_boot "$OUT/vendor_boot.img" \
  -o "$OUT/boot.img"

# --- footer AVB come lo stock: boot firmato (chiave TEST AOSP), vendor_boot hash non firmato
avbtool add_hash_footer --image "$OUT/boot.img" --partition_size $PART_BYTES --partition_name boot \
  --hash_algorithm sha256 --algorithm SHA256_RSA4096 --key "$KEY" --rollback_index $BOOT_ROLLBACK \
  --append_to_release_string " Luma bluejay debug; AOSP test key"
avbtool add_hash_footer --image "$OUT/vendor_boot.img" --partition_size $PART_BYTES --partition_name vendor_boot \
  --hash_algorithm sha256
avbtool info_image --image "$OUT/boot.img" > "$OUT/boot.avb.txt"
avbtool info_image --image "$OUT/vendor_boot.img" > "$OUT/vendor_boot.avb.txt"

# --- verifica a ritroso
unpack_bootimg --boot_img "$OUT/boot.img" --out $W/u1 >/dev/null
unpack_bootimg --boot_img "$OUT/vendor_boot.img" --out $W/u2 > "$OUT/vendor_boot.unpack.txt"
cmp $W/u1/kernel "$K/arch/arm64/boot/Image.lz4"
cmp $W/u2/dtb $W/dtb.img
cmp $W/u2/vendor_ramdisk00 $W/initramfs.cpio.zst 2>/dev/null || cmp $W/u2/vendor_ramdisk $W/initramfs.cpio.zst
for f in boot.img vendor_boot.img; do [ "$(stat -c %s "$OUT/$f")" = $PART_BYTES ] || { echo "$f non è $PART_BYTES byte"; exit 1; }; done

{
  echo "NAME=$NAME"
  echo "KERNEL_COMMIT=e8f42849a581ea8e915ad0f10c25951e696dc6b5"
  echo "KERNEL_RELEASE=$(cat $K/include/config/kernel.release)"
  echo "PORT_GIT=$(git -C "$P" rev-parse HEAD)$(git -C "$P" diff --quiet || echo -dirty)"
  echo "CMDLINE=$CMDLINE"
  echo "VARIANT=debug (dropbear root solo chiave, NCM 172.16.42.1)"
  echo "AVB=boot: chiave test AOSP; vendor_boot: hash non firmato; vbmeta NON modificato"
  echo "PHONE_ACCESSED=false"
} > "$OUT/manifest.env"
( cd "$OUT" && sha256sum boot.img vendor_boot.img > SHA256SUMS && cat SHA256SUMS )
