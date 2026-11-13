# Luma Mobile → Google Pixel 6a (bluejay) — note di port

Tutti gli orari in UTC. Iniziato 2026-11-05.

## Target
- Google Pixel 6a, codename `bluejay`, SoC Google Tensor G1 (gs101, derivato Exynos), Mali-G78 MP20, 6 GB LPDDR5, 128 GB UFS Micron, AMOLED 1080x2400 60 Hz.
- Pannello Samsung S6E3FC3 (nessun driver DSI mainline; nura usa simplefb), touch STM FTS (driver downstream).
- A/B, nessuna microSD → Luma va su `userdata` (come Pixel 9).
- Non supportato ufficialmente da Luma (supportati: Fairphone 6, Unihertz Titan 2 Elite, Pixel 9) → port da "Generic".
- Factory image Google pubbliche: sì (developers.google.com/android/images, bluejay). Da registrare versione + hash.

## Sorgenti (pinned)
- OS: ostree `luma/1/aarch64/nightly` da https://dl.simplyluma.com/os/repo, invariato.
- Disk image builder: SimplyLuma/luma `devices/pixel9:scripts/mobile/pixel9-tokay/compose/build-release-image.sh`
  (passare `REF=luma/1/aarch64/nightly` esplicitamente: il default è un ref tokay). Usa settori 4096 (UFS) — vale anche per il 6a.
- Boot layer da nura (fork/rebrand di postmarketOS; gitlab.postmarketos.org → gitlab.nura.eco):
  - pmaports `https://gitlab.nura.eco/nura/pmaports` @ `31482d7d5233eb4c510337a73f7492d9ed56ac7e` (2026-11-04)
    - `device/testing/device-google-bluejay` (deviceinfo, kernel-cmdline.conf, modules-initfs)
    - `device/testing/linux-postmarketos-gs101` (kernel 7.3-rc6)
    - `device/testing/soc-google-gs101` (hook initramfs: devmem2 0x1c300030=0x3061 per abilitare refresh del framebuffer DECON)
  - Kernel: `https://gitlab.nura.eco/soc/tensor-exynos/linux` @ `e8f42849a581ea8e915ad0f10c25951e696dc6b5`
  - DTB: `exynos/google/gs101-bluejay`
  - Boot image: header v4, pagesize 4096, cmdline `clk_ignore_unused regulator_ignore_unused`, flash vbmeta (pmOS flasha vbmeta con verifica disabilitata).
- Wiki nura (pagina SoC "Google Tensor G1 (GS101)") dietro Anubis: non leggibile in automatico.

## Stato nura (dal wiki)
Y: flashing, USB net, storage, batteria, schermo (simplefb), touch (downstream).
N: Wi-Fi, Bluetooth, GPS, power sensor. Vuoti (non testati): 3D, audio, camera, modem, sensori, haptics.
→ Molte voci della checklist "done" Luma richiederanno lavoro kernel oltre nura.

## Gap kernel per Luma (config nura vs requisiti)
- MANCA SELinux (`CONFIG_SECURITY_SELINUX` non presente) — Luma è Fedora/ostree con SELinux: necessario.
- MANCA binder/binderfs (`ANDROID_BINDER_IPC`, `ANDROID_BINDERFS`) — app Android.
- MANCA pstore/ramoops — debug crash.
- Presenti: NF_TABLES/NFT_NAT/NFT_MASQ (m), DMABUF_HEAPS_SYSTEM, USB_CONFIGFS_NCM, UFS_EXYNOS, S3C2410_WATCHDOG, PANFROST (G78 = Valhall: serve Panthor? da verificare), OVERLAY_FS, EROFS.
- Verificare il resto della lista Luma (kernel/android-netfilter.list nel ramo pixel9).

## Checklist "done" (ogni riga = test che la prova)
- [ ] Boot standalone da flash (no USB, no fastboot boot) fino al lock screen Luma, 3 volte di fila.
- [ ] Display nativo 1080x2400@60; touch preciso ai bordi (tap sintetici 4 angoli + centro); rotazione.
- [ ] USB networking (NCM, IPv6 link-local) per 1 h; ricarica USB con corrente sensata.
- [ ] Wi-Fi: associa, IP, 1 h di traffico + ping al gateway senza stalli + un trasferimento grande.
- [ ] Bluetooth: pairing cuffia, A2DP, riconnessione dopo reboot.
- [ ] Audio: speaker, auricolare, microfono, USB audio: registra e riproduci; niente underrun.
- [ ] Modem: SIM, registrazione, dati (IPv6 literal, hostname, HTTPS, IPv4 via CLAT), chiamata uscente/entrante con audio bidirezionale, SMS e MMS in/out; 5 cold boot.
- [ ] Camera: still + video da ogni sensore, né neri né uniformi, colori corretti.
- [ ] Suspend/resume: pm_test a livelli, poi 20 cicli (power button + chiamata entrante), modem/Wi-Fi ok dopo ognuno.
- [ ] Sensori (accel, prossimità, luce), GPS fix, vibrazione, torcia, percentuale batteria.
- [ ] App Android: app reale con video+audio; digitazione in campo testo.
- [ ] Origin `luma/1/aarch64/nightly`, legge il grafo ARM.
- [ ] Tutto quanto sopra su installazione fresca dall'immagine pubblicata.

## Stock (factory image)
- `bluejay-bp2a.250705.008-factory-128110b0.zip`, sha256 `128110b0979a070522a57c739cce741a3554595a8379d7c95b003286e8348740` (verificato).
- Bootloader `bluejay-16.2-13291547`, baseband `g5123b-145971-250328-B-13284995`. Non flashare MAI bootloader/radio da qui (anti-rollback).
- Estratti in `sources/stock/img/` (+ SHA256SUMS): boot.img (header v4, solo kernel GKI, ramdisk 0), vendor_boot.img
  (header v4, pagesize 2048, dtb 535798 B, 2 vendor ramdisk), dtbo.img, vbmeta.img (SHA256_RSA4096, chain boot/vbmeta_system/vbmeta_vendor).
- Cmdline stock: `earlycon=exynos4210,0x10A00000 console=ttySAC0,115200 ...`
- Installazione nura (dal wiki SoC): flash rootfs, flash kernel (boot), flash vbmeta (verifica disabilitata), `fastboot erase dtbo`;
  ripetere gli ultimi due se il bootloader cambia slot.
- Come caricano il DTB mainline:
  - nura (boot-deploy, header v4): genera boot.img (solo kernel) + vendor_boot.img (DTB + initramfs + cmdline);
    `flash_kernel` scrive boot e vendor_boot, poi vbmeta disabilitato, poi `erase dtbo` (altrimenti ABL applica gli overlay stock).
  - Linaro pixelscripts: stesso schema (boot + vendor_boot, erase dtbo, `fastboot oem disable-verification`).
  - Luma Pixel 9: scrive SOLO boot_a. DTB e initramfs linkati nel kernel (patch 0001/0003 linux-zumapro: head.S sostituisce x0
    con il DTB embedded, unflatten_and_copy_device_tree), CMDLINE_FORCE, footer AVB con chiave test AOSP, padding a 64 MiB.
    Le carve-out no-map del bootloader importate dall'FDT del bootloader (tokay-daily1/0005, luma_boot_fdt.c, non nel repo).
    Vantaggio: `fastboot boot` funziona senza scrivere nulla; vendor_boot/dtbo/vbmeta restano stock.
  - gs101 mainline NON ha nodo /memory (lo inserisce ABL): con DTB embedded va importato dall'FDT del bootloader.
- Hardware (wiki SoC): Wi-Fi/BT BCM4389 PCIe, modem Samsung S5123 (Shannon, PCIe), GPS BCM4775 SPI, amp CS35L41 SPI,
  haptics CS40L25A, PMIC MAX77759/S2MPG10/S2MPG11, charger PCA9468. Riferimenti: gitlab.com/LinaroLtd/googlelt/pixelscripts,
  android.googlesource.com/kernel/google-modules/raviole-device (android-gs-raviole-mainline).

## Host di sviluppo
- CachyOS, 8 core, 15 GiB RAM, /home 163 GB liberi; /tmp è tmpfs (non usarlo per build).
- Presenti: clang 23.1.4, lld, llvm, pahole, lz4, zstd, cpio, dosfstools, e2fsprogs, ostree, uv.
- Installati senza sudo in `hosttools/` (`source env.sh`): platform-tools 37.0.1 (adb/fastboot, zip sha256 d230f138…),
  mkbootimg @d2bb0af5, avb/avbtool 1.4.0 @c5066a96, bc 7.0.3 (Gavin Howard; GNU bc 1.07.1 non compila).
- Mancano: setfiles (policycoreutils), img2simg (c'è img2simg.py nel repo Luma), regole udev per fastboot senza root.
- Il builder del disco richiede root (losetup/mount/ostree admin deploy).

## Boot image (scelta utente 2026-11-05: stile nura/Linaro, slot B)
- Android resta in slot A. Luma: boot_b + vendor_boot_b (header v4, DTB+initramfs+cmdline in vendor_boot), erase dtbo_b.
- vbmeta NON scritto per ora: boot con footer AVB firmato chiave test AOSP (rollback 1751673600 come stock),
  vendor_boot con footer hash non firmato (come stock). Se ABL rifiuta → valutare vbmeta_b disabilitato (come nura).
- PRIMA di qualsiasi --set-active=b: scrivere in slot B lo stesso bootloader 16.2 (rischio anti-rollback 6a). docs/flash-slot-b.md.
- `fastboot boot` NON utile qui (usa il vendor_boot stock dello slot attivo).
- Candidato `build/candidates/bluejay-debug-v1`: initramfs di debug (busybox-static + dropbear Alpine 3.22, NCM+ACM,
  172.16.42.1, root solo chiave hosttools/ssh/bluejay_ed25519). boot 154d825e…, vendor_boot 074a5f07…
  Host key dropbear rigenerata a ogni boot (scripts/bluejay-ssh.sh non la salva).

## Stato reale del telefono (2026-11-05, prima dello sblocco)
- Serial <SERIAL>. Era GrapheneOS 2026081301 (Android 17, CP2A.260705.006), bootloader bloccato con chiave custom (yellow).
- Bootloader **17.0-15199431**, baseband g5123b-145971-260414-B-15201439. La factory 16.2 scaricata è PIÙ VECCHIA: mai flasharla.
- Slot attivo **B** (GrapheneOS) → Luma va nello slot **A**. slot A: unbootable=yes, successful=yes.
- Dump: device-info/ (getprop, by-name, getvar-all-before-unlock). Nessun dump partizioni (niente root su GrapheneOS).
- 2026-11-05 ~08:40 UTC: `fastboot flashing unlock` confermato dall'utente → unlocked: yes (userdata cancellato).
- Scritti boot_a, vendor_boot_a (bluejay-debug-v1), erase dtbo_a. Slot attivo ancora B.
- IN ATTESA: bootloader 17.0-15199431 per lo slot A (factory Google CP2A.260705.006, scaricata dall'utente) prima di --set-active=a.
- L'utente ha poi detto "fai tutto tu": i flash ora li eseguo io.

## Bring-up (2026-11-05, UTC)
- Bootloader 17.0-15199431 + radio scritti anche nello slot A (dalla factory CP2A.260705.006, sha256 03992adc…, verificata).
- debug-v1: bloccato al logo, 3 tentativi poi ritorno a B. Causa probabile: earlycon/ttySAC0 con UART spenta. Tolto.
- debug-v2: kernel+init OK (provato con reboot in fastboot da init dopo 120 s), USB gadget assente.
- debug-v3: TYPEC_TCPCI_MAXIM=y → UDC 11110000.usb, NCM ok, SSH root via IPv6 link-local.
- Dal vivo: exynos-mailbox + clk-acpm → regolatori PMIC (ACPM) → simpledrm fb0, touch STM FTS (probe ok), panfrost NO (Mali-G78 0x9202 non supportato).
- debug-v4: MBOX/ACPM_CLK built-in, moduli non compressi + coldplug, luma-devmem (DECON 0x1c300030=0x3061). Display confermato dall'utente.
- ABL: aggiunge sec_dram/sec_pt alle reserved-memory (ok), sostituisce console= con console=null, aggiunge `bootconfig`
  (CONFIG_BOOT_CONFIG non attivo: warning innocuo).
- Host: NetworkManager toglieva il link-local dall'interfaccia USB dopo il DHCP fallito → profilo `luma-bluejay-usb`
  (ipv6 link-local, ipv4 off, match enp*u* / cdc_ncm). Rimuovere con `nmcli con delete luma-bluejay-usb`.

## Luma OS
- ostree remote `luma` (chiave Luma OS Release 7D3DAFCE…51D96CE2), repo archive in build/ostree-repo.
- Pull lento: server HTTP/1.1, ~0.3-0.5 s/oggetto, ostree 8 richieste parallele → ~22 oggetti/s (ore).
  Nessun delta da zero, ISO ARM non pubblicate (404). Immagine Pixel 9 alpha1: repo bare, metadati persi senza root → inutilizzabile.
- Deployment Luma (da Pixel 9 alpha1): composefs enabled=yes, sysroot readonly, SELinux enforcing, GDM, sshd, setfiles,
  resize2fs presenti; moduli Fedora 7.2.11 (inutili col nostro kernel → hook che monta i nostri su /usr/lib/modules).
- Avvio Luma nell'initramfs (initramfs-debug/luma-boot.sh): userdata → GPT interno 4096 → LumaRoot (loop con offset),
  ostree= dalla voce BLS (non fisso nel boot image), ostree-prepare-root del deployment via il suo ld.so,
  hook /luma/hooks, move /run, switch_root su systemd. Finestra 20 s per fermarlo con `touch /run/stay`.

## Primo avvio di Luma (2026-11-05 ~12:10-12:30 UTC)
- Pull completato: commit fb167540… (Nightly 20261104.5), firma GPG valida (C8CE1A1B51D96CE2), 114288 oggetti, 5337 s.
- Builder (lanciato dall'utente con sudo da terminale vero): build/userdata-dev1/luma-bluejay-dev1-userdata.sparse
  sha256 bd17d94d…, ostree-path /ostree/boot.1/luma/c612b786…/0, origin luma/1/aarch64/nightly. Scritto su userdata (242 s).
- v5: readlink assente in busybox → v6: tutte le 305 applet. prepare-root con composefs OK (overlay ro, /etc rw, /sysroot ro,
  var montato su /sysroot/ostree/deploy/luma/var).
- v6: `move /run` fallito (/run non era tmpfs) → v7: /run tmpfs. sshd di Luma rifiutava la chiave → chiave in /etc/ssh.
- v7: Luma su, ma /var = var del deployment (ro): il generatore systemd var.mount e ostree-remount vogliono ostree= in
  /proc/cmdline → v8: il bind di /proc/cmdline con ostree= resta e passa a systemd.
- v8: LumaRoot pieno (10 GB): resize2fs online del loop → 108 GB. luma-app-baseline (flatpak) ok → GDM ok,
  autologin luma su seat0, gnome-shell --mode=user a 1080x2400, rendering software (niente GPU).
- v9 (costruita, non ancora installata): unit growfs al boot + bootloader-update mascherato.
- Da portare upstream (shared): bootloader-update.service dovrebbe avere ConditionPathExists=/boot/grub2 (o simile).

## GPU, Wi-Fi, Bluetooth (2026-11-05 pomeriggio, UTC)
- GPU: omarchy-mobile PR #3 (G78 panfrost + quirk AARCH64_PGTABLE) unita al gs101 parziale di nura. GLES 3.1 Panfrost,
  readback ok, gnome-shell su renderD128. Mesa 26.2.5 non conosce G78 → ripiego hook 30 (solo libgallium sha 25ea48a0…,
  voce G57(9,0,3)→G78(9,2,2)). DA FARE upstream: patch Mesa (omarchy-mobile mesa 0004). DVFS GPU (PR #189) non applicata.
  Vulkan: PanVK 26.2.5 compilato solo per arch 6/7/10/12/13/14, niente v9 → nessun Vulkan sul G78.
  I flatpak usano la loro Mesa (runtime 25.08): RetroArch in software finché non si fa un'estensione GL.
- Wi-Fi: PR #143 1-33 (PHY/host/SysMMU gs201 + 27 brcmfmac) + 9080c4a7 (BCM4389 base) + variante gs101 del PHY
  (CAL Google gs101 @204078758737) + DT bluejay da dtbo stock (board 0x20506, SKU G1AZG, varianti JPN = default).
  soc@0 ranges esteso a 2 GiB. PCIe Gen2 x1 al primo colpo, fw 20.101.90, connesso a WPA2, HTTPS ok.
  Firmware in /var/lib/luma-bluejay/firmware (dalla factory, fuori git), copiato in /run dall'initramfs.
  DA FARE: copia automatica dal vendor del telefono; test 1 h di traffico.
- Bluetooth: PR #6 commit 1,2,4,5 (clock APM, UART APM, hci_bcm) + 18e52ffa15 (btbcm patchram_nowait, attivo via
  modprobe.d dall'hook 20) + DT bluejay (linee identiche a raven). BCM.hcd dal vendor. Scansione ok.
  DA FARE: indirizzo BD vero (ora 43:89:00:00:76:93 di default), test cuffia A2DP.
- Flatpak: bwrap non montava /proc per il bind ostree= su /proc/cmdline → unit luma-bluejay-cmdline.service lo toglie
  dopo var.mount/ostree-remount. ATTENZIONE: strumenti ostree che leggono ostree= dopo il boot non lo vedranno.
- Android: container spento all'avvio (utente luma: maschera broker, session, prewarm); ~/android.sh start|stop|status.
- Installati come richiesto: Claude Code 2.1.318 (~/.local/bin, utente luma), RetroArch 1.22.2 (flathub, sistema).
- Microfono/audio: tutto passa dall'AoC; omamobile ha AoC solo gs201 (boot/rails/sysmmu specifici), niente per gs101.
- Fotocamere: omamobile ha solo CSIS gs201 + sensori 9a; per gs101 e IMX363/386/355 niente; senza ISP solo RAW.
- Slot A non viene segnato "successful": dopo 3 riavvii senza fastboot si torna a B. DA FARE (boot control gs101).

## Slot A, GPU flatpak, SSH Wi-Fi (2026-11-05 sera, UTC)
- devinfo (/dev/sdd1, LUN sdd): magic DEVI v3.15, slot a 48+4i (retry, bit0 unbootable, bit1 successful, bit2 active).
  Slot A successful scritto con OK utente (backup device-info/devinfo-before-successful.bin), servizio
  luma-bluejay-slot-ok a ogni avvio. 3 riavvii normali di fila: sempre A, retry fermo a 2.
- GPU flatpak: estensioni locali org.freedesktop.Platform.GL.bluejay//25.08,26.08 e org.projectluma.Platform.GL.bluejay//44
  (hardlink + libgallium G78), FLATPAK_GL_DRIVERS=bluejay:default. RetroArch e app Luma su Panfrost.
- SSH/SFTP utente luma via Wi-Fi: chiave ~/.ssh/luma_bluejay_ed25519 (PC), alias `ssh luma-bluejay` (<phone LAN IP>, DHCP).
  Debug: root solo da `fe80::*%usb0` e 172.16.42.* (Match Address non accetta CIDR su indirizzi con zona).
- firewalld falliva (helper conntrack mancanti nel kernel: SIP, H323, IRC, NETBIOS_NS, SNMP, PPTP, SANE, AMANDA) → aggiunti.
- Il PC (mt7925e) non rispondeva agli ARP del telefono con power save Wi-Fi attivo: disattivato su <home Wi-Fi SSID> (PC).
- APERTO: riavvio spontaneo alle 15:34:23 UTC dopo ~5,5 min (pressione memoria/panfrost shrinker, aggiornamento flatpak),
  pstore vuoto (ramoops non sopravvive o reset a freddo).
- APERTO: tastiera a schermo non si apre nei flatpak e nel browser (IBus + ibus-portal attivi).
- AutomaticLoginEnable=False in /etc/gdm/custom.conf (cambiato da Luma/utente): rispettato dall'hook.

## Flash
- Tutti i flash li fa l'utente a mano. Io preparo i comandi esatti con checksum e li spiego; non scrivo mai sul telefono.

## Piano (ordine)
1. Identificare il telefono (fastboot getvar all: versione bootloader, slot corrente, stato unlock).
2. Backup/dump stock (boot, init_boot, vendor_boot, dtbo, vbmeta, /vendor/firmware, dmesg, DT, tabella partizioni) + factory image con hash.
3. Known-good: RAM-boot dell'immagine nura/pmOS per bluejay (`fastboot boot`).
4. Kernel nura + config Luma (SELinux, binder, pstore, ...) → shell su USB via initramfs con sshd.
5. Userdata image Luma dal nightly, poi boot Luma completo (RAM-boot prima).
6. Display/touch, ricarica, Wi-Fi, BT, audio, modem, suspend, camera/sensori, app Android, soak.

## Kernel Luma
- `kernel/base-nura.config` (= config nura) + `kernel/luma-bluejay.fragment` (SELinux, binder/binderfs, dma-buf heaps,
  overlay/erofs/fs-verity built-in, pstore/ramoops, IKCONFIG, netfilter Android). `scripts/build-kernel.sh` → build/kernel.
- IP_NF_*/IP6_NF_* restano =m (dipendono da *_IPTABLES_LEGACY): ok come moduli.
- Patch: `kernel/patches/0001` chassis-type = "handset" in gs101-bluejay.dts.

## Scaffolding di debug aggiunto (da rimuovere)
- initramfs-debug (dropbear root, ACM shell): solo variante debug, mai in release.
- hook 90-luma-bluejay-debug-ssh.sh (sshd root solo chiave + NM usb0): solo debug.
- `enforcing=0` nella cmdline debug: togliere quando le etichette SELinux degli hook sono a posto.
- AllowSuspend=no (hook 20): finché suspend non è provato.
- Profilo NM host `luma-bluejay-usb`.

## Log
- 2026-11-05: tool host installati, factory image verificata ed estratta, pagina SoC nura letta (fornita dall'utente).
- 2026-11-05: ricerca iniziale. Letta pagina device nura (raw), clonati pacchetti pmaports, letto builder Luma.
