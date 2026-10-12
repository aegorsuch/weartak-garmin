import Toybox.Lang;
import Toybox.Test;

(:test)
function bloodhoundStrictIngress(logger) as Boolean {
    var harness = new BloodhoundSyncHarness();
    harness.sync.receiveControl(bloodhoundFixture("start"));
    Test.assert(harness.target == null);
    Test.assertEqual(harness.sent.size(), 0);
    harness.sync.connectionChanged(true);
    var invalid = [
        {"action" => "move"}, {"target_uid" => ""}, {"target_uid" => " remote-1"},
        {"target_uid" => "remote-1 "}, {"target_uid" => "remote\n1"},
        {"target_uid" => 1}, {"command_id" => "not-a-uuid"}, {"session_id" => "session-1"},
        {"bloodhoundVersion" => "1"}, {"bloodhoundVersion" => 2},
        {"relaySession" => "old-link"}, {"target_uid" => null}
    ];
    for (var index = 0; index < invalid.size(); index++) {
        var command = bloodhoundFixture("start");
        var changes = invalid[index] as Dictionary;
        var keys = changes.keys();
        command.put(keys[0], changes.get(keys[0]));
        harness.sync.receiveControl(command);
        Test.assert(harness.target == null);
        Test.assertEqual(harness.sent.size(), 0);
    }
    var longUid = "";
    for (var index = 0; index < 257; index++) { longUid += "x"; }
    var command = bloodhoundFixture("start");
    command.put("target_uid", longUid);
    harness.sync.receiveControl(command);
    Test.assertEqual(harness.sent.size(), 0);
    var malformed = [
        {"lat" => null}, {"lat" => "38.5"}, {"lat" => true}, {"lat" => 91},
        {"lon" => -181}, {"hae" => "100"}, {"target_callsign" => longUid}
    ];
    for (var index = 0; index < malformed.size(); index++) {
        command = bloodhoundFixture("start");
        var changes = malformed[index] as Dictionary;
        var keys = changes.keys();
        command.put(keys[0], changes.get(keys[0]));
        harness.sync.receiveControl(command);
        Test.assert(harness.target == null);
        Test.assertEqual(harness.lastPayload().get("ok"), false);
        Test.assertEqual(harness.lastPayload().get("command_id"), command.get("command_id"));
    }
    command = bloodhoundFixture("start");
    command.remove("hae");
    command.remove("target_callsign");
    harness.sync.receiveControl(command);
    Test.assertEqual(harness.lastPayload().get("ok"), true);
    return true;
}

(:test)
function bloodhoundExactAcknowledgements(logger) as Boolean {
    var harness = new BloodhoundSyncHarness();
    harness.sync.connectionChanged(true);
    harness.target = bloodhoundTestTarget("remote-1", 38.5d);
    harness.sync.localTargetChanged();
    var command = harness.lastPayload();
    var mismatches = [
        {"command_id" => "33333333-3333-4333-8333-333333333333"},
        {"session_id" => "33333333-3333-4333-8333-333333333333"},
        {"target_uid" => "other"}, {"action" => "stop"}, {"relaySession" => "old"},
        {"bloodhoundVersion" => 2}, {"ok" => "true"}, {"ok" => false}
    ];
    for (var index = 0; index < mismatches.size(); index++) {
        var result = bloodhoundAck(command, true);
        var changes = mismatches[index] as Dictionary;
        var keys = changes.keys();
        result.put(keys[0], changes.get(keys[0]));
        harness.sync.receiveResult(result);
        Test.assertEqual(harness.sync.pending.size(), 1);
    }
    harness.sync.receiveResult(bloodhoundAck(command, true));
    Test.assertEqual(harness.sync.pending.size(), 0);
    harness.sync.receiveResult(bloodhoundAck(command, true));
    Test.assertEqual(harness.sync.pending.size(), 0);
    harness.target = bloodhoundTestTarget("remote-1", 39.0d);
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.lastPayload().get("action"), "update");
    Test.assert(command.get("command_id") != harness.lastPayload().get("command_id"));
    harness.sync.receiveResult(bloodhoundAck(command, true));
    Test.assertEqual(harness.sync.pending.size(), 1);
    harness.sync.receiveResult(bloodhoundAck(harness.lastPayload(), false));
    Test.assertEqual(harness.sync.pending.size(), 0);
    Test.assert(harness.target != null);
    return true;
}

(:test)
function bloodhoundBoundedPendingAndErrors(logger) as Boolean {
    var harness = new BloodhoundSyncHarness();
    harness.sync.connectionChanged(true);
    harness.target = bloodhoundTestTarget("remote-1", 1.0d);
    harness.sync.localTargetChanged();
    for (var index = 0; index < 40; index++) {
        harness.target = bloodhoundTestTarget("remote-1", (index + 2).toDouble());
        harness.sync.localTargetChanged();
    }
    Test.assertEqual(harness.sync.pending.size(), BLOODHOUND_PENDING_LIMIT);
    Test.assertEqual(harness.sent.size(), BLOODHOUND_PENDING_LIMIT);
    harness.clockValue += BLOODHOUND_ACK_TIMEOUT_SECONDS;
    harness.sync.checkTimeouts();
    Test.assertEqual(harness.sync.pending.size(), 0);
    harness.sendResult = false;
    var before = harness.errors.size();
    Test.assert(!harness.sync.sendCommand("11111111-1111-4111-8111-111111111111",
        bloodhoundTestTarget("remote-1", 1.0d), "start"));
    Test.assertEqual(harness.errors.size(), before + 1);
    Test.assertEqual(harness.sync.pending.size(), 0);
    return true;
}

(:test)
function bloodhoundTransportFailureRetiresStart(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.status = :idle;
    relay.connect();
    relay.listeners[0].onComplete();
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false,
        "chatGroups" => false, "bloodhoundVersion" => 1, "bloodhoundControl" => true});
    var harness = new BloodhoundSyncHarness();
    relay.bloodhoundSync.activeTargetCallback = harness.method(:activeTarget);
    harness.target = bloodhoundTestTarget("remote-1", 38.5d);
    relay.bloodhoundSync.localTargetChanged();
    var listener = relay.listeners[relay.listeners.size() - 1];
    Test.assertEqual(relay.bloodhoundSync.pending.size(), 1);
    Test.assert(relay.bloodhoundSync.sessionId != null);
    listener.onError();
    Test.assertEqual(relay.bloodhoundSync.pending.size(), 0);
    Test.assert(relay.bloodhoundSync.sessionId == null);
    Test.assert(relay.bloodhoundSync.retired.size() > 0);
    return true;
}

(:test)
function bloodhoundCapabilityAndStaleCallbacks(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.status = :idle;
    relay.connect();
    var hello = relay.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(hello.get("bloodhoundVersion"), 1);
    Test.assertEqual(hello.get("protocolVersion"), 1);
    var oldListener = relay.listeners[0];
    oldListener.onComplete();
    Test.assert(relay.isConnected());
    Test.assert(!relay.bloodhoundSync.connected);
    var versions = [null, "1", 2, true];
    for (var index = 0; index < versions.size(); index++) {
        relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false,
            "chatGroups" => false, "bloodhoundVersion" => versions[index], "bloodhoundControl" => true});
        Test.assert(!relay.bloodhoundSync.connected);
    }
    relay.applyRelayStatus({"relaySession" => "old-link", "reliableDelivery" => false,
        "bloodhoundVersion" => 1, "bloodhoundControl" => true});
    Test.assert(!relay.bloodhoundSync.connected);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false,
        "bloodhoundVersion" => 1, "bloodhoundControl" => "true"});
    Test.assert(!relay.bloodhoundSync.connected);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false,
        "chatGroups" => false, "bloodhoundVersion" => 1, "bloodhoundControl" => true});
    Test.assert(relay.bloodhoundSync.connected);
    var harness = new BloodhoundSyncHarness();
    relay.bloodhoundSync.activeTargetCallback = harness.method(:activeTarget);
    harness.target = bloodhoundTestTarget("remote-1", 38.5d);
    relay.bloodhoundSync.localTargetChanged();
    var command = relay.envelopes[relay.envelopes.size() - 1].get("payload") as Dictionary;
    var listener = relay.listeners[relay.listeners.size() - 1];
    listener.onComplete();
    Test.assertEqual(relay.bloodhoundSync.pending.size(), 1);
    var oldSession = relay.relaySession;
    relay.disconnect();
    Test.assert(harness.target != null);
    relay.connect();
    Test.assert(oldSession != relay.relaySession);
    oldListener.onComplete();
    oldListener.onError();
    listener.onError();
    Test.assertEqual(relay.status, :connecting);
    Test.assert(!relay.bloodhoundSync.connected);
    relay.bloodhoundSync.receiveResult(bloodhoundAck(command, true));
    Test.assertEqual(relay.bloodhoundSync.pending.size(), 0);
    var currentListener = relay.listeners[relay.listeners.size() - 1];
    currentListener.onComplete();
    relay.applyRelayStatus({"relaySession" => oldSession, "reliableDelivery" => false,
        "bloodhoundVersion" => 1, "bloodhoundControl" => true});
    Test.assert(!relay.bloodhoundSync.connected);
    return true;
}
