#!/bin/bash
# Compila il kernel nura gs101 + opzioni Luma per Pixel 6a (bluejay). Solo host, non tocca il telefono.
# Uso: scripts/build-kernel.sh   (output in build/kernel, log in build/kernel.log)
set -euo pipefail
P=$(cd "$(dirname "$0")/.." && pwd)
source "$P/env.sh"
KCOMMIT=e8f42849a581ea8e915ad0f10c25951e696dc6b5
SRC=$P/build/linux-src
O=$P/build/kernel
JOBS=${JOBS:-6}
# Albero pulito dal tarball verificato + patch del port
if [ ! -f "$SRC/.luma-patched" ]; then
  rm -rf "$SRC"; mkdir -p "$SRC"
  cp -a "$P/sources/linux-$KCOMMIT/." "$SRC/"
  for p in "$P"/kernel/patches/*.patch "$P"/kernel/patches-omarchy/*.patch; do patch -d "$SRC" -p1 --no-backup-if-mismatch < "$p"; done
  touch "$SRC/.luma-patched"
fi
mkdir -p "$O"
cp "$P/kernel/base-nura.config" "$O/.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$P/kernel/luma-bluejay.fragment" >/dev/null
M="make -C $SRC O=$O ARCH=arm64 LLVM=1 KBUILD_BUILD_USER=luma KBUILD_BUILD_HOST=bluejay-port"
$M olddefconfig >/dev/null
# Verifica che le opzioni richieste siano rimaste (Kconfig scarta in silenzio le dipendenze mancanti)
miss=0
while IFS= read -r l; do
  case "$l" in CONFIG_*=*) grep -qxF "$l" "$O/.config" || { echo "MANCA: $l (ora: $(grep -E "^(# )?${l%%=*}[= ]" "$O/.config" || echo assente))"; miss=1; } ;; esac
done < "$P/kernel/luma-bluejay.fragment"
[ "$miss" = 0 ] || echo "ATTENZIONE: opzioni non applicate (sopra)"
nice -n 19 $M -j"$JOBS" Image.lz4 modules dtbs
ls -la "$O/arch/arm64/boot/Image.lz4" "$O/arch/arm64/boot/dts/exynos/google/gs101-bluejay.dtb"
