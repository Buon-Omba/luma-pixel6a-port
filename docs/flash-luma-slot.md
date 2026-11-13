# Pixel 6a: comandi manuali (slot A, stile nura/Linaro)

Tutti i comandi li lanci tu. Prima di ogni blocco: `source env.sh` nella cartella del progetto.
`fastboot` si può lanciare con `sudo` se senza dà "no permissions".
Android resta nello **slot B** e non viene toccato. Luma va nello **slot A**.

## Fase 0: identificazione (sola lettura, nessuna scrittura)

Telefono in modalità fastboot (spento, poi Volume giù + Power), collegato via USB.

```
fastboot devices
fastboot getvar product            # deve dire: bluejay
fastboot getvar unlocked           # yes/no
fastboot getvar current-slot       # dove sta Android (atteso: a)
fastboot getvar version-bootloader # atteso: bluejay-16.2-13291547
fastboot getvar version-baseband
fastboot getvar slot-retry-count:a
fastboot getvar slot-retry-count:b
fastboot getvar slot-successful:b
fastboot getvar slot-unbootable:b
fastboot getvar partition-size:boot_b
fastboot getvar partition-size:vendor_boot_b
fastboot getvar partition-size:dtbo_b
fastboot getvar all 2> getvar-all.txt
```

Mandami l'output (soprattutto `getvar-all.txt`). Se `current-slot` non è `a`, scambia a/b in tutto quello che segue.

## Fase 1 (UNA VOLTA): il bootloader dello slot A

**Perché:** anche il bootloader del Pixel ha uno slot A e uno slot A. Il 6a è uscito con Android 12, e da Android 13 Google
ha attivato un anti-rollback del bootloader. Se lo slot A ha ancora un bootloader vecchio e si avvia da B,
il telefono può bloccarsi in modo irrecuperabile. Google stessa raccomanda di scrivere il bootloader attuale anche nell'altro slot.
Per questo prima scriviamo in B lo **stesso** bootloader che gira già in A (16.2-13291547, dalla factory image verificata).

**Cosa cambia:** le partizioni del bootloader dello slot A. **Cosa può andare storto:** un'interruzione (cavo staccato) durante la
scrittura dello slot A. Lo slot A resta comunque intatto e il telefono continua ad avviarsi da A.

```
fastboot getvar current-slot                       # deve essere a
sha256sum sources/stock/bluejay-bp2a.250705.008/bootloader-bluejay-bluejay-16.2-13291547.img
fastboot --slot=other flash bootloader sources/stock/bluejay-bp2a.250705.008/bootloader-bluejay-bluejay-16.2-13291547.img
fastboot getvar current-slot                       # deve essere ancora a
```

(Va fatta prima di qualsiasi `--set-active=b`. Te lo ricorderò.)

## Fase 2: prova in RAM (non scrive niente)

Con il layout v4, `fastboot boot` usa il `vendor_boot` già scritto nello slot attivo (quello stock). Quindi in RAM
**non** si può provare il nostro device tree senza scrivere prima `vendor_boot`. Si salta, e si va alla fase 3 sullo slot A.

## Fase 3: scrittura dello slot A (candidato `<NOME>`)

**Cosa cambia:** `boot_b` e `vendor_boot_b` (immagini nostre) e `dtbo_b` (cancellato). `vbmeta`, lo slot A,
modem, `persist`, `efs` e `userdata` non vengono toccati.
**Cosa può andare storto:** se Luma non si avvia, il bootloader riprova qualche volta e poi torna da solo allo slot A
(Android). Se resta in un loop, Volume giù + Power riporta in fastboot e `fastboot --set-active=a` torna ad Android.

```
cd build/candidates/<NOME> && sha256sum -c SHA256SUMS && cd -
fastboot getvar product                                  # bluejay
fastboot flash boot_b        build/candidates/<NOME>/boot.img
fastboot flash vendor_boot_b build/candidates/<NOME>/vendor_boot.img
fastboot erase dtbo_b
fastboot --set-active=b
fastboot reboot
```

Se il bootloader rifiuta di avviare per la verifica AVB (vbmeta stock con l'hash di `vendor_boot`/`dtbo` diverso),
ti preparo un `vbmeta_b` con verifica disabilitata. È lo stesso passo che fa nura, e lo valutiamo insieme in quel momento.

## Tornare ad Android

```
fastboot --set-active=a
fastboot reboot
```

Ripristino completo dello slot A allo stock (se servisse):
```
fastboot flash boot_b        sources/stock/img/boot.img
fastboot flash vendor_boot_b sources/stock/img/vendor_boot.img
fastboot flash dtbo_b        sources/stock/img/dtbo.img
```

## Dopo l'avvio di Luma debug

Sul PC: `scripts/bluejay-ssh.sh` (root via USB, solo chiave). Lo uso io, ed è in sola lettura finché non dici altro.
