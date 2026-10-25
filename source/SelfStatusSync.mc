import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

class SelfStatusListener extends Communications.ConnectionListener {
    var client;
    var generation as Number;
    function initialize(relay) {
        ConnectionListener.initialize();
        client = relay;
        generation = relay.relayGeneration;
    }
    function onComplete() as Void {}
    function onError() as Void {
        if (client.relayEnabled && generation == client.relayGeneration) {
            System.println("Wearable self status transport failed; snapshot is not queued");
        }
    }
}

class SelfStatusSync {
    var client;
    var supported as Boolean = false;
    var ppe as Dictionary? = null;
    var heartRate as Number? = null;
    var measuredAt as Number? = null;
    var sequence as Number = 0;
    var lastSentAt as Number? = null;
    var pendingSample as Boolean = false;

    function initialize(relay) { client = relay; }

    function reset() as Void {
        disable();
        sequence = 0;
    }

    function disable() as Void {
        supported = false;
        heartRate = null;
        measuredAt = null;
        lastSentAt = null;
        pendingSample = false;
    }

    function setPpe(level as Number?, savedAt as String?) as Void {
        ppe = savedAt == null ? null : {"level" => moppLevelLabel(level), "savedAt" => savedAt};
        flush(true);
    }

    function clearPhysio() as Void {
        heartRate = null;
        measuredAt = null;
        pendingSample = false;
        flush(true);
    }

    function sample(value as Number?, optedIn as Boolean) as Void {
        if (!client.isConnected() || !supported) { return; }
        var valid = optedIn && value != null && value >= 20 && value <= 250;
        if (!valid && heartRate == null) { return; }
        heartRate = valid ? value : null;
        measuredAt = valid ? client.relayEpochNow() : null;
        pendingSample = true;
        flush(false);
    }

    function flush(force as Boolean) as Void {
        if (!supported || !client.isConnected()) { return; }
        var age = measuredAt == null ? null : client.relayEpochNow() - measuredAt;
        if (age != null && (age < 0 || age > 120)) {
            heartRate = null;
            measuredAt = null;
            pendingSample = true;
        }
        var now = client.relayNow();
        if (!force && lastSentAt != null && now >= lastSentAt
                && now - lastSentAt < (pendingSample ? 15000 : 60000)) { return; }
        var physio = heartRate == null ? null : {"hr" => heartRate,
            "measuredAt" => client.cotTimestamp(new Time.Moment(measuredAt))};
        send(ppe, physio);
    }

    function clearRemote() as Void {
        if (supported && client.isConnected()) { send(null, null); }
    }

    function send(savedPpe as Dictionary?, physio as Dictionary?) as Void {
        if (!client.relayEnabled) { return; }
        client.transmitEnvelope({"msgType" => "self_status", "payload" => {
            "version" => 1, "session" => client.relaySession, "seq" => sequence,
            "deviceUid" => client.getWatchDeviceUid(), "model" => "GARMIN",
            "ppe" => savedPpe, "physio" => physio
        }}, new SelfStatusListener(client));
        sequence++;
        lastSentAt = client.relayNow();
        pendingSample = false;
    }
}
