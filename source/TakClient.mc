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
    var statusCallback as Method?  = null;
    var incomingCotCallback as Method? = null;
    var incomingChatCallback as Method? = null;
    var pendingMarkerOperations = [];

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
    }

    function isAlerting() as Boolean {
        return alerting;
    }

    function getAlertType() as String {
        return alertType;
    }

    function activateManualAlert(type as String) as Void {
        alertType = type;
        alerting = true;
        sendEmergency(:ALERT);
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
        alerting = false;
        status = :idle;
        notifyStatusChanged();
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
        alerting = false;
        status = :failed;
        notifyStatusChanged();
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
        var markerType = type == :hostile ? "a-h-G-E-S" : type == :friendly ? "a-f-G-E-S" : type == :obstacle ? "a-o-G-E-S" : "a-u-G-E-S";
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

    function sendEmergency(state as Symbol) as Void {
        if (!isConnected() || lastPosition == null || lastPosition.position == null) {
            return;
        }
        var degrees = lastPosition.position.toDegrees();
        transmit("emergency", {
            "uid" => "garmin-sos", "state" => state == :ALERT ? "ALERT" : "CANCEL",
            "alertType" => alertType,
            "lat" => degrees[0], "lon" => degrees[1], "hae" => lastPosition.altitude,
            "tStart" => cotTimestamp(Time.now()),
            "tStale" => cotTimestamp(Time.now().add(new Time.Duration(3600)))
        });
    }

    function sendChatReply(replyTo as String, text as String) as Void {
        if (!isConnected()) {
            return;
        }
        transmit("chat", {"replyTo" => replyTo, "text" => text});
    }

    function transmit(msgType as String, payload as Dictionary) as Void {
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
            incomingCotCallback.invoke(uid.toString(), (latitude as Number).toFloat(), (longitude as Number).toFloat(), cotType.toString());
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