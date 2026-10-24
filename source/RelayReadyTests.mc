import Toybox.Lang;
import Toybox.Application;
import Toybox.Test;

(:test)
class RelayReadyAppFixture extends StandaloneApp {
    var relay as TestReliableRelay;
    var locationEnabled as Boolean = true;
    var refreshes as Number = 0;
    function initialize(client as TestReliableRelay) { relay = client; }
    function getTakClient() as TakClient { return relay; }
    function isLocationServicesEnabled() as Boolean { return locationEnabled; }
    function requestPositionForAction(action as String) as Void { relay.requestLocation(action); }
    function sendPliNow() as Boolean {
        refreshes++;
        relay.sendPli(60, "CURRENT", "Team Member", "Blue", null, 30, false);
        return true;
    }
}

(:test)
function currentPliHeartRateRequiresFreshActualOptedInSample(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    Test.assertEqual(app.pliHeartRateFromSample(72, 100, 160, true), 72);
    Test.assertEqual(app.pliHeartRateFromSample(20, 100, 100, true), 20);
    Test.assertEqual(app.pliHeartRateFromSample(250, 100, 100, true), 250);
    Test.assert(app.pliHeartRateFromSample(72, 100, 161, true) == null);
    Test.assert(app.pliHeartRateFromSample(72, 100, 99, true) == null);
    Test.assert(app.pliHeartRateFromSample(72, 100, 100, false) == null);
    Test.assert(app.pliHeartRateFromSample(72, null, 100, true) == null);
    Test.assert(app.pliHeartRateFromSample(null, 100, 100, true) == null);
    Test.assert(app.pliHeartRateFromSample(19, 100, 100, true) == null);
    Test.assert(app.pliHeartRateFromSample(251, 100, 100, true) == null);
    return true;
}

(:test)
function relayReadyRequestsCurrentPliOncePerValidatedSession(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    var app = new RelayReadyAppFixture(relay);
    relay.relayReadyCallback = app.method(:onRelayReady);
    relay.status = :idle;
    relay.connect();
    Test.assertEqual(app.refreshes, 0);
    relay.onRelayTransmitComplete();
    Test.assertEqual(app.refreshes, 0);
    var before = relay.envelopes.size();
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => false});
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => "false"});
    Test.assertEqual(relay.envelopes.size(), before);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false});
    Test.assertEqual(app.refreshes, 1);
    Test.assertEqual(relay.envelopes.size(), before + 2);
    Test.assertEqual(relay.envelopes[before].get("msgType"), "location_request");
    var hint = relay.envelopes[before].get("payload") as Dictionary;
    Test.assertEqual(hint.get("action"), "pli");
    Test.assertEqual(hint.get("relaySession"), relay.relaySession);
    Test.assertEqual(relay.envelopes[before + 1].get("msgType"), "pli");
    var pli = relay.envelopes[before + 1].get("payload") as Dictionary;
    Test.assertEqual(pli.get("callsign"), "CURRENT");
    Test.assert(!pli.hasKey("lat") && !pli.hasKey("lon") && !pli.hasKey("uid"));
    Test.assert(!pli.hasKey("hr") && !pli.hasKey("remarks"));
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false});
    relay.onRelayTransmitComplete();
    Test.assertEqual(app.refreshes, 1);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    relay.onRelayTransmitError();
    app.onRelayReady();
    Test.assertEqual(app.refreshes, 1);
    relay.clock++;
    relay.connect();
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false});
    Test.assertEqual(app.refreshes, 1);
    relay.onRelayTransmitComplete();
    Test.assertEqual(app.refreshes, 2);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    return true;
}

(:test)
function relayReadyRespectsLocationOptOutAndDoesNotReplayHistory(logger) as Boolean {
    var relay = new TestReliableRelay();
    var app = new RelayReadyAppFixture(relay);
    app.locationEnabled = false;
    relay.relayReadyCallback = app.method(:onRelayReady);
    relay.relayStatusAccepted = true;
    relay.notifyRelayReady();
    Test.assertEqual(app.refreshes, 0);
    Test.assertEqual(relay.envelopes.size(), 0);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    app.locationEnabled = true;
    relay.notifyRelayReady();
    Test.assertEqual(app.refreshes, 0);
    app.onRelayReady();
    Test.assertEqual(app.refreshes, 1);
    Test.assertEqual(relay.envelopes.size(), 2);
    Test.assertEqual(relay.envelopes[0].get("msgType"), "location_request");
    Test.assertEqual(relay.envelopes[1].get("msgType"), "pli");
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    return true;
}
