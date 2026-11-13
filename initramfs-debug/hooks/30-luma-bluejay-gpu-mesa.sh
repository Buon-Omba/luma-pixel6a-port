#!/bin/sh
# RIPIEGO finché Luma (e le estensioni GL flatpak) non distribuiscono Mesa con il Mali-G78
# (patch condivisa da proporre upstream: omarchy-mobile mesa 0004).

# 1) Sistema: solo per la libgallium esatta di Mesa 26.2.5 fc44, copia in RAM con la voce G78 e bind
#    sopra quella di sistema. Qualsiasi altra Mesa: nessuna modifica (resta llvmpipe).
host_gallium() {
	L=/sysroot/usr/lib64/libgallium-26.2.5.so
	ORIG=25ea48a0881b8c4b976dbf75ceb99a7d62be5b719ac5bafeb5fda8400b1a4784
	NEW=86efed533dc03a0fcbdd6df9548f14ca2a326129d0d6e77533e2bfd6a667d71c
	[ -f $L ] || return 0
	[ "$(sha256sum $L | cut -d' ' -f1)" = $ORIG ] || { echo "luma-bluejay: libgallium diversa, niente G78" > /dev/kmsg; return 0; }
	mkdir -p /run/luma-bluejay
	O=/run/luma-bluejay/libgallium-26.2.5.so
	luma-g78-gallium $L $O && [ "$(sha256sum $O | cut -d' ' -f1)" = $NEW ] && mount --bind $O $L &&
		echo "luma-bluejay: libgallium con Mali-G78 (ripiego)" > /dev/kmsg
}

# 2) Flatpak: estensioni GL locali "bluejay" (luma-bluejay-flatpak-gl.sh) create all'avvio da un servizio,
#    usate con FLATPAK_GL_DRIVERS=bluejay:default (default come riserva). La modifica cerca la voce G57 per contenuto: se una Mesa futura
#    non la ha, quella branch viene saltata.
flatpak_gl() {
	mkdir -p /run/luma-bluejay/bin
	cp /bin/luma-g78-gallium /luma/luma-bluejay-flatpak-gl.sh /run/luma-bluejay/bin/
	e=/sysroot/etc; s=$e/systemd/system
	[ -d $e ] || return 0
	mkdir -p $s/multi-user.target.wants $e/environment.d $e/profile.d
	printf '[Unit]\nDescription=Pixel 6a: estensioni GL flatpak con Mali-G78 (ripiego)\nAfter=local-fs.target\nConditionPathExists=/run/luma-bluejay/bin/luma-bluejay-flatpak-gl.sh\n[Service]\nType=oneshot\nExecStart=/bin/sh /run/luma-bluejay/bin/luma-bluejay-flatpak-gl.sh\n[Install]\nWantedBy=multi-user.target\n' > $s/luma-bluejay-flatpak-gl.service
	ln -sfn ../luma-bluejay-flatpak-gl.service $s/multi-user.target.wants/luma-bluejay-flatpak-gl.service
	printf 'FLATPAK_GL_DRIVERS=bluejay:default\n' > $e/environment.d/60-luma-bluejay-gl.conf
	printf 'export FLATPAK_GL_DRIVERS=bluejay:default\n' > $e/profile.d/luma-bluejay-gl.sh
	echo "luma-bluejay: GL flatpak bluejay configurato" > /dev/kmsg
}

host_gallium
flatpak_gl
exit 0
