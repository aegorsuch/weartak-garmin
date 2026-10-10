import Toybox.Communications;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
class TestReliableRelay extends TakClient {
    var clock as Number = 1000;
    var epoch as Number = 100000;
    var envelopes as Array<Dictionary> = [];
    var listeners as Array<Communications.ConnectionListener> = [];
    var stored as Dictionary = {};
    var storageAvailable as Boolean = true;

    function initialize() {
        TakClient.initialize();
        status = :connected;
        relaySession = "test-session";
        addEvent("test-event", null);
    }

    function startRelayRuntime() as Void {}
    function loadOfflineValue(key as String) { return stored.get(key); }
    function saveOfflineValue(key as String, value) as Boolean {
        if (!storageAvailable) { return false; }
        stored.put(key, value instanceof Array ? value.slice(0, value.size()) : value);
        return true;
    }
    function relayNow() as Number { return clock; }
    function relayEpochNow() as Number { return epoch; }
    function transmitEnvelope(envelope as Dictionary, listener as Communications.ConnectionListener) as Void {
        envelopes.add(envelope);
        listeners.add(listener);
    }
    function addEvent(id as String, key as String?) as Void {
        Test.assert(pointReplies.add({"messageId" => id, "createdAt" => epoch,
            "msgType" => "chat", "key" => key,
            "payload" => {"messageId" => id, "createdAt" => epoch, "text" => "Rgr",
                "replyTo" => "recipient"}}, epoch));
    }
    function result(id as String, ok as Boolean) as Void {
        applyRelayResult({"messageId" => id, "relaySession" => relaySession, "ok" => ok});
    }
    function waitForRetry(delay as Number) as Void {
        var count = envelopes.size();
        Test.assert(pointReplyInFlight == null);
        Test.assertEqual(pointReplyRetryAt, clock + delay);
        clock += delay - 1;
        flushPointReplies();
        Test.assertEqual(envelopes.size(), count);
        clock++;
        flushPointReplies();
        Test.assertEqual(envelopes.size(), count + 1);
        flushPointReplies();
        Test.assertEqual(envelopes.size(), count + 1);
    }
}

(:test)
function reliableRelayFixtureIsolation(logger) as Boolean {
    var first = new TestReliableRelay();
    Test.assert(first.loadOfflineValue("manualAlertState") == null);
    Test.assertEqual(first.pointReplies.replies.size(), 1);
    Test.assertEqual(first.envelopes.size(), 0);
    first.storageAvailable = false;
    Test.assert(!first.savePointReplies());
    first.storageAvailable = true;
    Test.assert(first.savePointReplies());
    var second = new TestReliableRelay();
    Test.assertEqual((second.stored.get("pointReplies") as Array).size(), 0);
    Test.assertEqual(second.pointReplies.replies.size(), 1);
    Test.assertEqual(second.envelopes.size(), 0);
    return true;
}

(:test)
function reliableRelayNegotiation(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayNegotiating = true;
    relay.relayNegotiationAt = relay.clock;
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => true});
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => "true"});
    Test.assert(relay.relayNegotiating);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true});
    Test.assertEqual(relay.envelopes.size(), 1);
    relay.listeners[0].onComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 0);
    return true;
}

(:test)
function reliableRelayRetryPayload(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    relay.listeners[0].onError();
    relay.waitForRetry(5000);
    for (var i = 0; i < relay.envelopes.size(); i++) {
        var envelope = relay.envelopes[i];
        Test.assertEqual(envelope.get("msgType"), "chat");
        var payload = envelope.get("payload") as Dictionary;
        Test.assertEqual(payload.size(), 5);
        Test.assertEqual(payload.get("messageId"), "test-event");
        Test.assertEqual(payload.get("createdAt"), relay.epoch);
        Test.assertEqual(payload.get("text"), "Rgr");
        Test.assertEqual(payload.get("replyTo"), "recipient");
        Test.assertEqual(payload.get("relaySession"), relay.relaySession);
    }
    Test.assert((relay.pointReplies.replies[0].get("payload") as Dictionary).get("relaySession") == null);
    return true;
}

(:test)
function reliableRelayTimeoutBoundary(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    relay.clock += 29999;
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, "test-event");
    relay.clock++;
    relay.flushPointReplies();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.waitForRetry(5000);
    return true;
}

(:test)
function reliableRelayBackoffSchedule(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    var delays = [5000, 10000, 20000, 40000, 60000, 60000];
    for (var i = 0; i < delays.size(); i++) {
        relay.result("test-event", false);
        Test.assertEqual(relay.pointReplies.replies.size(), 1);
        relay.waitForRetry(delays[i]);
    }
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplyRetryDelay, 5000);
    Test.assertEqual(relay.pointReplyRetryAt, 0);
    Test.assert(relay.pointReplyInFlight == null);
    relay.addEvent("next-event", null);
    relay.flushPointReplies();
    relay.result("next-event", false);
    relay.waitForRetry(5000);
    return true;
}

(:test)
function reliableRelayStaleCallbacks(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    var oldListener = relay.listeners[0];
    oldListener.onError();
    relay.waitForRetry(5000);
    // Disable reliable delivery so a stale success would incorrectly dequeue the new attempt.
    relay.relayResultRequired = false;
    oldListener.onComplete();
    oldListener.onError();
    Test.assertEqual(relay.pointReplyInFlight, "test-event");
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyRetryDelay, 10000);
    Test.assertEqual(relay.envelopes.size(), 2);
    return true;
}

(:test)
function reliableRelayMalformedResults(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    var invalid = [
        {"messageId" => "test-event", "relaySession" => "old", "ok" => true},
        {"messageId" => "other", "relaySession" => relay.relaySession, "ok" => true},
        {"messageId" => "test-event", "relaySession" => relay.relaySession, "ok" => "true"},
        {"messageId" => "test-event", "relaySession" => relay.relaySession, "ok" => 1},
        {"messageId" => "test-event", "ok" => true},
        {"relaySession" => relay.relaySession, "ok" => true}
    ];
    for (var i = 0; i < invalid.size(); i++) {
        relay.applyRelayResult(invalid[i]);
        Test.assertEqual(relay.pointReplies.replies.size(), 1);
        Test.assertEqual(relay.pointReplyInFlight, "test-event");
        Test.assertEqual(relay.pointReplyRetryAt, 0);
    }
    return true;
}

(:test)
function reliableRelayDuplicateAcknowledgement(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.addEvent("next-event", null);
    relay.flushPointReplies();
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplyInFlight, "next-event");
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, "next-event");
    Test.assertEqual(relay.envelopes.size(), 2);
    relay.result("next-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function reliableRelayReconnect(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    var oldListener = relay.listeners[0];
    var oldSession = relay.relaySession;
    relay.disconnect();
    Test.assert(relay.pointReplyInFlight == null);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.result("test-event", true);
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 1);
    relay.connect();
    var hello = relay.envelopes[1];
    Test.assertEqual(hello.get("msgType"), "relay_hello");
    Test.assert(!oldSession.equals(relay.relaySession));
    Test.assertEqual((hello.get("payload") as Dictionary).get("relaySession"), relay.relaySession);
    relay.listeners[1].onComplete();
    Test.assertEqual(relay.envelopes.size(), 3);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true});
    Test.assertEqual(relay.envelopes.size(), 4);
    relay.applyRelayResult({"messageId" => "test-event", "relaySession" => oldSession, "ok" => true});
    oldListener.onComplete();
    oldListener.onError();
    Test.assertEqual(relay.pointReplyInFlight, "test-event");
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual((relay.envelopes[3].get("payload") as Dictionary).get("relaySession"), relay.relaySession);
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function reliableRelayAcknowledgementStorageFailure(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    Test.assert(relay.savePointReplies());
    relay.flushPointReplies();
    relay.storageAvailable = false;
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 1);
    relay.waitForRetry(5000);
    relay.storageAvailable = true;
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 0);
    return true;
}

(:test)
function reliableRelayLegacyStorageFailure(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.flushPointReplies();
    relay.storageAvailable = false;
    relay.listeners[0].onComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.waitForRetry(5000);
    relay.storageAvailable = true;
    relay.listeners[1].onComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual(relay.pointReplyRetryDelay, 5000);
    return true;
}

(:test)
function reliableRelayReplacementInFlight(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.pointReplies.replies[0].put("key", "same-point");
    relay.flushPointReplies();
    relay.addEvent("replacement-event", "same-point");
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, "replacement-event");
    relay.listeners[0].onError();
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplyInFlight, "replacement-event");
    relay.result("replacement-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function reliableRelayExpiryInFlight(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    relay.flushPointReplies();
    relay.epoch += 86399;
    relay.flushPointReplies();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.epoch++;
    relay.flushPointReplies();
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assert(relay.pointReplyInFlight == null);
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 0);
    relay.addEvent("fresh-event", null);
    relay.flushPointReplies();
    relay.result("test-event", true);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, "fresh-event");
    relay.listeners[0].onError();
    Test.assertEqual(relay.pointReplyInFlight, "fresh-event");
    return true;
}

(:test)
function reliableRelayEventCreationClock(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    Test.assert(relay.queueRelay("chat", {"text" => "Rgr", "replyTo" => "recipient"}, null));
    var event = relay.pointReplies.replies[0];
    Test.assertEqual(event.get("createdAt"), relay.epoch);
    Test.assertEqual((event.get("payload") as Dictionary).get("createdAt"), relay.epoch);
    Test.assertEqual(event.get("messageId"), "garmin-event-100000-1");
    return true;
}

(:test)
function reliableRelayQueueStorageFailure(logger) as Boolean {
    var relay = new TestReliableRelay();
    Test.assert(relay.savePointReplies());
    relay.storageAvailable = false;
    Test.assert(!relay.queueRelay("chat", {"text" => "New", "replyTo" => "recipient"}, null));
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplies.replies[0].get("messageId"), "test-event");
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 1);
    Test.assertEqual(relay.envelopes.size(), 0);
    return true;
}

(:test)
function reliableRelayRestartRestoresPendingEvent(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayResultRequired = true;
    Test.assert(relay.savePointReplies());
    relay.flushPointReplies();
    var restarted = new TestReliableRelay();
    restarted.pointReplies = new OfflineRelayQueue();
    restarted.pointReplies.restore(relay.stored.get("pointReplies"), restarted.epoch);
    restarted.relayResultRequired = true;
    restarted.flushPointReplies();
    Test.assertEqual(restarted.pointReplyInFlight, "test-event");
    Test.assertEqual((restarted.envelopes[0].get("payload") as Dictionary).get("messageId"), "test-event");
    restarted.result("test-event", true);
    Test.assertEqual(restarted.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function reliableRelayLegacyFallbackBoundary(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.relayNegotiating = true;
    relay.relayNegotiationAt = relay.clock;
    relay.clock += 14999;
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.clock++;
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assert((relay.envelopes[0].get("payload") as Dictionary).get("relaySession") == null);
    relay.listeners[0].onComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function reliableRelayMissingHelloNeverDowngrades(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true});
    relay.disconnect();
    relay.connect();
    relay.listeners[1].onComplete();
    relay.clock += 15000;
    relay.flushPointReplies();
    Test.assert(relay.relayResultRequired);
    Test.assertEqual(relay.envelopes.size(), 4);
    relay.listeners[3].onComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, "test-event");
    return true;
}

(:test)
class TestRelayMenuDelegate extends NetworkPreferencesDelegate {
    var relay as TakClient;

    function initialize(application as StandaloneApp, relayMenu as WatchUi.Menu2, client as TakClient) {
        NetworkPreferencesDelegate.initialize(application, relayMenu);
        relay = client;
    }

    function getRelayClient() as TakClient { return relay; }
}

(:test)
function reliableRelayCompanionMenuToggle(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var menu = buildTakRelayMenu(app);
    var relay = new TestReliableRelay();
    relay.status = :idle;
    var delegate = new TestRelayMenuDelegate(app, menu, relay);
    var companion = menu.getItem(menu.findItemById(:wearTakCompanionRelay));
    var atak = menu.getItem(menu.findItemById(:atakRelayToggle));
    Test.assert(companion != null && atak != null);
    Test.assertEqual(companion.getLabel(), "WearTAK Companion");
    Test.assert(menu.findItemById(:wearTakCompanionSetup) >= 0);
    delegate.onClientStatusChanged();
    Test.assertEqual(companion.getSubLabel(), toolToggleLabel(false));
    Test.assertEqual(atak.getSubLabel(), toolToggleLabel(false));
    delegate.onSelect(companion);
    Test.assertEqual(relay.status, :connecting);
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assertEqual(companion.getSubLabel(), toolToggleLabel(true));
    Test.assertEqual(atak.getSubLabel(), toolToggleLabel(true));
    delegate.onSelect(atak);
    Test.assertEqual(relay.status, :idle);
    Test.assertEqual(companion.getSubLabel(), toolToggleLabel(false));
    Test.assertEqual(atak.getSubLabel(), toolToggleLabel(false));
    delegate.onSelect(atak);
    Test.assertEqual(relay.status, :connecting);
    delegate.onSelect(companion);
    Test.assertEqual(relay.status, :idle);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(companion.getSubLabel(), atak.getSubLabel());
    return true;
}
