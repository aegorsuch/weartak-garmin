import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class PhoneRelayListener extends Communications.ConnectionListener {
    var client;

    function initialize(relayClient) {
        ConnectionListener.initialize();
        client = relayClient;
    }

    function onComplete() as Void {
        client.onRelayTransmitComplete();
    }

    function onError() as Void {
        client.onRelayTransmitError();
    }
}


// Relays watch input to ATAK; server connectivity, credentials, identity, and PLI stay on the phone.
class TakClient {
    var status as Symbol = :idle;
    var lastResponseCode as Number?  = null;
    var lastPosition as Position.Info?  = null;
    var alerting as Boolean = false;
    var alertType as String = "Manual Alert";
    var automatedAlertUids = {};
    var automatedAlertSentAt = {};
    var automatedAlertSequence as Number = 0;
    var statusCallback as Method?  = null;
    var incomingCotCallback as Method? = null;
    var incomingChatCallback as Method? = null;
    var pendingMarkerOperations = [];
    var verboseLoggingEnabled as Boolean = false;
    var lastRelayMessageType as String? = null;
    var lastRelayMessageTime as Time.Moment? = null;

    function initialize() {
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function updatePosition(info as Position.Info) as Void {
        lastPosition = info;
    }

    function setAlerting(value as Boolean) as Void {
        if (alerting == value) {
            return;
        }
        alerting = value;
        if (!alerting) {
            alertType = "Manual Alert";
            sendEmergency(:CANCEL);
        }
        WatchUi.requestUpdate();
    }

    function isAlerting() as Boolean {
        return alerting;
    }

    function getAlertType() as String {
        return alertType;
    }

    function activateManualAlert(type as String) as Boolean {
        alertType = type;
        alerting = true;
        sendEmergency(:ALERT);
        WatchUi.requestUpdate();
        return true;
    }

    function isConnected() as Boolean {
        return status == :connected;
    }

    function connect() as Void {
        if (status == :connecting || isConnected()) {
            return;
        }
        status = :connecting;
        transmit("relay_hello", {"watchLabel" => "Garmin watch", "protocolVersion" => 1});
        notifyStatusChanged();
    }

    function disconnect() as Void {
        automatedAlertUids = {};
        automatedAlertSentAt = {};
        status = :idle;
        notifyStatusChanged();
        WatchUi.requestUpdate();
    }

    function onRelayTransmitComplete() as Void {
        if (status != :connecting) {
            return;
        }
        status = :connected;
        transmit("entity_sync_request", {"limit" => 50, "protocolVersion" => 1});
        flushMarkerOperations();
        notifyStatusChanged();
    }

    function onRelayTransmitError() as Void {
        if (status == :idle) {
            return;
        }
        automatedAlertUids = {};
        automatedAlertSentAt = {};
        status = :failed;
        notifyStatusChanged();
        WatchUi.requestUpdate();
    }

    function sendMarker(id as String, location as Position.Location, type as Symbol, label as String, remark as String) as Void {
        if (!isConnected()) {
            queueMarkerOperation({"op" => "upsert", "id" => id, "location" => location, "type" => type, "label" => label, "remark" => remark});
            return;
        }
        transmitMarker(id, location, type, label, remark);
    }

    function deleteMarker(id as String) as Void {
        if (!isConnected()) {
            queueMarkerOperation({"op" => "delete", "id" => id});
            return;
        }
        transmit("marker_delete", {"uid" => "garmin-marker-" + id});
    }

    function queueMarkerOperation(operation as Dictionary) as Void {
        var id = operation.get("id").toString();
        for (var index = pendingMarkerOperations.size() - 1; index >= 0; index--) {
            if (pendingMarkerOperations[index].get("id").toString() == id) {
                pendingMarkerOperations.remove(index);
            }
        }
        pendingMarkerOperations.add(operation);
    }

    function transmitMarker(id as String, location as Position.Location, type as Symbol, label as String, remark as String) as Void {
        var degrees = location.toDegrees();
        var markerType = type == :hostile ? "a-h-G-T" : type == :friendly ? "a-f-G-T" : type == :neutral ? "a-n-G-T" : "a-u-G-T";
        transmit("marker", {
            "uid" => "garmin-marker-" + id,
            "lat" => degrees[0], "lon" => degrees[1], "type" => markerType,
            "title" => label, "remark" => remark, "tStart" => cotTimestamp(Time.now()),
            "tStale" => cotTimestamp(Time.now().add(new Time.Duration(3600)))
        });
    }

    function flushMarkerOperations() as Void {
        var operations = pendingMarkerOperations;
        pendingMarkerOperations = [];
        for (var i = 0; i < operations.size(); i++) {
            var operation = operations[i] as Dictionary;
            if (operation.get("op") == "delete") {
                deleteMarker(operation.get("id").toString());
            } else {
                transmitMarker(operation.get("id").toString(), operation.get("location") as Position.Location, operation.get("type") as Symbol, operation.get("label").toString(), operation.get("remark").toString());
            }
        }
    }

    function sendSosEvent() as Void {
        activateManualAlert("Manual Alert");
    }

    function sendEmergency(state as Symbol) as Boolean {
        if (!isConnected()) {
            return false;
        }
        transmit("emergency", {
            "uid" => "garmin-sos", "state" => state == :ALERT ? "ALERT" : "CANCEL",
            "alertType" => alertType,
            "tStart" => cotTimestamp(Time.now()),
            "tStale" => cotTimestamp(Time.now().add(new Time.Duration(3600)))
        });
        return true;
    }

    function sendAutomatedAlert(category as String, description as String) as Boolean {
        if (!isConnected()) {
            return false;
        }
        var now = Time.now();
        var uid = automatedAlertUids.get(category);
        if (uid == null) {
            automatedAlertSequence += 1;
            uid = "garmin-auto-" + now.value().toString() + "-" + automatedAlertSequence.toString();
            automatedAlertUids.put(category, uid);
        } else if (now.value() - automatedAlertSentAt.get(category) < 240) {
            return true;
        }
        automatedAlertSentAt.put(category, now.value());
        transmit("emergency", {
            "uid" => uid, "state" => "ALERT", "catg" => category, "desc" => description,
            "tStart" => cotTimestamp(now),
            "tStale" => cotTimestamp(now.add(new Time.Duration(300)))
        });
        return true;
    }

    function clearAutomatedAlert(category as String) as Void {
        var uid = automatedAlertUids.get(category);
        if (uid == null) {
            return;
        }
        if (isConnected()) {
            transmit("emergency", {
                "uid" => uid, "state" => "CANCEL",
                "tStart" => cotTimestamp(Time.now()),
                "tStale" => cotTimestamp(Time.now().add(new Time.Duration(300)))
            });
        }
        automatedAlertUids.remove(category);
        automatedAlertSentAt.remove(category);
    }

    function sendChatReply(replyTo as String, text as String) as Void {
        if (!isConnected()) {
            return;
        }
        transmit("chat", {"replyTo" => replyTo, "text" => text});
    }

    function transmit(msgType as String, payload as Dictionary) as Void {
        lastRelayMessageType = "-> " + msgType;
        lastRelayMessageTime = Time.now();
        if (verboseLoggingEnabled) {
            System.println("TAK relay out: " + msgType);
        }
        Communications.transmit({"msgType" => msgType, "payload" => payload}, null, new PhoneRelayListener(self));
    }

    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        if (!(message.data instanceof Dictionary)) {
            return;
        }
        var envelope = message.data as Dictionary;
        var msgType = envelope.get("msgType");
        var payload = envelope.get("payload");
        if (!(payload instanceof Dictionary)) {
            return;
        }
        lastRelayMessageType = "<- " + msgType.toString();
        lastRelayMessageTime = Time.now();
        if (verboseLoggingEnabled) {
            System.println("TAK relay in: " + msgType.toString());
        }
        if (msgType == "chat" && incomingChatCallback != null) {
            incomingChatCallback.invoke(payload as Dictionary);
            return;
        }
        if ((msgType != "entity" && msgType != "entities") || incomingCotCallback == null) {
            return;
        }
        if (msgType == "entity") {
            forwardEntity(payload as Dictionary);
            return;
        }
        var entities = (payload as Dictionary).get("entities");
        if (entities instanceof Array) {
            for (var index = 0; index < entities.size(); index++) {
                if (entities[index] instanceof Dictionary) {
                    forwardEntity(entities[index] as Dictionary);
                }
            }
        }
    }

    function forwardEntity(entity as Dictionary) as Void {
        var uid = entity.get("uid");
        var latitude = entity.get("lat");
        var longitude = entity.get("lon");
        var cotType = entity.get("type");
        if (uid != null && latitude != null && longitude != null && cotType != null) {
            var callSign = entity.get("callSign");
            if (callSign == null) { callSign = entity.get("callsign"); }
            var team = entity.get("team");
            var role = entity.get("role");
            var group = entity.get("__group");
            if (group instanceof Dictionary) {
                if (team == null) { team = (group as Dictionary).get("name"); }
                if (role == null) { role = (group as Dictionary).get("role"); }
            }
            var contact = entity.get("contact");
            if (callSign == null && contact instanceof Dictionary) {
                callSign = (contact as Dictionary).get("callsign");
            }
            incomingCotCallback.invoke(
                uid.toString(), (latitude as Number).toFloat(), (longitude as Number).toFloat(), cotType.toString(),
                callSign == null ? null : callSign.toString(),
                team == null ? null : team.toString(),
                role == null ? null : role.toString()
            );
        }
    }

    function cotTimestamp(moment as Time.Moment) as String {
        var info = Time.Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.year.format("%04d") + "-" + info.month.format("%02d") + "-" + info.day.format("%02d")
            + "T" + info.hour.format("%02d") + ":" + info.min.format("%02d") + ":" + info.sec.format("%02d") + "Z";
    }

    function notifyStatusChanged() as Void {
        if (statusCallback != null) {
            statusCallback.invoke();
        }
    }

    function setVerboseLogging(enabled as Boolean) as Void {
        verboseLoggingEnabled = enabled;
    }

    function getLastRelayMessageSummary() as String {
        if (lastRelayMessageType == null || lastRelayMessageTime == null) {
            return "None";
        }
        var secondsAgo = Time.now().value() - lastRelayMessageTime.value();
        return lastRelayMessageType + " (" + secondsAgo.toString() + "s ago)";
    }

    function statusText() as String {
        if (status == :connecting) {
            return WatchUi.loadResource(Rez.Strings.StatusConnecting);
        } else if (status == :connected) {
            return WatchUi.loadResource(Rez.Strings.StatusConnected);
        } else if (status == :failed) {
            return WatchUi.loadResource(Rez.Strings.StatusFailed);
        }
        return WatchUi.loadResource(Rez.Strings.StatusIdle);
    }
}