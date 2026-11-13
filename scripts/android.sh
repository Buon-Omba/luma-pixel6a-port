#!/bin/bash
# Container Android (Waydroid) di Luma su Pixel 6a: spento all'avvio, acceso a richiesta.
# Uso: ~/android.sh start | stop | status
# All'avvio non parte: luma-android-prewarm.timer, luma-android-session.service e il broker sono mascherati
# per questo utente (~/.config/systemd/user), insieme al broker luma-android.service. "start" li riattiva solo fino al prossimo riavvio.
set -u
case "${1:-status}" in
  start)
    systemctl --user unmask --runtime luma-android.service luma-android-session.service luma-android-prewarm.timer 2>/dev/null
    systemctl --user unmask luma-android.service luma-android-session.service luma-android-prewarm.timer 2>/dev/null
    systemctl --user start luma-android.service luma-android-session.service
    luma-android resume
    # di nuovo mascherati per il prossimo avvio
    systemctl --user mask luma-android.service luma-android-session.service luma-android-prewarm.timer >/dev/null 2>&1
    echo "Android avviato."
    ;;
  stop)
    luma-android pause 2>/dev/null
    systemctl --user stop luma-android.service luma-android-session.service luma-android-prewarm.timer 2>/dev/null
    waydroid session stop 2>/dev/null
    echo "Per fermare anche il container di sistema serve la password:"
    sudo systemctl stop waydroid-container.service
    echo "Android spento."
    ;;
  status)
    echo "container: $(systemctl is-active waydroid-container.service)"
    echo "sessione:  $(systemctl --user is-active luma-android-session.service)"
    free -h | sed -n 1,2p
    ;;
  *) echo "uso: $0 start|stop|status"; exit 2 ;;
esac
