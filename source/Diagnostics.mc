import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

module Diagnostics {
    const START = 1;
    const STOP = 2;
    const LOCATION_ON = 3;
    const LOCATION_OFF = 4;
    const FIX_USABLE = 5;
    const FIX_UNUSABLE = 6;
    const REPORT_SENT = 7;
    const REPORT_WAIT = 8;
    const REPORT_OFFLINE = 9;
    const SENSOR_PRESENT = 10;
    const SENSOR_ABSENT = 11;
    const RELAY_CONNECTED = 12;
    const RELAY_DISCONNECTED = 13;
    const RELAY_RECEIVED = 14;
    const RELAY_TRANSMITTED = 15;
    const STORAGE_ERROR = 16;
    const RELAY_ERROR = 17;
    const SPEED_UNKNOWN = 18;
    const SPEED_STATIONARY = 19;
    const SPEED_MOVING = 20;
    const BATTERY_LOW = 21;
    const BATTERY_NORMAL = 22;
    const MONITORING_ON = 23;
    const MONITORING_OFF = 24;
    var journal as DiagnosticJournal = new DiagnosticJournal();

    function record(code as Number) as Void {
        if (journal.enabled) { journal.record(code, Time.now().value()); }
    }
    class DiagnosticJournal {
        const CAPACITY = 32;
        const PERIOD = 60;
        var enabled as Boolean = false;
        var entries as Array = [];
        var lastEventAt as Dictionary<Number, Number> = {};
        var lastFlushAt as Number? = null;
        var lastPowerAt as Number? = null;
        var storageFailed as Boolean = false;
        var labels as Array<String> = ["App started", "App stopped", "Location enabled", "Location disabled",
                "Usable position sample", "Unusable position sample", "PLI send attempted",
                "Reporting not due", "Reporting offline", "HR sample present", "HR unavailable or disabled",
                "Relay connected", "Relay disconnected", "Relay received", "Relay transmitted",
                "App storage error", "Relay error", "Speed unknown", "Speed stationary",
                "Speed moving", "Battery low", "Battery normal", "Monitoring enabled", "Monitoring disabled"];

        function initialize() {}

        function label(code as Number) as String? {
            return code >= 1 && code <= labels.size() ? labels[code - 1] : null;
        }

        function readStored() { return Application.Storage.getValue("diagnosticsV1"); }
        function writeStored(value as Dictionary) as Void { Application.Storage.setValue("diagnosticsV1", value); }

        function storageError() as Void {
            if (!storageFailed) { System.println("Diagnostics storage unavailable; recent evidence may be unsaved"); }
            storageFailed = true;
        }

        function restore(now as Number) as Void {
            enabled = false;
            entries = [];
            lastEventAt = {};
            lastFlushAt = now;
            lastPowerAt = null;
            storageFailed = false;
            var stored = null;
            try {
                stored = readStored();
            } catch (error instanceof Application.ObjectStoreAccessException) {
                storageError();
                return;
            }
            if (stored == null) { return; }
            if (!(stored instanceof Dictionary) || stored.get("schema") != 1
                    || !(stored.get("enabled") instanceof Boolean) || !(stored.get("entries") instanceof Array)) {
                System.println("Diagnostics rejected invalid stored state");
                storageFailed = true;
                return;
            }
            enabled = stored.get("enabled") as Boolean;
            var saved = stored.get("entries") as Array;
            var first = saved.size() > CAPACITY ? saved.size() - CAPACITY : 0;
            for (var i = first; i < saved.size(); i++) {
                var entry = saved[i];
                if (entry instanceof Array && entry.size() == 2 && entry[0] instanceof Number
                        && entry[0] >= 0 && entry[0] <= now && entry[1] instanceof Number
                        && label(entry[1]) != null) {
                    entries.add([entry[0], entry[1]]);
                    lastEventAt.put(entry[1], entry[0]);
                } else {
                    System.println("Diagnostics rejected invalid stored event");
                }
            }
        }

        function persist(value as Boolean, now as Number) as Boolean {
            lastFlushAt = now;
            try {
                writeStored({"schema" => 1, "enabled" => value, "entries" => entries});
            } catch (error instanceof Lang.StorageFullException) {
                storageError();
                return false;
            } catch (error instanceof Application.ObjectStoreAccessException) {
                storageError();
                return false;
            }
            storageFailed = false;
            return true;
        }

        function setEnabled(value as Boolean, now as Number) as Boolean {
            // Explicit opt-out stops capture even if native storage cannot save the preference.
            if (!value) { enabled = false; }
            if (!persist(value, now)) { return false; }
            enabled = value;
            return true;
        }

        function record(code as Number, now as Number) as Void {
            if (!enabled) { return; }
            if (label(code) == null || now < 0) {
                System.println("Diagnostics rejected invalid event");
                return;
            }
            var previous = lastEventAt.get(code);
            if (previous != null && now >= previous && now - previous < PERIOD) { return; }
            lastEventAt.put(code, now);
            if (entries.size() == CAPACITY) { entries = entries.slice(1, entries.size()); }
            entries.add([now, code]);
            if (lastFlushAt == null || now < lastFlushAt || now - lastFlushAt >= PERIOD) { persist(enabled, now); }
        }

        function samplePower() as Void {
            if (!enabled) { return; }
            var now = Time.now().value();
            if (lastPowerAt != null && now >= lastPowerAt && now - lastPowerAt < PERIOD) { return; }
            lastPowerAt = now;
            var battery = System.getSystemStats().battery;
            if (battery != null) { record(battery < 20 ? Diagnostics.BATTERY_LOW : Diagnostics.BATTERY_NORMAL, now); }
        }

        function timestamp(epoch as Number) as String {
            var date = Gregorian.utcInfo(new Time.Moment(epoch), Time.FORMAT_SHORT);
            return date.year.format("%04d") + "-" + date.month.format("%02d") + "-" + date.day.format("%02d")
                + " " + date.hour.format("%02d") + ":" + date.min.format("%02d") + ":" + date.sec.format("%02d") + "Z";
        }
    }

    function buildEventsMenu(journal as DiagnosticJournal) as WatchUi.Menu2 {
        var menu = createMenu("Diagnostic Events");
        if (journal.storageFailed) { addMenuEntry(menu, "Storage unavailable", "Recent events may be unsaved", :storage); }
        if (journal.entries.size() == 0) { addMenuEntry(menu, "No events yet", "Diagnostics is opt-in", :empty); }
        for (var i = journal.entries.size() - 1; i >= 0; i--) {
            var entry = journal.entries[i];
            addMenuEntry(menu, journal.label(entry[1]), journal.timestamp(entry[0]), i);
        }
        return menu;
    }
}
