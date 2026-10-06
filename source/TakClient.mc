import Toybox.Communications;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
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


class PointReplyListener extends Communications.ConnectionListener {
    var client;
    var messageId as String;

    function initialize(relayClient, id as String) {
        ConnectionListener.initialize();
        client = relayClient;
        messageId = id;
    }

    function onComplete() as Void {
        client.onPointReplyComplete(messageId);
    }

    function onError() as Void {
        client.onPointReplyError(messageId);
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
    var channelsCallback as Method? = null;
    var dataSync as DataSyncClient;
    var verboseLoggingEnabled as Boolean = false;
    var lastRelayMessageType as String? = null;
    var lastRelayMessageTime as Time.Moment? = null;
    var pointReplies as OfflineRelayQueue;
    var pointReplyInFlight as String? = null;
    var pointReplySequence as Number = 0;
    var outboxTimer as Timer.Timer;

    function initialize() {
        dataSync = new DataSyncClient(self);
        pointReplies = new OfflineRelayQueue();
        var sequence = Application.Storage.getValue("pointReplySequence");
        if (sequence instanceof Number) { pointReplySequence = sequence; }
        pointReplies.restore(Application.Storage.getValue("pointReplies"), Time.now().value());
        if (pointReplies.expiredOnRestore > 0) {
            System.println("TAK offline events expired during restart");
        }
        savePointReplies();
        var savedAlertUids = Application.Storage.getValue("automatedAlertUids");
        if (savedAlertUids instanceof Dictionary) { automatedAlertUids = savedAlertUids; }
        var savedAlert = Application.Storage.getValue("manualAlertState");
        if (savedAlert instanceof Dictionary) {
            alerting = savedAlert.get("active") == true;
            var type = savedAlert.get("type");
            if (type instanceof String) { alertType = type; }
        }
        outboxTimer = new Timer.Timer();
        outboxTimer.start(method(:flushPointReplies), 5000, true);
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function updatePosition(info as Position.Info) as Void {
        lastPosition = info;
    }

    function setAlerting(value as Boolean) as Void {
        if (alerting == value) {
            return;
        }
        if (!value) {
            if (!sendEmergency(:CANCEL)) { return; }
            alertType = "Manual Alert";
        }
        alerting = value;
        saveOfflineValue("manualAlertState", {"active" => alerting, "type" => alertType});
        WatchUi.requestUpdate();
    }

    function isAlerting() as Boolean {
        return alerting;
    }

    function getAlertType() as String {
        return alertType;
    }

    function activateManualAlert(type as String) as Boolean {
        var previous = alertType;
        alertType = type;
        if (!sendEmergency(:ALERT)) { alertType = previous; return false; }
        alerting = true;
        saveOfflineValue("manualAlertState", {"active" => alerting, "type" => alertType});
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
        if (dataSync.requestId != null) { dataSync.fail(Rez.Strings.DataSyncRelayOff); }
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
        transmit("entity_sync_request", {"limit" => MapItemLimits.RETAINED_LIMIT, "protocolVersion" => 1});
        flushPointReplies();
        notifyStatusChanged();
    }

    function onRelayTransmitError() as Void {
        if (status == :idle) {
            return;
        }
        automatedAlertSentAt = {};
        status = :failed;
        notifyStatusChanged();
        WatchUi.requestUpdate();
    }

    function sendMarker(id as String, location as Position.Location?, type as Symbol, label as String, remark as String) as Boolean {
        var markerType = type == :hostile ? "a-h-G-T" : type == :friendly ? "a-f-G-T" : type == :neutral ? "a-n-G-T" : "a-u-G-T";
        var payload = {
            "uid" => "garmin-marker-" + id,
            "localId" => id, "type" => markerType,
            "title" => label, "remark" => remark, "tStart" => cotTimestamp(Time.now()),
            "tStale" => cotTimestamp(Time.now().add(new Time.Duration(86400)))
        };
        if (location != null) {
            var degrees = location.toDegrees();
            payload.put("lat", degrees[0]);
            payload.put("lon", degrees[1]);
        }
        return queueRelay("marker", payload, "marker-" + id);
    }

    function deleteMarker(id as String) as Boolean {
        return queueRelay("marker_delete", {"uid" => "garmin-marker-" + id}, "marker-" + id);
    }

    function sendSosEvent() as Void {
        activateManualAlert("Manual Alert");
    }

    function sendEmergency(state as Symbol) as Boolean {
        return queueRelay("emergency", {
            "uid" => "garmin-sos", "state" => state == :ALERT ? "ALERT" : "CANCEL",
            "alertType" => alertType,
            "tStart" => cotTimestamp(Time.now()),
            "tStale" => cotTimestamp(Time.now().add(new Time.Duration(86400)))
        }, "manual-alert");
    }

    function sendAutomatedAlert(category as String, description as String) as Boolean {
        var now = Time.now();
        var uid = automatedAlertUids.get(category);
        if (uid == null) {
            automatedAlertSequence += 1;
            uid = "garmin-auto-" + now.value().toString() + "-" + automatedAlertSequence.toString();
            automatedAlertUids.put(category, uid);
        } else if (automatedAlertSentAt.hasKey(category) && now.value() - automatedAlertSentAt.get(category) < 240) {
            return true;
        }
        if (!saveOfflineValue("automatedAlertUids", automatedAlertUids)) { return false; }
        var queued = queueRelay("emergency", {
            "uid" => uid, "state" => "ALERT", "catg" => category, "desc" => description,
            "tStart" => cotTimestamp(now),
            "tStale" => cotTimestamp(now.add(new Time.Duration(86400)))
        }, "auto-" + category);
        if (queued) { automatedAlertSentAt.put(category, now.value()); }
        return queued;
    }

    function clearAutomatedAlert(category as String) as Void {
        var uid = automatedAlertUids.get(category);
        if (uid == null) {
            return;
        }
        if (!queueRelay("emergency", {
                "uid" => uid, "state" => "CANCEL",
                "tStart" => cotTimestamp(Time.now()),
                "tStale" => cotTimestamp(Time.now().add(new Time.Duration(86400)))
            }, "auto-" + category)) { return; }
        automatedAlertUids.remove(category);
        automatedAlertSentAt.remove(category);
        saveOfflineValue("automatedAlertUids", automatedAlertUids);
    }

    function sendChatReply(replyTo as String, text as String) as Void {
        queueRelay("chat", {"replyTo" => replyTo, "text" => text}, null);
    }

    function queuePointReply(recipientUid as String, pointUid as String, text as String) as Boolean {
        if (recipientUid.length() == 0) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyNoSender), null);
            return false;
        }
        return queueRelay("chat", {
            "recipientUid" => recipientUid,
            "replyTo" => recipientUid, "pointUid" => pointUid,
            "text" => text
        }, null);
    }

    function queueRelay(msgType as String, payload as Dictionary, key as String?) as Boolean {
        if (pointReplies.restoreFailed) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.OfflineStorageFailed), null);
            return false;
        }
        expirePointReplies();
        var textSize = 0;
        var values = payload.values();
        for (var i = 0; i < values.size(); i++) {
            var value = values[i];
            if (value instanceof String) { textSize += value.length(); }
        }
        if (textSize > 512) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.OfflineDetailsTooLong), null);
            return false;
        }
        pointReplySequence += 1;
        var now = Time.now().value();
        var id = "garmin-event-" + now.toString() + "-" + pointReplySequence.toString();
        payload.put("messageId", id);
        payload.put("createdAt", now);
        var previous = pointReplies.replies.slice(0, pointReplies.replies.size());
        if (!pointReplies.add({"messageId" => id, "createdAt" => now,
                "msgType" => msgType, "payload" => payload, "key" => key}, now)) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyQueueFull), null);
            return false;
        }
        if (!savePointReplies()) { pointReplies.replies = previous; return false; }
        WatchUi.showToast(WatchUi.loadResource(msgType.equals("marker") ? Rez.Strings.MarkerStored : Rez.Strings.PointReplyQueued), null);
        flushPointReplies();
        return true;
    }

    function savePointReplies() as Boolean {
        if (pointReplies.restoreFailed) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.OfflineStorageFailed), null);
            System.println("TAK offline queue unreadable; stored events not overwritten");
            return false;
        }
        if (!saveOfflineValue("pointReplySequence", pointReplySequence)) { return false; }
        return saveOfflineValue("pointReplies", pointReplies.replies);
    }

    function saveOfflineValue(key as String, value) as Boolean {
        try {
            Application.Storage.setValue(key, value);
            return true;
        } catch (error instanceof Lang.StorageFullException) {
            System.println("TAK offline storage full: " + error.getErrorMessage());
        } catch (error instanceof Application.ObjectStoreAccessException) {
            System.println("TAK offline storage unavailable: " + error.getErrorMessage());
        }
        WatchUi.showToast(WatchUi.loadResource(Rez.Strings.OfflineStorageFailed), null);
        return false;
    }

    function expirePointReplies() as Void {
        if (pointReplies.expiredOnRestore > 0) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyExpired), null);
            pointReplies.expiredOnRestore = 0;
        }
        if (pointReplies.expire(Time.now().value()) > 0) {
            savePointReplies();
            System.println("TAK relay: unsent point replies expired");
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyExpired), null);
        }
    }

    function flushPointReplies() as Void {
        if (dataSync.requestId != null && System.getTimer() - dataSync.requestedAt >= 65000) {
            dataSync.fail(Rez.Strings.DataSyncTimeout);
        }
        if (pointReplies.restoreFailed) { return; }
        expirePointReplies();
        if (!isConnected() || pointReplyInFlight != null || pointReplies.replies.size() == 0) { return; }
        var reply = null;
        for (var i = 0; i < pointReplies.replies.size(); i++) {
            var candidate = pointReplies.replies[i];
            var payload = candidate.get("payload") as Dictionary;
            if (candidate.get("msgType").equals("marker") && payload.get("lat") == null) { continue; }
            reply = candidate;
            break;
        }
        if (reply == null) { return; }
        pointReplyInFlight = reply.get("messageId") as String;
        lastRelayMessageType = "-> " + reply.get("msgType").toString();
        lastRelayMessageTime = Time.now();
        Communications.transmit({"msgType" => reply.get("msgType"), "payload" => reply.get("payload")}, null,
            new PointReplyListener(self, pointReplyInFlight));
    }

    function onPointReplyComplete(id as String) as Void {
        if (pointReplyInFlight == null || !pointReplyInFlight.equals(id)) { return; }
        pointReplyInFlight = null;
        // This acknowledges only the phone handoff, not TAK delivery.
        var previous = pointReplies.replies.slice(0, pointReplies.replies.size());
        pointReplies.remove(id);
        if (!savePointReplies()) { pointReplies.replies = previous; return; }
        WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyHandedOff), null);
        flushPointReplies();
    }

    function onPointReplyError(id as String) as Void {
        if (pointReplyInFlight == null || !pointReplyInFlight.equals(id)) { return; }
        pointReplyInFlight = null;
        System.println("TAK relay: point reply phone handoff failed; retained for reconnect");
        WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyFailed), null);
        onRelayTransmitError();
    }

    function setChannelsCallback(callback as Method?) as Void {
        channelsCallback = callback;
    }

    function requestChannelServers() as Void {
        transmit("channels_servers_request", {});
    }

    function requestChannels(serverIndex as Number) as Void {
        transmit("channels_request", {"serverIndex" => serverIndex});
    }

    function updateChannel(serverIndex as Number, bitPosition as Number, active as Boolean) as Void {
        transmit("channels_update", {
            "serverIndex" => serverIndex,
            "bitpos" => bitPosition,
            "active" => active
        });
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
        if (!(msgType instanceof String) || !(payload instanceof Dictionary)) {
            return;
        }
        lastRelayMessageType = "<- " + msgType.toString();
        lastRelayMessageTime = Time.now();
        if (verboseLoggingEnabled) {
            System.println("TAK relay in: " + msgType.toString());
        }
        if (msgType.equals("missions_servers_response") || msgType.equals("missions_response")
                || msgType.equals("missions_error")) {
            dataSync.receive(msgType, payload);
            return;
        }
        if (msgType == "chat" && incomingChatCallback != null) {
            incomingChatCallback.invoke(payload as Dictionary);
            return;
        }
        if ((msgType == "channels_servers_response" || msgType == "channels_response" || msgType == "channels_error")
                && channelsCallback != null) {
            channelsCallback.invoke(msgType.toString(), payload as Dictionary);
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
                role == null ? null : role.toString(),
                entity
            );
            flushPointReplies();
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