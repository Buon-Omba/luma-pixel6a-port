#!/bin/sh
# RIPIEGO Mali-G78 per i flatpak, finché le estensioni GL di Mesa non conoscono il G78:
# per ogni estensione GL.default installata crea un'estensione locale "<punto>.bluejay" (hardlink, più una
# libgallium copiata e corretta come nuovo file) in /var/lib/flatpak/extension. Flatpak la usa con
# FLATPAK_GL_DRIVERS=bluejay. Idempotente: rifà una branch solo se la GL.default sorgente è cambiata.
set -u
TOOL=${TOOL:-/run/luma-bluejay/bin/luma-g78-gallium}
EXT=/var/lib/flatpak/extension
for dir in /var/lib/flatpak/runtime/*.Platform.GL.default/aarch64/*/active; do
	[ -d "$dir/files" ] || continue
	point=$(echo "$dir" | sed 's|/var/lib/flatpak/runtime/\(.*\)\.default/aarch64/.*|\1|')
	branch=$(basename "$(dirname "$dir")")
	case "$branch" in *-extra) continue ;; esac
	src=$(readlink -f "$dir")
	dst=$EXT/$point.bluejay/aarch64/$branch
	[ "$(cat "$dst/.luma-bluejay-src" 2>/dev/null)" = "$src" ] && continue
	lib=$(cd "$src/files" && find . -name 'libgallium*.so' -type f | head -1)
	[ -n "$lib" ] || continue
	tmp=$dst.new; rm -rf "$tmp"; mkdir -p "$(dirname "$dst")"
	cp -al "$src/files" "$tmp" || continue
	rm -f "$tmp/$lib"
	if "$TOOL" "$src/files/$lib" "$tmp/$lib"; then
		echo "$src" > "$tmp/.luma-bluejay-src"
		rm -rf "$dst"; mv "$tmp" "$dst"
		echo "luma-bluejay: $point.bluejay//$branch con Mali-G78"
	else
		rm -rf "$tmp"; echo "luma-bluejay: $point//$branch: libgallium non riconosciuta, saltata"
	fi
done
