#!/bin/sh
# Firmware del dispositivo (copiato dalla partizione vendor del telefono, non ridistribuito) da /var a /run,
# così è disponibile per udev fin dall'avvio di systemd (firmware_class.path=/run/luma-bluejay/firmware).
# /var dello stateroot: ostree-prepare-root lo monta qui (il /var del deployment è vuoto e in sola lettura)
src=/sysroot/sysroot/ostree/deploy/luma/var/lib/luma-bluejay/firmware
[ -d $src ] || { echo "luma-bluejay: nessun firmware in /var/lib/luma-bluejay/firmware" > /dev/kmsg; exit 0; }
mkdir -p /run/luma-bluejay/firmware
cp -a $src/. /run/luma-bluejay/firmware/
echo "luma-bluejay: firmware in /run ($(find /run/luma-bluejay/firmware -type f | wc -l) file)" > /dev/kmsg
