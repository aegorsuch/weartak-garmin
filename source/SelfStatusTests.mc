import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
class TestSelfStatusRelay extends TestReliableRelay {
    function initialize() { TestReliableRelay.initialize(); }
    function getWatchDeviceUid() as String { return "watch-device"; }
    function ready(version) as Void {
        applyRelayStatus({"relaySession" => relaySession, "reliableDelivery" => false, "selfStatus" => version});
    }
    function lastSelfStatus() as Dictionary {
        return envelopes[envelopes.size() - 1].get("payload") as Dictionary;
    }
}

(:test)
function selfStatusCapabilitySessionAndFullSnapshot(logger) as Boolean {
    var relay = new TestSelfStatusRelay();
    relay.pointReplies.replies = [];
    relay.selfStatus.setPpe(0, relay.cotTimestamp(new Toybox.Time.Moment(relay.epoch)));
    relay.selfStatus.sample(72, true);
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => false, "selfStatus" => 1});
    Test.assert(!relay.selfStatus.supported);
    relay.ready(true);
    Test.assert(!relay.selfStatus.supported);
    relay.ready(2);
    Test.assert(!relay.selfStatus.supported);
    relay.ready(1);
    Test.assertEqual(relay.envelopes[0].get("msgType"), "self_status");
    var payload = relay.lastSelfStatus();
    Test.assertEqual(payload.get("session"), "test-session");
    Test.assertEqual(payload.get("seq"), 0);
    Test.assertEqual(payload.get("deviceUid"), "watch-device");
    Test.assertEqual(payload.get("model"), "GARMIN");
    Test.assertEqual((payload.get("ppe") as Dictionary).get("level"), "MOPP 0");
    Test.assert(payload.hasKey("physio") && payload.get("physio") == null);
    relay.selfStatus.setPpe(null, relay.cotTimestamp(new Toybox.Time.Moment(relay.epoch)));
    Test.assertEqual((relay.lastSelfStatus().get("ppe") as Dictionary).get("level"), "None");
    Test.assertEqual(relay.lastSelfStatus().get("seq"), 1);
    relay.ready(2);
    relay.ready(1);
    Test.assertEqual(relay.lastSelfStatus().get("seq"), 2);
    relay.selfStatus.reset();
    relay.relaySession = "next-session";
    relay.ready(1);
    Test.assertEqual(relay.lastSelfStatus().get("session"), "next-session");
    Test.assertEqual(relay.lastSelfStatus().get("seq"), 0);
    Test.assert(relay.lastSelfStatus().get("physio") == null);
    return true;
}

(:test)
function selfStatusSamplesThrottleExpireAndNeverQueue(logger) as Boolean {
    var relay = new TestSelfStatusRelay();
    relay.pointReplies.replies = [];
    relay.ready(1);
    relay.selfStatus.sample(72, true);
    Test.assertEqual(relay.envelopes.size(), 1);
    relay.clock += 15000;
    relay.selfStatus.flush(false);
    var physio = relay.lastSelfStatus().get("physio") as Dictionary;
    Test.assertEqual(physio.get("hr"), 72);
    Test.assertEqual(physio.get("measuredAt"), relay.cotTimestamp(new Toybox.Time.Moment(relay.epoch)));
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    relay.selfStatus.sample(73, true);
    Test.assertEqual(relay.envelopes.size(), 2);
    relay.epoch += 121;
    relay.clock += 121000;
    relay.selfStatus.flush(false);
    Test.assert(relay.lastSelfStatus().get("physio") == null);
    var count = relay.envelopes.size();
    relay.clock += 59999;
    relay.selfStatus.flush(false);
    Test.assertEqual(relay.envelopes.size(), count);
    relay.clock++;
    relay.selfStatus.flush(false);
    Test.assertEqual(relay.envelopes.size(), count + 1);
    relay.selfStatus.sample(72, true);
    relay.selfStatus.clearPhysio();
    Test.assert(relay.lastSelfStatus().get("physio") == null);
    var invalid = [19, 251];
    for (var i = 0; i < invalid.size(); i++) {
        relay.clock += 15000;
        relay.selfStatus.sample(invalid[i], true);
        relay.selfStatus.flush(false);
        Test.assert(relay.lastSelfStatus().get("physio") == null);
    }
    relay.selfStatus.sample(72, false);
    relay.selfStatus.flush(true);
    Test.assert(relay.lastSelfStatus().get("physio") == null);
    relay.selfStatus.clearRemote();
    Test.assert(relay.lastSelfStatus().get("ppe") == null);
    relay.disconnect();
    count = relay.envelopes.size();
    relay.selfStatus.sample(72, true);
    relay.selfStatus.flush(true);
    Test.assertEqual(relay.envelopes.size(), count);
    Test.assert(relay.selfStatus.heartRate == null);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    relay.connect();
    Test.assertEqual(relay.envelopes[relay.envelopes.size() - 1].get("msgType"), "relay_hello");
    Test.assertEqual(relay.lastSelfStatus().get("watchUid"), "watch-device");
    relay.onRelayTransmitComplete();
    count = relay.envelopes.size();
    relay.selfStatus.sample(72, true);
    Test.assertEqual(relay.envelopes.size(), count);
    relay.ready(1);
    Test.assert(relay.lastSelfStatus().get("physio") == null);
    for (var hr = 20; hr <= 250; hr += 230) {
        relay.clock += 15000;
        relay.selfStatus.sample(hr, true);
        Test.assertEqual((relay.lastSelfStatus().get("physio") as Dictionary).get("hr"), hr);
    }
    relay.onRelayTransmitError();
    Test.assert(!relay.selfStatus.supported && relay.selfStatus.heartRate == null);
    return true;
}

(:test)
function selfStatusHonorsMonitoringAndBatdokOptOut(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var monitoring = app.isPhysiologicalMonitoringEnabled();
    var batdok = app.isBatdokCotEnabled();
    app.setPhysiologicalMonitoringEnabled(true);
    app.setBatdokCotEnabled(true);
    Test.assert(app.isSelfStatusPhysioEnabled());
    app.getTakClient().selfStatus.heartRate = 72;
    app.setBatdokCotEnabled(false);
    Test.assert(!app.isSelfStatusPhysioEnabled());
    Test.assert(app.getTakClient().selfStatus.heartRate == null);
    app.setBatdokCotEnabled(true);
    Test.assert(app.getTakClient().selfStatus.heartRate == null);
    app.setPhysiologicalMonitoringEnabled(false);
    Test.assert(!app.isSelfStatusPhysioEnabled());
    app.setPhysiologicalMonitoringEnabled(monitoring);
    app.setBatdokCotEnabled(batdok);
    return true;
}

(:test)
function selfStatusLegacyPpeNeedsExplicitSaveAndPliHasNoSignature(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = Application.Storage.getValue("moppLevel");
    Application.Storage.setValue("moppLevel", 2);
    app.loadMoppLevel();
    Test.assertEqual(app.getMoppLevel(), 2);
    Test.assert(app.getTakClient().selfStatus.ppe == null);
    Test.assertEqual(Application.Storage.getValue("moppLevel"), 2);
    Test.assert(app.setMoppLevel(2));
    app.loadMoppLevel();
    Test.assertEqual((app.getTakClient().selfStatus.ppe as Dictionary).get("level"), "MOPP 2");
    if (previous == null) { Application.Storage.deleteValue("moppLevel"); }
    else { Application.Storage.setValue("moppLevel", previous); }
    app.loadMoppLevel();
    var relay = new TestSelfStatusRelay();
    relay.sendPli(60, "WATCH", "Team Member", "Blue", 72, 30, true);
    Test.assert(!relay.lastSelfStatus().hasKey("remarks"));
    Test.assertEqual(relay.lastSelfStatus().get("hr"), 72);
    relay.pointReplies.replies = [];
    relay.ready(1);
    relay.sendPli(60, "WATCH", "Team Member", "Blue", 72, 30, true);
    Test.assert(!relay.lastSelfStatus().hasKey("remarks"));
    Test.assert(!relay.lastSelfStatus().hasKey("hr"));
    return true;
}
