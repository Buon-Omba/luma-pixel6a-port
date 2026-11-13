#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# The GDM autologin and handheld blocks are adapted from SimplyLuma/luma devices/pixel9
# (scripts/mobile/pixel9-tokay/initramfs-hooks/89-luma-tokay-session.sh).
# Pixel 6a sul ARM nightly condiviso: file del dispositivo rimessi a ogni avvio (come sul Pixel 9).
e=/sysroot/etc
[ -d $e ] || exit 0
mkdir -p $e/luma
printf '[update]\n# I telefoni scaricano aggiornamenti solo su richiesta; canale e ref sono quelli ARM condivisi.\nautomatic_download = false\n' > $e/luma/update.conf
# Classe dispositivo: telefono (presentazione Mobile)
[ -s $e/luma-device-class ] || printf 'mobile\n' > $e/luma-device-class
mkdir -p /run/luma; [ -s /run/luma/experience ] || printf 'mobile\n' > /run/luma/experience
if [ ! -e /sysroot/usr/lib/environment.d/90-luma-handheld.conf ]; then
	mkdir -p $e/environment.d
	printf 'LUMA_DEVICE_CLASS=handheld\n' > $e/environment.d/90-luma-handheld.conf
fi
# GDM: accesso automatico dell'utente del telefono (come l'hook 89 del Pixel 9)
if [ -e /sysroot/usr/lib/systemd/system/gdm.service ]; then
	c=$e/gdm/custom.conf
	u=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' $e/passwd 2>/dev/null)
	if [ -n "$u" ] && ! grep -q '^AutomaticLogin=' $c 2>/dev/null; then
		mkdir -p $e/gdm; [ -f $c ] || printf '[daemon]\n' > $c
		grep -q '^\[daemon\]' $c || printf '[daemon]\n' >> $c
		sed -i "s/^\[daemon\]/[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=$u/" $c
	fi
fi
# Finché suspend non è provato: niente sospensione di sistema (vedi checklist)
mkdir -p $e/systemd/sleep.conf.d
printf '[Sleep]\nAllowSuspend=no\nAllowHibernation=no\nAllowSuspendThenHibernate=no\nAllowHybridSleep=no\n' > $e/systemd/sleep.conf.d/90-luma-bluejay-nosuspend.conf
s=$e/systemd/system
mkdir -p $s/local-fs.target.wants
# LumaRoot nasce da 10 GB (immagine): allargalo online fino alla fine di userdata (il loop arriva già fin lì).
# Senza, /var si riempie e luma-app-baseline (e quindi GDM) fallisce.
printf '[Unit]\nDescription=Pixel 6a: allarga LumaRoot fino alla fine di userdata\nDefaultDependencies=no\nAfter=local-fs-pre.target\nBefore=local-fs.target luma-app-baseline.service\n[Service]\nType=oneshot\nExecStart=/bin/sh -c "resize2fs $(findmnt -n -o SOURCE /sysroot)"\n[Install]\nWantedBy=local-fs.target\n' > $s/luma-bluejay-growfs.service
ln -sfn ../luma-bluejay-growfs.service $s/local-fs.target.wants/luma-bluejay-growfs.service
# ostree= arriva a systemd da un bind su /proc/cmdline (vedi luma-boot.sh): serve ai generatori (var.mount)
# e a ostree-remount, poi va tolto, altrimenti /proc non è "fully visible" e bwrap (flatpak) non può montare proc.
mkdir -p $s/sysinit.target.wants
printf '[Unit]\nDescription=Pixel 6a: togli il bind ostree= da /proc/cmdline (flatpak/bwrap)\nDefaultDependencies=no\nAfter=ostree-remount.service var.mount systemd-remount-fs.service\nBefore=sysinit.target\nConditionPathIsMountPoint=/proc/cmdline\n[Service]\nType=oneshot\nExecStart=/usr/bin/umount /proc/cmdline\n[Install]\nWantedBy=sysinit.target\n' > $s/luma-bluejay-cmdline.service
ln -sfn ../luma-bluejay-cmdline.service $s/sysinit.target.wants/luma-bluejay-cmdline.service
# Bluetooth BCM4389: il suo loader non conferma ogni record Write RAM (omarchy-mobile 18e52ffa15)
mkdir -p $e/modprobe.d
printf 'options btbcm patchram_nowait=1\n' > $e/modprobe.d/luma-bluejay-bt.conf
# Slot A/B: dopo un avvio riuscito segna lo slot A "successful" in devinfo (come il boot control HAL di Google),
# altrimenti ABL scala retry_count a ogni avvio e dopo 3 torna allo slot B.
mkdir -p /run/luma-bluejay/bin $s/graphical.target.wants
cp /luma/luma-bluejay-slot-ok.sh /run/luma-bluejay/bin/
printf '[Unit]\nDescription=Pixel 6a: segna lo slot A avviato con successo (devinfo)\nAfter=graphical.target gdm.service\nConditionPathExists=/run/luma-bluejay/bin/luma-bluejay-slot-ok.sh\n[Service]\nType=oneshot\nExecStart=/bin/sh /run/luma-bluejay/bin/luma-bluejay-slot-ok.sh --write\n[Install]\nWantedBy=graphical.target\n' > $s/luma-bluejay-slot-ok.service
ln -sfn ../luma-bluejay-slot-ok.service $s/graphical.target.wants/luma-bluejay-slot-ok.service
# Il telefono non ha GRUB: bootloader-update cerca /boot/grub2 e fallisce a ogni avvio
ln -sfn /dev/null $s/bootloader-update.service
# greenboot segna l'avvio riuscito nel grubenv: sul telefono va fatto segnando lo slot A/B (da fare)
ln -sfn /dev/null $s/greenboot-healthcheck.service
echo "luma-bluejay: file dispositivo installati" > /dev/kmsg
