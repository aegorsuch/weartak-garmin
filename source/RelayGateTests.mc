import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
class RelayGateFixture extends TestReliableRelay {
    var starts as Number = 0;
    var stops as Number = 0;
    var received as Number = 0;
    var releaseError as String? = null;
    var releases as Number = 0;
    var failStart as Boolean = false;
    var failRollback as Boolean = false;
    function initialize(saved as Dictionary) {
        stored = saved;
        TakClient.initialize();
        incomingChatCallback = method(:receiveChat);
        phoneSettingsCallback = method(:releaseSettings);
    }
    function startRelayRuntime() as Void {
        starts++;
        if (failStart) { throw new Lang.OperationNotAllowedException("Fixture start failed"); }
    }
    function stopRelayRuntime() as Void { stops++; relayRuntimeRunning = false; }
    function receiveChat(payload as Dictionary) as Void { received++; }
    function releaseSettings(payload) as String? {
        releases++;
        if (failRollback) { storageAvailable = false; }
        return releaseError;
    }
}

(:test)
function relayGateDefaultsOffResumesSavedIntentAndRetainsTransientIntent(logger) as Boolean {
    var relay = new RelayGateFixture({});
    Test.assert(!relay.relayEnabled && !relay.relayRuntimeRunning);
    relay.resumeRelay();
    Test.assertEqual(relay.starts, 0);
    relay.transmit("chat", {});
    relay.transmitEnvelope({"msgType" => "test", "payload" => {}}, new PhoneRelayListener(relay));
    relay.handlePhoneEnvelope({"msgType" => "chat", "payload" => {}});
    relay.handlePhoneEnvelope({"msgType" => "set_settings", "payload" => {}});
    relay.handlePhoneEnvelope({"msgType" => "request_settings", "payload" => {}});
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 0);
    Test.assertEqual(relay.received, 0);
    Test.assertEqual(relay.releases, 0);
    relay.connect();
    Test.assert(relay.relayEnabled && relay.relayRuntimeRunning);
    Test.assertEqual(relay.stored.get("companionRelayEnabled"), true);
    Test.assertEqual(relay.starts, 1);
    Test.assertEqual(relay.envelopes.size(), 1);
    relay.onRelayTransmitError();
    Test.assert(relay.relayEnabled);
    Test.assertEqual(relay.status, :failed);
    Test.assertEqual(relay.releases, 0);
    var restarted = new RelayGateFixture(relay.stored);
    Test.assert(restarted.relayEnabled && !restarted.relayRuntimeRunning);
    restarted.resumeRelay();
    Test.assertEqual(restarted.starts, 1);
    Test.assertEqual(restarted.status, :connecting);
    Test.assertEqual(restarted.envelopes[0].get("msgType"), "relay_hello");
    restarted.resumeRelay();
    Test.assertEqual(restarted.starts, 1);
    return true;
}

(:test)
function relayGateOffRetainsQueueFencesCallbacksIngressAndAllTransmitPaths(logger) as Boolean {
    var relay = new RelayGateFixture({});
    relay.connect();
    relay.status = :connected;
    relay.relayNegotiating = false;
    relay.addEvent("retained", null);
    Test.assert(relay.savePointReplies());
    relay.flushPointReplies();
    var stale = relay.listeners[relay.listeners.size() - 1];
    var phone = new PhoneRelayListener(relay);
    var count = relay.envelopes.size();
    var before = relay.pointReplies.replies.size();
    relay.disconnect();
    Test.assert(!relay.relayEnabled && !relay.relayRuntimeRunning);
    Test.assertEqual(relay.stored.get("companionRelayEnabled"), false);
    Test.assertEqual(relay.status, :idle);
    Test.assertEqual(relay.relaySession, "");
    Test.assertEqual(relay.stops, 1);
    Test.assertEqual(relay.pointReplies.replies.size(), before);
    stale.onComplete();
    stale.onError();
    phone.onComplete();
    phone.onError();
    relay.handlePhoneEnvelope({"msgType" => "chat", "payload" => {}});
    relay.applyRelayStatus({"relaySession" => "", "reliableDelivery" => true});
    relay.flushPointReplies();
    relay.transmit("chat", {});
    relay.transmitEnvelope({"msgType" => "marker_delete", "payload" => {}}, new PhoneRelayListener(relay));
    relay.sendPli(60, "", "", "", null, 30, false);
    relay.dataSync.sendRequest("missions_request", {}, "old");
    relay.selfStatus.send(null, null);
    Test.assertEqual(relay.envelopes.size(), count);
    Test.assertEqual(relay.received, 0);
    Test.assertEqual(relay.pointReplies.replies.size(), before);
    Test.assertEqual(relay.status, :idle);
    var restarted = new RelayGateFixture(relay.stored);
    restarted.resumeRelay();
    Test.assertEqual(restarted.starts, 0);
    Test.assertEqual(restarted.pointReplies.replies.size(), before);
    restarted.connect();
    restarted.onRelayTransmitComplete();
    restarted.applyRelayStatus({"relaySession" => restarted.relaySession, "reliableDelivery" => false});
    Test.assert(restarted.envelopes.size() >= 3);
    Test.assertEqual(restarted.pointReplies.replies.size(), before);
    return true;
}

(:test)
function relayGateQueueExpiryAndOldGenerationRemainEffectiveAfterReenable(logger) as Boolean {
    var relay = new RelayGateFixture({});
    relay.connect();
    var phone = new PhoneRelayListener(relay);
    relay.addEvent("expired", null);
    Test.assert(relay.savePointReplies());
    relay.disconnect();
    relay.epoch += relay.pointReplies.MAX_AGE_SECONDS;
    relay.flushPointReplies();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.connect();
    phone.onComplete();
    phone.onError();
    Test.assertEqual(relay.status, :connecting);
    relay.onRelayTransmitComplete();
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual((relay.stored.get("pointReplies") as Array).size(), 0);
    return true;
}

(:test)
function relayGateSaveReleaseAndStartFailuresRemainTruthful(logger) as Boolean {
    var relay = new RelayGateFixture({});
    relay.storageAvailable = false;
    relay.connect();
    Test.assert(!relay.relayEnabled);
    Test.assertEqual(relay.starts, 0);
    relay.storageAvailable = true;
    relay.connect();
    var generation = relay.relayGeneration;
    relay.storageAvailable = false;
    relay.disconnect();
    Test.assert(relay.relayEnabled && relay.relayRuntimeRunning);
    Test.assertEqual(relay.releases, 0);
    Test.assertEqual(relay.stops, 0);
    Test.assertEqual(relay.relayGeneration, generation);
    relay.storageAvailable = true;
    relay.releaseError = "Management release failed";
    relay.disconnect();
    Test.assert(relay.relayEnabled && relay.relayRuntimeRunning);
    Test.assertEqual(relay.stored.get("companionRelayEnabled"), true);
    Test.assertEqual(relay.relayGeneration, generation);
    relay.releaseError = null;
    relay.disconnect();
    Test.assert(!relay.relayEnabled);
    relay.failStart = true;
    relay.connect();
    Test.assert(relay.relayEnabled && !relay.relayRuntimeRunning);
    Test.assertEqual(relay.stored.get("companionRelayEnabled"), true);
    Test.assertEqual(relay.status, :failed);
    Test.assertEqual(relay.relayStateLabel(), WatchUi.loadResource(Rez.Strings.StatusFailed));
    relay.failRollback = true;
    relay.releaseError = "Management release failed";
    relay.disconnect();
    Test.assert(relay.relayEnabled);
    Test.assertEqual(relay.stored.get("companionRelayEnabled"), false);
    relay.storageAvailable = true;
    relay.failRollback = false;
    relay.releaseError = null;
    relay.disconnect();
    Test.assert(!relay.relayEnabled);
    return true;
}

(:test)
function relayGateDataSyncUsesGatedTransportAndFencesOldErrors(logger) as Boolean {
    var relay = new RelayGateFixture({});
    relay.connect();
    relay.status = :connected;
    var sync = relay.dataSync;
    sync.refresh();
    Test.assertEqual(relay.envelopes[relay.envelopes.size() - 1].get("msgType"), "missions_servers_request");
    var old = relay.listeners[relay.listeners.size() - 1];
    relay.disconnect();
    Test.assert(sync.requestId == null);
    relay.connect();
    relay.status = :connected;
    sync.refresh();
    var pending = sync.requestId;
    old.onError();
    Test.assertEqual(sync.requestId, pending);
    Test.assert(sync.error == null);
    return true;
}

(:test)
class RelayGateAppFixture extends StandaloneApp {
    var relay as RelayGateFixture;
    var locked as Boolean = false;
    var managed as Boolean = false;
    function initialize(client as RelayGateFixture) { relay = client; }
    function getTakClient() as TakClient { return relay; }
    function getSitxClient() as SitxClient { return (Application.getApp() as StandaloneApp).getSitxClient(); }
    function isNetworkPreferencesLocked() as Boolean { return locked; }
    function isPhoneManagedSettings() as Boolean { return managed; }
}

(:test)
function relayGateNativeChecklistUsesIntentAndLiveManagementGuards(logger) as Boolean {
    var relay = new RelayGateFixture({});
    var app = new RelayGateAppFixture(relay);
    var menu = buildNetworkPreferencesMenu(app);
    var item = menu.getItem(0) as WatchUi.ToggleMenuItem;
    Test.assertEqual(item.getId(), :wearTakCompanionRelay);
    Test.assert(!item.isEnabled());
    Test.assert(compareMenuLabels(menu.getItem(1).getLabel(), menu.getItem(2).getLabel()) <= 0);
    Test.assert(menu.getItem(3) == null);
    var config = buildTakRelayMenu(app);
    Test.assert(config.findItemById(:atakRelayToggle) < 0 && config.findItemById(:wearTakCompanionRelay) < 0);
    Test.assert(config.findItemById(:wearTakCompanionSetup) >= 0);
    var delegate = new NetworkPreferencesDelegate(app, menu);
    app.locked = true;
    delegate.onSelect(item);
    Test.assert(!relay.relayEnabled && !item.isEnabled());
    app.locked = false;
    app.managed = true;
    delegate.onSelect(item);
    Test.assert(!relay.relayEnabled && !item.isEnabled());
    app.managed = false;
    delegate.onSelect(item);
    Test.assert(relay.relayEnabled && item.isEnabled());
    relay.onRelayTransmitError();
    Test.assert(item.isEnabled());
    Test.assert(item.getSubLabel() == null);
    var status = buildTakRelayMenu(app);
    Test.assertEqual(status.getItem(status.findItemById(:relayState)).getSubLabel(),
        WatchUi.loadResource(Rez.Strings.StatusFailed));
    delegate.onSelect(item);
    Test.assert(!relay.relayEnabled && !item.isEnabled());
    var sitx = buildSitxDeviceApiMenu(app);
    var groups = buildSitxGroupsMenu(app);
    var host = app.getSitxClient().getOrganizationAddress();
    app.locked = true;
    var legacy = buildTakServerMenu();
    var legacyDelegate = new TakServerMenuDelegate(app, legacy);
    legacyDelegate.toggleConnect();
    Test.assert(!relay.relayEnabled);
    new SitxDeviceApiDelegate(app, sitx, menu).onSelect(sitx.getItem(sitx.findItemById(:sitxApiHost)));
    new SitxGroupsDelegate(app, groups, sitx, menu).onSelect(new WatchUi.MenuItem("Group", null, 0, null));
    Test.assert(!new SitxSettingsTextPickerDelegate(app, sitx).onTextEntered("not-saved.invalid", true));
    Test.assertEqual(app.getSitxClient().getOrganizationAddress(), host);
    app.locked = false;
    legacyDelegate.toggleConnect();
    Test.assertEqual(legacy.getItem(legacy.findItemById(:toggleConnect)).getLabel(),
        WatchUi.loadResource(Rez.Strings.LabelDisconnect));
    relay.onRelayTransmitError();
    legacyDelegate.toggleConnect();
    Test.assert(!relay.relayEnabled);
    return true;
}
