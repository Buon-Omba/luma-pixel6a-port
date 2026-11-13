#!/bin/bash
# SSH root al Pixel 6a (initramfs di debug) via USB NCM, IPv6 link-local (scoperta con ping multicast).
# Host key rigenerata a ogni boot dall'initramfs di debug: non viene salvata (solo link USB diretto).
P=$(cd "$(dirname "$0")/.." && pwd)
O=(-i "$P/hosttools/ssh/bluejay_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=5)
for try in 1 2 3 4 5 6 7 8 9 10; do
for i in /sys/class/net/*; do
  n=${i##*/}; d=$(readlink -f $i/device 2>/dev/null) || continue
  case "$d" in */usb*) ;; *) continue;; esac
  mine=$(ip -6 addr show dev "$n" | grep -o 'fe80[^/]*' | head -1)
  a=$(ping -6 -c2 -W1 "ff02::1%$n" 2>/dev/null | grep -o 'from fe80[^ %]*' | awk '{print $2}' | grep -vx "$mine" | head -1)
  [ -n "$a" ] && exec ssh "${O[@]}" ${LUMA_SSH_EXTRA:-} "root@$a%$n" "$@"
done
sleep 1
done
echo "telefono non raggiungibile via USB"; exit 1
