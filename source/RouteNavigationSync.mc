import Toybox.Lang;
import Toybox.Timer;

const ROUTE_NAV_ACK_SECONDS = 8;

// Geometry stays in RouteStore; bonded navigation is owned by ATAK, not watch GPS.
class RouteNavigationSync {
    var identities as BloodhoundSync;
    var sendCallback as Method? = null;
    var applyCallback as Method? = null;
    var connected as Boolean = false;
    var relaySession as String = "";
    var sessionId as String? = null;
    var serverId as String? = null;
    var routeUid as String? = null;
    var sequence as Number = -1;
    var pending as Array<Dictionary> = [];
    var retired as Array<String> = [];
    var timer as Timer.Timer;

    function initialize(shared as BloodhoundSync) { identities = shared; timer = new Timer.Timer(); }

    function connectionChanged(ready as Boolean) as Void {
        if (ready == connected) { return; }
        connected = ready;
        if (sessionId != null) {
            apply({"action" => "stop", "completed" => false});
            retire(sessionId);
        }
        sessionId = null;
        serverId = null;
        routeUid = null;
        sequence = -1;
        pending = [];
        timer.stop();
    }

    function startLocal(route as Dictionary, index as Number) as Boolean {
        if (!connected) { return false; }
        stopLocal();
        var id = identities.newSessionId();
        var command = {"version" => 1, "relaySession" => relaySession,
            "requestId" => identities.newSessionId(), "sessionId" => id, "action" => "start",
            "serverId" => route.get("serverId"), "routeUid" => route.get("uid"), "targetPointIndex" => index};
        if (!sendCommand(command)) { return false; }
        sessionId = id;
        serverId = route.get("serverId");
        routeUid = route.get("uid");
        sequence = -1;
        return true;
    }

    function stopLocal() as Void {
        if (sessionId == null) { return; }
        var command = {"version" => 1, "relaySession" => relaySession,
            "requestId" => identities.newSessionId(), "sessionId" => sessionId, "action" => "stop",
            "serverId" => serverId, "routeUid" => routeUid};
        retire(sessionId);
        sessionId = null;
        sequence = -1;
        if (connected) { sendCommand(command); }
    }

    function sendCommand(command as Dictionary) as Boolean {
        if (pending.size() >= 8) {
            error("Too many unconfirmed route commands");
            return false;
        }
        var request = {"command" => command, "deadline" => identities.clock() + ROUTE_NAV_ACK_SECONDS};
        pending.add(request);
        if (!send("watch_route_navigation", command)) {
            pending.remove(request);
            error("Could not send phone route " + command.get("action"));
            return false;
        }
        timer.start(method(:checkTimeouts), 1000, true);
        return true;
    }

    function receiveState(payload as Dictionary) as Void {
        var incomingSequence = payload.get("sequence");
        var targetIndex = payload.get("targetPointIndex");
        if (!connected || !relaySession.equals(payload.get("relaySession"))
                || !(payload.get("version") instanceof Number) || payload.get("version") != 1
                || !identities.validUuid(payload.get("sessionId"))
                || !identities.validText(payload.get("serverId"), false)
                || !identities.validText(payload.get("routeUid"), false)
                || !(incomingSequence instanceof Number) || incomingSequence < 0) {
            error("Invalid phone route state");
            return;
        }
        var id = payload.get("sessionId") as String;
        var action = payload.get("action");
        if (!(action instanceof String) || !(action.equals("start") || action.equals("progress") || action.equals("stop"))) {
            error("Invalid phone route action"); return;
        }
        if (isRetired(id)) { return; }
        var same = sessionId != null && sessionId.equals(id);
        if (same && (!serverId.equals(payload.get("serverId")) || !routeUid.equals(payload.get("routeUid")))) {
            error("Phone route session target mismatch"); return;
        }
        if (same && incomingSequence <= sequence) { return; }
        if (action.equals("stop")) {
            if (!(payload.get("completed") instanceof Boolean)) { error("Invalid route completion"); return; }
            if (!same) { retire(id); return; }
        } else if (!(targetIndex instanceof Number) || targetIndex < 0) {
            error("Invalid phone route point"); return;
        }
        if (!apply(payload)) {
            error("Phone route is unavailable or exceeds watch limits");
            return;
        }
        if (sessionId != null && !same) { retire(sessionId); }
        sessionId = action.equals("stop") ? null : id;
        serverId = payload.get("serverId");
        routeUid = payload.get("routeUid");
        sequence = incomingSequence;
        if (action.equals("stop")) { retire(id); }
        for (var i = pending.size() - 1; i >= 0; i--) {
            var command = pending[i].get("command") as Dictionary;
            if (id.equals(command.get("sessionId")) && command.get("action").equals("start")) {
                pending.remove(pending[i]);
            }
        }
    }

    function receiveAck(payload as Dictionary) as Void {
        if (!connected || !relaySession.equals(payload.get("relaySession"))
                || !identities.validUuid(payload.get("requestId")) || !identities.validUuid(payload.get("sessionId"))
                || !(payload.get("ok") instanceof Boolean)) { return; }
        for (var i = 0; i < pending.size(); i++) {
            var command = pending[i].get("command") as Dictionary;
            if (!command.get("requestId").equals(payload.get("requestId")) || !command.get("sessionId").equals(payload.get("sessionId"))) { continue; }
            if (payload.get("ok") == false && !identities.validText(payload.get("error"), false)) {
                error("Invalid phone route acknowledgement"); return;
            }
            // A positive start acknowledgement still needs a matching authoritative snapshot.
            if (payload.get("ok") == true && command.get("action").equals("start")) { return; }
            pending.remove(pending[i]);
            if (payload.get("ok") == false) { failed(command, payload.get("error") as String); }
            return;
        }
    }

    function checkTimeouts() as Void {
        for (var i = pending.size() - 1; i >= 0; i--) {
            if ((pending[i].get("deadline") as Number) > identities.clock()) { continue; }
            var command = pending[i].get("command") as Dictionary;
            pending.remove(pending[i]);
            failed(command, "Phone did not confirm route " + command.get("action") + "; navigation is not synchronized");
        }
        if (pending.size() == 0) { timer.stop(); }
    }

    function transportError(command as Dictionary) as Void {
        if (!connected || !relaySession.equals(command.get("relaySession"))) { return; }
        for (var i = pending.size() - 1; i >= 0; i--) {
            var expected = pending[i].get("command") as Dictionary;
            if (!expected.get("requestId").equals(command.get("requestId"))) { continue; }
            pending.remove(pending[i]);
            failed(expected, "Could not hand off phone route " + expected.get("action"));
            return;
        }
    }

    function failed(command as Dictionary, message as String) as Void {
        if (command.get("action").equals("start") && sessionId != null && sessionId.equals(command.get("sessionId"))) {
            apply({"action" => "stop", "completed" => false});
            stopLocal();
        }
        error(message);
    }

    function retire(id as String) as Void {
        if (!isRetired(id)) { retired.add(id); }
        while (retired.size() > 32) { retired.remove(retired[0]); }
        for (var i = pending.size() - 1; i >= 0; i--) {
            var command = pending[i].get("command") as Dictionary;
            if (id.equals(command.get("sessionId")) && command.get("action").equals("start")) { pending.remove(pending[i]); }
        }
    }

    function isRetired(id as String) as Boolean {
        for (var i = 0; i < retired.size(); i++) { if (id.equals(retired[i])) { return true; } }
        return false;
    }

    function apply(payload as Dictionary) as Boolean {
        return applyCallback != null && applyCallback.invoke(payload) == true;
    }
    function send(kind as String, payload as Dictionary) as Boolean {
        return sendCallback != null && sendCallback.invoke(kind, payload) == true;
    }
    function error(message as String) as Void { identities.reportError("Route sync: " + message); }
}
