import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class DataSyncListener extends Communications.ConnectionListener {
    var client as DataSyncClient;
    var id as String;

    function initialize(owner as DataSyncClient, requestId as String) {
        ConnectionListener.initialize();
        client = owner;
        id = requestId;
    }

    function onComplete() as Void {}

    function onError() as Void {
        if (client.requestId != null && client.requestId.equals(id)) {
            client.fail(Rez.Strings.DataSyncHandoffFailed);
        }
    }
}

// A phone handoff is not a mission acknowledgement; only a correlated snapshot changes subscriptions.
class DataSyncClient {
    var relay as TakClient;
    var servers as Array<Dictionary> = [];
    var feeds as Array<Dictionary> = [];
    var serverID as String? = null;
    var requestId as String? = null;
    var sequence as Number = 0;
    var error as String? = null;
    var callback as Method? = null;
    var requestedAt as Number = 0;
    var pendingFeed as String? = null;
    var pendingSubscribed as Boolean = false;

    function initialize(owner as TakClient) {
        relay = owner;
    }

    function refresh() as Void {
        request(serverID == null ? "missions_servers_request" : "missions_request", {});
    }

    function selectServer(id as String) as Void {
        feeds = [];
        serverID = id;
        refresh();
    }

    function subscribe(feed as Dictionary) as Void {
        if (error != null || requestId != null || serverID == null) { return; }
        if (feed.get("passwordProtected") == true && feed.get("subscribed") != true) {
            fail(Rez.Strings.DataSyncPassword);
            return;
        }
        pendingFeed = feed.get("name") as String;
        pendingSubscribed = feed.get("subscribed") != true;
        request("mission_update", {"missionName" => pendingFeed, "missionSubscribe" => pendingSubscribed});
    }

    function request(kind as String, payload as Dictionary) as Void {
        if (requestId != null) { return; }
        if (!relay.isConnected()) { fail(Rez.Strings.DataSyncRelayOff); return; }
        sequence += 1;
        requestId = System.getTimer().toString() + "-" + sequence.toString();
        payload.put("requestId", requestId);
        payload.put("dataSyncVersion", 1);
        payload.put("serverID", serverID);
        payload.put("limit", serverID == null ? 4 : 20);
        error = null;
        requestedAt = System.getTimer();
        sendRequest(kind, payload, requestId);
        changed();
    }

    function sendRequest(kind as String, payload as Dictionary, id as String) as Void {
        Communications.transmit({"msgType" => kind, "payload" => payload}, null, new DataSyncListener(self, id));
    }

    function fail(value as ResourceId or String) as Void {
        requestId = null;
        pendingFeed = null;
        error = value instanceof String ? value : WatchUi.loadResource(value) as String;
        changed();
    }

    function receive(kind as String, payload as Dictionary) as Void {
        var id = payload.get("requestId");
        if (requestId == null || !(id instanceof String) || !requestId.equals(id)) { return; }
        if (kind.equals("missions_error")) {
            var detail = payload.get("error");
            fail(detail instanceof String && detail.length() > 0 && detail.length() <= 256
                ? detail : WatchUi.loadResource(Rez.Strings.DataSyncInvalid) as String);
            return;
        }
        if (payload.get("dataSyncVersion") != 1) { fail(Rez.Strings.DataSyncUnsupported); return; }
        var discovery = serverID == null;
        var list = payload.get(discovery ? "servers" : "missions");
        if (!kind.equals(discovery ? "missions_servers_response" : "missions_response")
                || (!discovery && !serverID.equals(payload.get("serverID")))
                || !validList(list, discovery)) {
            fail(Rez.Strings.DataSyncInvalid);
            return;
        }
        var rows = list as Array;
        if (pendingFeed != null) {
            var confirmed = false;
            for (var i = 0; i < rows.size(); i++) {
                var feed = rows[i] as Dictionary;
                if (pendingFeed.equals(feed.get("name")) && feed.get("subscribed") == pendingSubscribed) {
                    confirmed = true;
                }
            }
            if (!confirmed) { fail(Rez.Strings.DataSyncInvalid); return; }
        }
        requestId = null;
        pendingFeed = null;
        error = null;
        if (discovery) { servers = rows as Array<Dictionary>; }
        else { feeds = rows as Array<Dictionary>; }
        changed();
    }

    function validList(value, discovery as Boolean) as Boolean {
        if (!(value instanceof Array) || value.size() > (discovery ? 4 : 20)) { return false; }
        var ids = [];
        for (var i = 0; i < value.size(); i++) {
            var row = value[i];
            if (!(row instanceof Dictionary)) { return false; }
            var allowed = discovery ? ["id", "name", "state", "error"]
                : ["name", "subscribed", "passwordProtected", "itemCount", "error"];
            var keys = row.keys();
            for (var k = 0; k < keys.size(); k++) {
                if (allowed.indexOf(keys[k]) == -1) { return false; }
            }
            var name = row.get("name");
            var id = discovery ? row.get("id") : name;
            if (!(name instanceof String) || name.length() == 0 || name.length() > 128
                    || !(id instanceof String) || id.length() == 0 || id.length() > 128
                    || ids.indexOf(id) != -1) { return false; }
            ids.add(id);
            var state = row.get("state");
            var detail = row.get("error");
            if ((state != null && (!(state instanceof String) || state.length() > 128))
                    || (detail != null && (!(detail instanceof String) || detail.length() > 256))) { return false; }
            if (!discovery) {
                var count = row.get("itemCount");
                if (!(row.get("subscribed") instanceof Boolean)
                        || !(row.get("passwordProtected") instanceof Boolean)
                        || (count != null && (!(count instanceof Number) || count < 0))) { return false; }
            }
        }
        return true;
    }

    function cancel() as Void {
        requestId = null;
        pendingFeed = null;
    }

    function changed() as Void {
        if (callback != null) { callback.invoke(); }
    }
}
