#!/bin/sh
# Avvio di Luma dall'initramfs (Pixel 6a). Sorgente con ". /luma-boot.sh" da /init.
# userdata contiene un disco GPT con settori da 4096 (builder Luma): p1 LumaBoot (FAT, vuota), p2 LumaRoot (ext4).
# Il percorso ostree= viene letto dalla voce BLS del deployment, non è fisso nel boot image.
log() { echo "luma-boot: $*" > /dev/kmsg; }

luma_find_userdata() {
	for p in /sys/class/block/sda*; do
		grep -qx 'PARTNAME=userdata' "$p/uevent" 2>/dev/null && { echo "/dev/${p##*/}"; return 0; }
	done
	return 1
}

# intero little-endian a 32/64 bit dal file $1 all'offset $2 (busybox hexdump non fa 8 byte)
u32() { dd if="$1" bs=1 skip="$2" count=4 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
u64() { lo=$(u32 "$1" "$2"); hi=$(u32 "$1" $(($2 + 4))); echo $(( hi * 4294967296 + lo )); }

# Legge da un disco GPT a 4096 byte/settore: offset e lunghezza in byte della partizione con nome $2
luma_gpt_part() {
	dev=$1; want=$2
	[ "$(dd if=$dev bs=4096 skip=1 count=1 2>/dev/null | dd bs=8 count=1 2>/dev/null)" = "EFI PART" ] || return 1
	# header LBA1: entries LBA @72 (8 byte), n entries @80, size entry @84
	hdr=$(u64 $dev $((4096 + 72)))
	n=$(u32 $dev $((4096 + 80)))
	esz=$(u32 $dev $((4096 + 84)))
	i=0
	while [ $i -lt $n ] && [ $i -lt 16 ]; do
		off=$(( hdr * 4096 + i * esz ))
		name=$(dd if=$dev bs=1 skip=$((off + 56)) count=72 2>/dev/null | tr -d '\000')
		if [ "$name" = "$want" ]; then
			first=$(u64 $dev $((off + 32)))
			last=$(u64 $dev $((off + 40)))
			echo "$((first * 4096)) $(( (last - first + 1) * 4096 ))"
			return 0
		fi
		i=$((i + 1))
	done
	return 1
}

luma_mount_root() {
	ud=$(luma_find_userdata) || { log "userdata non trovato"; return 1; }
	r=$(luma_gpt_part "$ud" LumaRoot) || { log "LumaRoot non trovato in $ud (userdata senza disco Luma?)"; return 1; }
	set -- $r
	# loop a partire da LumaRoot fino alla fine di userdata: l'ext4 si può poi allargare online
	loop=$(losetup -f) || return 1
	losetup -o "$1" "$loop" "$ud" || { log "losetup fallito"; return 1; }
	mkdir -p /sysroot
	mount -t ext4 -o rw,noatime "$loop" /sysroot || { log "mount ext4 fallito su $loop"; losetup -d "$loop"; return 1; }
	log "LumaRoot montato da $ud offset $1 ($loop)"
	echo "$loop" > /run/luma-root-loop
}

luma_ostree_path() {
	e=$(ls /sysroot/boot/loader/entries/*.conf 2>/dev/null | sort | tail -1)
	[ -n "$e" ] || return 1
	sed -n 's/^options .*ostree=\([^ ]*\).*/\1/p' "$e" | head -1
}

luma_switch() {
	op=$(luma_ostree_path) || { log "nessuna voce BLS"; return 1; }
	[ -e "/sysroot$op" ] || { log "percorso ostree $op assente"; return 1; }
	dep=$(readlink -f "/sysroot$op")
	log "deployment $op -> $dep"
	# ostree-prepare-root del deployment (glibc), con la sua config; ostree= via /proc/cmdline finto
	mkdir -p /usr/lib/ostree /etc/ostree
	[ -f "$dep/usr/lib/ostree/prepare-root.conf" ] && cp "$dep/usr/lib/ostree/prepare-root.conf" /usr/lib/ostree/
	[ -f "$dep/etc/ostree/prepare-root.conf" ] && cp "$dep/etc/ostree/prepare-root.conf" /etc/ostree/
	printf '%s ostree=%s\n' "$(cat /proc/cmdline)" "$op" > /run/luma-cmdline
	mount --bind /run/luma-cmdline /proc/cmdline
	ld=$(ls "$dep"/usr/lib/ld-linux-aarch64.so.1 "$dep"/usr/lib64/ld-linux-aarch64.so.1 2>/dev/null | head -1)
	pr="$dep/usr/lib/ostree/ostree-prepare-root"
	[ -x "$pr" ] || pr="$dep/usr/libexec/ostree/ostree-prepare-root"
	if ! "$ld" --library-path "$dep/usr/lib64:$dep/usr/lib" "$pr" /sysroot > /run/luma-prepare-root.log 2>&1; then
		log "ostree-prepare-root fallito: $(tail -3 /run/luma-prepare-root.log | tr '\n' ' ')"
		umount /proc/cmdline; return 1
	fi
	# /proc/cmdline con ostree= resta montato: passa a systemd con /proc (generatore var.mount, ostree-remount)
	log "prepare-root ok: $(tail -2 /run/luma-prepare-root.log | tr '\n' ' ')"
	# Hook di dispositivo (file in /sysroot/etc, rifatti a ogni avvio come sul Pixel 9)
	for h in /luma/hooks/*.sh; do [ -f "$h" ] && sh "$h"; done
	# /run passa a systemd (contiene /run/ostree-booted e i log di questo stadio)
	mkdir -p /sysroot/run
	kill $(cat /run/dropbear.pid 2>/dev/null) 2>/dev/null
	mount --move /run /sysroot/run 2>/dev/null || log "move /run fallito"
	for m in /dev /proc /sys; do mount --move $m /sysroot$m 2>/dev/null; done
	# i servizi di debug dell'initramfs non devono sopravvivere al cambio di root
	kill $(cat /run/dropbear.pid 2>/dev/null) $LUMA_ACM_PID 2>/dev/null
	log "switch_root su systemd"
	exec switch_root /sysroot /usr/lib/systemd/systemd
}
