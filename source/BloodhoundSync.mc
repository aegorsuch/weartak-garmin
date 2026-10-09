import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

const BLOODHOUND_ACK_TIMEOUT_SECONDS = 10;
const BLOODHOUND_RETIRED_LIMIT = 64;

// Mirrors the WearOS companion Bloodhound contract so one ATAK plugin drives both watches.
// Remote changes never echo a command back to the phone.
class BloodhoundSync {
    var activeTargetCallback as Method? = null;
    var startTrackingCallback as Method? = null;
    var stopTrackingCallback as Method? = null;
    var updateTrackingCallback as Method? = null;
    var sendCallback as Method? = null;
    var reportErrorCallback as Method? = null;
    var sessionIdCallback as Method? = null;
    var clockCallback as Method? = null;

    var connected as Boolean = false;
    var observedTarget as Dictionary? = null;
    var sessionId as String? = null;
    var sessionTarget as Dictionary? = null;
    var retired as Array<String> = [];
    var pending as Array<Dictionary> = [];

    function initialize() {
    }

    function connectionChanged(ready as Boolean) as Void {
        if (connected == ready) { return; }
        connected = ready;
        if (sessionId != null) { retire(sessionId as String); }
        sessionId = null;
        sessionTarget = null;
        pending = [];
        observedTarget = activeTarget();
    }

    // Call after any local Bloodhound target change so the phone follows the watch.
    function localTargetChanged() as Void {
        var target = activeTarget();
        if (targetsEqual(target, observedTarget)) { return; }
        var currentUid = uidOf(target);
        var previousUid = uidOf(observedTarget);
        var sameUid = currentUid != null && previousUid != null && currentUid.equals(previousUid);
        observedTarget = target;
        if (!connected) { return; }
        if (sameUid) {
            if (target != null && sessionId != null && isValidTarget(target as Dictionary)
                    && currentUid.equals(uidOf(sessionTarget))) {
                sessionTarget = target;
                if (!send("bloodhound_control", targetPayload(sessionId as String, "update", target as Dictionary))) {
                    reportError("Could not update phone Bloodhound target");
                }
            }
            return;
        }
        if (sessionId != null) {
            sendCommand(sessionId as String, sessionTarget as Dictionary, "stop");
            retire(sessionId as String);
        }
        sessionId = null;
        sessionTarget = null;
        if (target == null) { return; }
        if (!isValidTarget(target as Dictionary)) {
            reportError("Tracking target has no valid location");
            return;
        }
        var nextId = newSessionId();
        if (sendCommand(nextId, target as Dictionary, "start")) {
            sessionId = nextId;
            sessionTarget = target;
        }
    }

    function receiveControl(payload as Dictionary) as Void {
        if (!connected) {
            reportError("Bloodhound command received without a ready phone connection");
            return;
        }
        var id = stringValue(payload, "session_id");
        var action = stringValue(payload, "action");
        var uid = stringValue(payload, "target_uid");
        if (id.length() == 0 || uid.length() == 0
                || !(action.equals("start") || action.equals("stop") || action.equals("update"))) {
            reportError("Invalid phone Bloodhound command");
            if (id.length() > 0) { result(id, action, false, "Invalid tracking command"); }
            return;
        }
        if (action.equals("stop")) {
            receiveStop(id, action, uid);
            return;
        }
        if (isRetired(id)) {
            if (!action.equals("update")) { result(id, action, false, "Tracking session has ended"); }
            return;
        }
        var callsign = stringValue(payload, "target_callsign");
        var target = {
            "uid" => uid,
            "callsign" => callsign.length() == 0 ? uid : callsign,
            "lat" => numberValue(payload, "lat"),
            "lon" => numberValue(payload, "lon"),
            "hae" => numberValue(payload, "hae")
        };
        if (!isValidTarget(target)) {
            if (!action.equals("update")) { result(id, action, false, "Tracking target has no valid location"); }
            reportError("Phone Bloodhound target has no valid location");
            return;
        }
        if (action.equals("update")) {
            receiveUpdate(id, uid, target);
            return;
        }
        receiveStart(id, action, uid, target);
    }

    function receiveStop(id as String, action as String, uid as String) as Void {
        if (sessionId == null || !(sessionId as String).equals(id) || !uid.equals(uidOf(sessionTarget))) {
            var known = isRetired(id);
            result(id, action, known, known ? null : "Tracking session is not active");
            return;
        }
        // A delayed stop must not cancel a local replacement that has not been observed yet.
        if (!uid.equals(uidOf(activeTarget()))) {
            retire(id);
            sessionId = null;
            sessionTarget = null;
            result(id, action, false, "Tracking target has changed");
            return;
        }
        if (!stopTracking(uid)) {
            result(id, action, false, "Could not stop tracking");
            reportError("Could not stop phone Bloodhound tracking");
            return;
        }
        retire(id);
        sessionId = null;
        sessionTarget = null;
        observedTarget = activeTarget();
        result(id, action, true, null);
    }

    function receiveUpdate(id as String, uid as String, target as Dictionary) as Void {
        if (sessionId == null || !(sessionId as String).equals(id)
                || !uid.equals(uidOf(sessionTarget)) || !uid.equals(uidOf(activeTarget()))) { return; }
        if (!updateTracking(target)) {
            reportError("Could not update phone Bloodhound target on watch");
            return;
        }
        observedTarget = activeTarget();
        sessionTarget = observedTarget == null ? target : observedTarget;
    }

    function receiveStart(id as String, action as String, uid as String, target as Dictionary) as Void {
        if (sessionId != null && (sessionId as String).equals(id)) {
            var matches = uid.equals(uidOf(sessionTarget)) && uid.equals(uidOf(activeTarget()));
            result(id, action, matches, matches ? null : "Tracking session target mismatch");
            return;
        }
        // Both sides started at once; the lower session id yields so exactly one target survives.
        if (sessionId != null && hasPendingStart(sessionId as String)
                && compareStrings(sessionId as String, id) < 0) {
            retire(id);
            result(id, action, false, "Superseded by simultaneous tracking start");
            return;
        }
        if (!startTracking(target)) {
            result(id, action, false, "Could not activate tracking target");
            reportError("Could not start phone Bloodhound target on watch");
            return;
        }
        if (sessionId != null) { retire(sessionId as String); }
        sessionId = id;
        sessionTarget = target;
        observedTarget = activeTarget();
        result(id, action, true, null);
    }

    function receiveResult(payload as Dictionary) as Void {
        var id = stringValue(payload, "session_id");
        var action = stringValue(payload, "action");
        var index = pendingIndex(id, action);
        if (index < 0) { return; }
        var ok = payload.get("ok");
        if (!(ok instanceof Boolean)) {
            reportError("Invalid phone Bloodhound acknowledgement");
            return;
        }
        pending.remove(pending[index]);
        if (ok == true) { return; }
        if (action.equals("start") && sessionId != null && (sessionId as String).equals(id)) {
            sessionId = null;
            sessionTarget = null;
            retire(id);
        }
        var error = stringValue(payload, "error");
        reportError(error.length() > 0 ? error : "Phone rejected Bloodhound " + action);
    }

    function checkTimeouts() as Void {
        var deadline = clock();
        var expired = [];
        for (var index = 0; index < pending.size(); index++) {
            var request = pending[index] as Dictionary;
            if ((request.get("deadline") as Number) <= deadline) { expired.add(request); }
        }
        for (var index = 0; index < expired.size(); index++) {
            var request = expired[index] as Dictionary;
            pending.remove(request);
            var id = request.get("id") as String;
            var action = request.get("action") as String;
            if (action.equals("start") && sessionId != null && (sessionId as String).equals(id)) {
                sessionId = null;
                sessionTarget = null;
                retire(id);
            }
            reportError("Phone did not confirm Bloodhound " + action + "; tracking may not be synchronized");
        }
    }

    function sendCommand(id as String, target as Dictionary, action as String) as Boolean {
        if (!send("bloodhound_control", targetPayload(id, action, target))) {
            reportError("Could not send phone Bloodhound " + action);
            return false;
        }
        pending.add({"id" => id, "action" => action,
            "deadline" => clock() + BLOODHOUND_ACK_TIMEOUT_SECONDS});
        return true;
    }

    function result(id as String, action as String, ok as Boolean, error as String?) as Void {
        var payload = {"session_id" => id, "action" => action, "ok" => ok};
        if (error != null) { payload.put("error", error); }
        if (!send("bloodhound_control_result", payload)) {
            reportError("Could not acknowledge phone Bloodhound " + action);
        }
    }

    function targetPayload(id as String, action as String, target as Dictionary) as Dictionary {
        var payload = {"action" => action, "session_id" => id, "target_uid" => target.get("uid")};
        if (!action.equals("stop")) {
            payload.put("target_callsign", target.get("callsign"));
            payload.put("lat", target.get("lat"));
            payload.put("lon", target.get("lon"));
            payload.put("hae", target.get("hae"));
        }
        return payload;
    }

    function retire(id as String) as Void {
        for (var index = pending.size() - 1; index >= 0; index--) {
            var request = pending[index] as Dictionary;
            if ((request.get("id") as String).equals(id) && (request.get("action") as String).equals("start")) {
                pending.remove(request);
            }
        }
        if (isRetired(id)) { return; }
        retired.add(id);
        while (retired.size() > BLOODHOUND_RETIRED_LIMIT) { retired.remove(retired[0]); }
    }

    function isRetired(id as String) as Boolean {
        for (var index = 0; index < retired.size(); index++) {
            if ((retired[index] as String).equals(id)) { return true; }
        }
        return false;
    }

    function hasPendingStart(id as String) as Boolean {
        return pendingIndex(id, "start") >= 0;
    }

    function pendingIndex(id as String, action as String) as Number {
        for (var index = 0; index < pending.size(); index++) {
            var request = pending[index] as Dictionary;
            if ((request.get("id") as String).equals(id) && (request.get("action") as String).equals(action)) {
                return index;
            }
        }
        return -1;
    }

    function activeTarget() as Dictionary? {
        if (activeTargetCallback == null) { return null; }
        var target = activeTargetCallback.invoke();
        return target instanceof Dictionary ? target as Dictionary : null;
    }

    function startTracking(target as Dictionary) as Boolean {
        return startTrackingCallback == null ? false : startTrackingCallback.invoke(target) == true;
    }

    function stopTracking(uid as String) as Boolean {
        return stopTrackingCallback == null ? false : stopTrackingCallback.invoke(uid) == true;
    }

    function updateTracking(target as Dictionary) as Boolean {
        return updateTrackingCallback == null ? false : updateTrackingCallback.invoke(target) == true;
    }

    function send(msgType as String, payload as Dictionary) as Boolean {
        return sendCallback == null ? false : sendCallback.invoke(msgType, payload) == true;
    }

    function reportError(message as String) as Void {
        if (reportErrorCallback != null) { reportErrorCallback.invoke(message); }
    }

    function clock() as Number {
        if (clockCallback != null) { return clockCallback.invoke() as Number; }
        return Time.now().value();
    }

    function newSessionId() as String {
        if (sessionIdCallback != null) { return sessionIdCallback.invoke() as String; }
        // ATAK requires a UUID-shaped session id.
        var variants = ["8", "9", "a", "b"];
        return randomHex(8) + "-" + randomHex(4) + "-4" + randomHex(3) + "-"
            + variants[randomIndex(4)] + randomHex(3) + "-" + randomHex(12);
    }

    function randomHex(count as Number) as String {
        var digits = "0123456789abcdef";
        var value = "";
        for (var index = 0; index < count; index++) {
            var position = randomIndex(16);
            value += digits.substring(position, position + 1);
        }
        return value;
    }

    function randomIndex(limit as Number) as Number {
        var value = Math.rand() % limit;
        return value < 0 ? -value : value;
    }

    function uidOf(target as Dictionary?) as String? {
        if (target == null) { return null; }
        var uid = (target as Dictionary).get("uid");
        return uid instanceof String && (uid as String).length() > 0 ? uid as String : null;
    }

    function isValidTarget(target as Dictionary) as Boolean {
        if (uidOf(target) == null) { return false; }
        var latitude = target.get("lat");
        var longitude = target.get("lon");
        if (!(latitude instanceof Float) && !(latitude instanceof Double) && !(latitude instanceof Number)) { return false; }
        if (!(longitude instanceof Float) && !(longitude instanceof Double) && !(longitude instanceof Number)) { return false; }
        var lat = latitude.toDouble();
        var lon = longitude.toDouble();
        return lat >= -90.0d && lat <= 90.0d && lon >= -180.0d && lon <= 180.0d;
    }

    function targetsEqual(left as Dictionary?, right as Dictionary?) as Boolean {
        if (left == null || right == null) { return left == null && right == null; }
        var keys = ["uid", "callsign", "lat", "lon", "hae"];
        for (var index = 0; index < keys.size(); index++) {
            var key = keys[index] as String;
            var leftValue = (left as Dictionary).get(key);
            var rightValue = (right as Dictionary).get(key);
            if (leftValue == null || rightValue == null) {
                if (leftValue != rightValue) { return false; }
            } else if (!leftValue.equals(rightValue)) {
                return false;
            }
        }
        return true;
    }

    function stringValue(payload as Dictionary, key as String) as String {
        var value = payload.get(key);
        return value instanceof String ? value as String : "";
    }

    function numberValue(payload as Dictionary, key as String) as Double? {
        var value = payload.get(key);
        if (value instanceof Float || value instanceof Double || value instanceof Number) {
            return value.toDouble();
        }
        return null;
    }

    function compareStrings(left as String, right as String) as Number {
        var leftBytes = left.toUtf8Array();
        var rightBytes = right.toUtf8Array();
        var limit = leftBytes.size() < rightBytes.size() ? leftBytes.size() : rightBytes.size();
        for (var index = 0; index < limit; index++) {
            if (leftBytes[index] != rightBytes[index]) {
                return leftBytes[index] < rightBytes[index] ? -1 : 1;
            }
        }
        if (leftBytes.size() == rightBytes.size()) { return 0; }
        return leftBytes.size() < rightBytes.size() ? -1 : 1;
    }
}
