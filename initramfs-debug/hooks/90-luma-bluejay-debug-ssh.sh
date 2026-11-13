#!/bin/sh
# SOLO VARIANTE DEBUG: sshd root solo chiave e rete USB link-local. Mai in una release.
e=/sysroot/etc; v=/sysroot/sysroot/ostree/deploy/luma/var   # /var dello stateroot (montato da prepare-root)
[ -d $e ] && [ -d $v ] || exit 0
mkdir -p $e/ssh/sshd_config.d
# root (chiave di debug) solo dal link USB; gli altri utenti con le proprie chiavi, mai con password
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nMatch User root Address fe80::*%%usb0,172.16.42.*\n\tPermitRootLogin prohibit-password\n\tAuthorizedKeysFile .ssh/authorized_keys /etc/ssh/luma-bluejay-debug-keys\n' > $e/ssh/sshd_config.d/10-luma-bluejay-debug.conf
install -m 0644 /etc/luma/authorized_keys $e/ssh/luma-bluejay-debug-keys
mkdir -p $v/roothome/.ssh; chmod 700 $v/roothome/.ssh
cp /etc/luma/authorized_keys $v/roothome/.ssh/authorized_keys; chmod 600 $v/roothome/.ssh/authorized_keys
mkdir -p $e/systemd/system/multi-user.target.wants
ln -sfn /usr/lib/systemd/system/sshd.service $e/systemd/system/multi-user.target.wants/sshd.service
n=$e/NetworkManager/system-connections/luma-bluejay-usb0.nmconnection
mkdir -p ${n%/*}
printf '[connection]\nid=luma-bluejay-usb0\ntype=ethernet\ninterface-name=usb0\nautoconnect=true\n[ipv4]\nmethod=disabled\n[ipv6]\nmethod=link-local\n' > $n; chmod 600 $n
echo "luma-bluejay: debug ssh attivo (solo chiave)" > /dev/kmsg
