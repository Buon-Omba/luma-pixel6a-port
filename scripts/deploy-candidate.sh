#!/bin/bash
# Installa un candidato nello slot A del Pixel 6a e aspetta Luma.
# Uso: scripts/deploy-candidate.sh <nome>   (build/candidates/<nome>)
set -uo pipefail
P=$(cd "$(dirname "$0")/.." && pwd); source "$P/env.sh"
C=$P/build/candidates/${1:?nome candidato}; SSH=$P/scripts/bluejay-ssh.sh
SERIAL=${BLUEJAY_SERIAL:-}   # optional: fastboot serial of your phone
(cd "$C" && sha256sum -c --quiet SHA256SUMS) || { echo "checksum errati"; exit 1; }
if ! fastboot devices | grep -q "${SERIAL:-fastboot}"; then
  timeout 30 $SSH 'systemctl reboot --reboot-argument=bootloader 2>/dev/null || { sync; luma-reboot bootloader; }' 2>&1 | grep -v chdir
  for i in $(seq 1 60); do fastboot devices | grep -q "${SERIAL:-fastboot}" && break; sleep 2; done
fi
fastboot devices | grep -q "${SERIAL:-fastboot}" || { echo "telefono non in fastboot"; exit 1; }
[ "$(fastboot getvar product 2>&1 | grep -o 'product: .*')" = "product: bluejay" ] || { echo "non è un bluejay"; exit 1; }
fastboot flash boot_a "$C/boot.img" 2>&1 | tail -1
fastboot flash vendor_boot_a "$C/vendor_boot.img" 2>&1 | tail -1
fastboot --set-active=a 2>&1 | tail -1
fastboot reboot 2>&1 | tail -1
T0=$(date +%s)
until timeout 20 $SSH 'test -e /run/ostree-booted' >/dev/null 2>&1 || [ $(( $(date +%s) - T0 )) -gt 240 ]; do sleep 5; done
echo "Luma raggiungibile dopo $(( $(date +%s) - T0 )) s"
