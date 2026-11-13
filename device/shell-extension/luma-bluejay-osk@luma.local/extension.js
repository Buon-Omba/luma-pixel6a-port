// SPDX-License-Identifier: Unlicense
// Ripiego per Luma su Pixel 6a: mutter 50 apre il pannello di input per i client text-input-v3 v1 solo
// quando riattivano un campo già a fuoco. I client Qt attivano text-input una volta per finestra e non lo
// ripetono al tocco, quindi la tastiera non compare mai. Qui: se un tocco recente porta il focus (o il
// cursore) in un campo di testo, apri la tastiera. Da portare upstream in Luma (shell o mutter).
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const TOUCH_WINDOW_US = 700 * 1000;

export default class LumaBluejayOsk extends Extension {
    enable() {
        this._lastTouch = 0;
        this._stageId = global.stage.connect('captured-event', (actor, event) => {
            if (event.type() === Clutter.EventType.TOUCH_BEGIN)
                this._lastTouch = GLib.get_monotonic_time();
            return Clutter.EVENT_PROPAGATE;
        });
        const im = Main.inputMethod;
        const maybeOpen = () => {
            if (!im.currentFocus || Main.keyboard.visible)
                return;
            if (GLib.get_monotonic_time() - this._lastTouch > TOUCH_WINDOW_US)
                return;
            Main.keyboard.open(Main.layoutManager.focusIndex);
        };
        this._imIds = [
            im.connect('request-surrounding', maybeOpen),
            im.connect('cursor-location-changed', maybeOpen),
        ];
    }

    disable() {
        if (this._stageId)
            global.stage.disconnect(this._stageId);
        this._stageId = 0;
        for (const id of this._imIds ?? [])
            Main.inputMethod.disconnect(id);
        this._imIds = null;
    }
}
