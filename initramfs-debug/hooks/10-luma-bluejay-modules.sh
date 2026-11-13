#!/bin/sh
# I moduli del kernel del boot image non sono nel commit OS (che porta quelli Fedora):
# montali sopra /usr/lib/modules del deployment, solo per questo avvio.
kr=$(uname -r)
[ -d /luma/modules/$kr ] && [ -d /sysroot/usr/lib/modules ] || exit 0
mount -t tmpfs -o mode=0755,size=64m luma-modules /sysroot/usr/lib/modules || exit 0
cp -a /luma/modules/$kr /sysroot/usr/lib/modules/
echo "luma-bluejay: moduli $kr su /usr/lib/modules" > /dev/kmsg
