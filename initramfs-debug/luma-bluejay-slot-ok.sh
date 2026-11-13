#!/bin/sh
# Segna lo slot A come avviato con successo in devinfo, come fa il boot control HAL di Google per gs101
# (device/google/gs-common bootctrl/aidl, DevInfo.h): 128 byte, magic "DEVI", versione >= 3.3,
# slot[i] a offset 48+4*i: retry_count, poi bit 0 unbootable, 1 successful, 2 active, 3 fastboot_ok.
# Luma sta solo nello slot A: scrive solo se A è lo slot attivo. Uso: luma-bluejay-slot-ok.sh [--write]
set -eu
DEV=""
for p in /sys/class/block/sd*; do grep -qx PARTNAME=devinfo "$p/uevent" 2>/dev/null && DEV=/dev/${p##*/}; done
[ -n "$DEV" ] || { echo "devinfo non trovato"; exit 1; }
T=$(mktemp); trap 'rm -f "$T" "$T.new"' EXIT
dd if="$DEV" of="$T" bs=128 count=1 status=none
b() { od -An -tu1 -j "$1" -N 1 "$T" | tr -d ' '; }
magic=$(od -An -tx4 -N 4 "$T" | tr -d ' ')
maj=$(od -An -tu2 -j 4 -N 2 "$T" | tr -d ' '); mnr=$(od -An -tu2 -j 6 -N 2 "$T" | tr -d ' ')
[ "$magic" = 49564544 ] || { echo "magic devinfo inatteso ($magic): non tocco niente"; exit 1; }
[ $((maj * 65536 + mnr)) -ge $((3 * 65536 + 3)) ] || { echo "versione devinfo $maj.$mnr < 3.3: non tocco niente"; exit 1; }
fa=$(b 49); fb=$(b 53); ra=$(b 48)
echo "devinfo $DEV v$maj.$mnr: A retry=$ra flags=$fa, B flags=$fb"
[ $((fa & 4)) -ne 0 ] && [ $((fb & 4)) -eq 0 ] || { echo "lo slot attivo non è A: non tocco niente"; exit 1; }
[ $((fa & 2)) -eq 0 ] || { echo "slot A già segnato successful"; exit 0; }
[ "${1:-}" = --write ] || { echo "prova a vuoto: scriverei il bit successful dello slot A (byte 49: $fa -> $((fa | 2)))"; exit 0; }
cp "$T" "$T.new"
printf "$(printf '\\%03o' $((fa | 2)))" | dd of="$T.new" bs=1 seek=49 conv=notrunc status=none
# solo il byte 49 deve cambiare
[ "$(cmp -l "$T" "$T.new" | wc -l)" = 1 ] || { echo "differenza inattesa: annullo"; exit 1; }
dd if="$T.new" of="$DEV" bs=128 count=1 conv=notrunc,fsync status=none
dd if="$DEV" of="$T" bs=128 count=1 status=none
cmp -s "$T" "$T.new" && echo "slot A segnato successful (riletto e verificato)" || { echo "rilettura diversa!"; exit 1; }
