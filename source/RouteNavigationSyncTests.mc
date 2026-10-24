import Toybox.Lang;
import Toybox.Test;

(:test)
class RouteSyncHarness {
    var map as TestMapSelectionView;
    var relay as TestReliableRelay;
    var helper as BloodhoundSyncHarness;
    function initialize() {
        map = new TestMapSelectionView();
        relay = new TestReliableRelay();
        relay.pointReplies.replies = [];
        helper = new BloodhoundSyncHarness();
        relay.bloodhoundSync = helper.sync;
        relay.routeNavigationSync = new RouteNavigationSync(helper.sync);
        relay.routeNavigationSync.sendCallback = relay.method(:sendRouteNavigationMessage);
        relay.routeNavigationSync.relaySession = relay.relaySession;
        relay.routeNavigationSync.connectionChanged(true);
        map.setTakClient(relay);
        map.hasInitialPosition = true;
        map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    }
    function route() as Dictionary { return map.routeStore.routes[0]; }
    function id() as String { return map.routeStore.routeId(route()); }
    function state(action as String, seq as Number, index as Number) as Dictionary {
        return {"version" => 1, "relaySession" => relay.relaySession,
            "sessionId" => "11111111-1111-4111-8111-111111111111", "sequence" => seq,
            "action" => action, "serverId" => "s", "routeUid" => "r", "targetPointIndex" => index,
            "completed" => action.equals("stop")};
    }
    function receive(payload as Dictionary) as Void {
        relay.handlePhoneEnvelope({"msgType" => "phone_route_navigation", "payload" => payload});
    }
    function last() as Dictionary { return relay.envelopes[relay.envelopes.size() - 1].get("payload") as Dictionary; }
    function dispose() as Void { relay.routeNavigationSync.connectionChanged(false); }
    function ack(command as Dictionary, ok as Boolean) as Void {
        relay.handlePhoneEnvelope({"msgType" => "route_navigation_ack", "payload" => {
            "relaySession" => relay.relaySession, "requestId" => command.get("requestId"),
            "sessionId" => command.get("sessionId"), "ok" => ok, "error" => "Route rejected"}});
    }
}

(:test)
function phoneRouteOwnsProgressAndCompletionWithoutEcho(logger) as Boolean {
    var h = new RouteSyncHarness();
    h.receive(h.state("start", 0, 0));
    Test.assertEqual(h.map.followingRouteId, h.id());
    Test.assert(h.map.followingRoutePhoneOwned);
    h.map.updatePosition(new RouteGpsFix(RouteNavigation.location((h.route().get("points") as Array)[0])));
    Test.assertEqual(h.map.followingRouteIndex, 0);
    h.receive(h.state("progress", 1, 2));
    Test.assertEqual(h.map.followingRouteIndex, 2);
    h.map.updatePosition(new RouteGpsFix(RouteNavigation.location((h.route().get("points") as Array)[2])));
    Test.assert(h.map.isBloodhoundActive());
    h.receive(h.state("stop", 2, 2));
    Test.assert(!h.map.isBloodhoundActive());
    Test.assert(!h.map.followingRoutePhoneOwned);
    Test.assertEqual(h.relay.envelopes.size(), 0);
    h.receive(h.state("start", 3, 0));
    Test.assert(!h.map.isBloodhoundActive());
    h.dispose();
    return true;
}

(:test)
function phoneRouteRejectsInvalidStaleAndCrossServerState(logger) as Boolean {
    var h = new RouteSyncHarness();
    var invalid = [{"version" => "1"}, {"version" => 2}, {"relaySession" => "old"},
        {"sessionId" => "not-a-uuid"}, {"sequence" => -1}, {"sequence" => 0.5},
        {"sequence" => null}, {"action" => "move"}, {"routeUid" => ""},
        {"serverId" => ""}, {"targetPointIndex" => -1}, {"targetPointIndex" => 0.5},
        {"targetPointIndex" => 3}, {"routeUid" => "missing"}, {"serverId" => "other"}];
    for (var i = 0; i < invalid.size(); i++) {
        var state = h.state("start", 0, 0);
        var changes = invalid[i] as Dictionary;
        state.put(changes.keys()[0], changes.get(changes.keys()[0]));
        h.receive(state);
        Test.assert(!h.map.isBloodhoundActive());
    }
    h.receive(h.state("start", 0, 1));
    h.receive(h.state("progress", 0, 2));
    Test.assertEqual(h.map.followingRouteIndex, 1);
    var mismatch = h.state("progress", 1, 2);
    mismatch.put("serverId", "other");
    h.receive(mismatch);
    Test.assertEqual(h.map.followingRouteIndex, 1);
    var stop = h.state("stop", 1, 1);
    stop.put("completed", "true");
    h.receive(stop);
    Test.assert(h.map.isBloodhoundActive());
    h.receive(h.state("progress", 2, 2));
    h.receive(h.state("progress", 1, 0));
    Test.assertEqual(h.map.followingRouteIndex, 2);
    Test.assertEqual(h.relay.envelopes.size(), 0);
    h.dispose();
    return true;
}

(:test)
function watchRouteStartStopUsesScopedProtocolAndPhoneAuthority(logger) as Boolean {
    var h = new RouteSyncHarness();
    Test.assert(h.map.startRoute(h.id(), false));
    var start = h.last();
    Test.assertEqual(h.relay.envelopes[0].get("msgType"), "watch_route_navigation");
    Test.assertEqual(start.get("version"), 1);
    Test.assertEqual(start.get("serverId"), "s");
    Test.assertEqual(start.get("routeUid"), "r");
    Test.assertEqual(start.get("targetPointIndex"), 0);
    Test.assert(h.helper.sync.validUuid(start.get("sessionId")));
    Test.assert(h.helper.sync.validUuid(start.get("requestId")));
    Test.assertEqual(start.get("relaySession"), h.relay.relaySession);
    h.map.updatePosition(new RouteGpsFix(RouteNavigation.location((h.route().get("points") as Array)[0])));
    Test.assertEqual(h.map.followingRouteIndex, 0);
    h.ack(start, true);
    Test.assertEqual(h.relay.routeNavigationSync.pending.size(), 1);
    var state = h.state("start", 0, 1);
    state.put("sessionId", start.get("sessionId"));
    h.receive(state);
    Test.assertEqual(h.relay.routeNavigationSync.pending.size(), 0);
    Test.assertEqual(h.map.followingRouteIndex, 1);
    Test.assertEqual(h.relay.envelopes.size(), 1);
    h.map.stopRoute();
    var stop = h.last();
    Test.assertEqual(stop.get("action"), "stop");
    Test.assertEqual(stop.get("sessionId"), start.get("sessionId"));
    Test.assert(stop.get("requestId") != start.get("requestId"));
    Test.assert(!h.map.isBloodhoundActive());
    state.put("sequence", 1);
    h.receive(state);
    Test.assert(!h.map.isBloodhoundActive());
    h.ack(stop, true);
    Test.assertEqual(h.relay.routeNavigationSync.pending.size(), 0);
    h.dispose();
    return true;
}

(:test)
function watchRouteStopBeforeAckAndDelayedFailureCannotCancelReplacement(logger) as Boolean {
    var h = new RouteSyncHarness();
    Test.assert(h.map.startRoute(h.id(), false));
    var start = h.last();
    h.map.stopRoute();
    Test.assertEqual(h.last().get("sessionId"), start.get("sessionId"));
    Test.assert(h.map.startRoute(h.id(), false));
    var replacement = h.last();
    h.ack(start, false);
    Test.assert(h.map.isBloodhoundActive());
    Test.assertEqual(h.relay.routeNavigationSync.sessionId, replacement.get("sessionId"));
    var old = h.state("start", 1, 2);
    old.put("sessionId", start.get("sessionId"));
    h.receive(old);
    Test.assertEqual(h.map.followingRouteIndex, 0);
    h.ack(replacement, false);
    Test.assert(!h.map.isBloodhoundActive());
    Test.assert(h.helper.errors.size() > 0);
    h.dispose();
    return true;
}

(:test)
function watchRouteTimeoutTransportAndDisconnectAreExplicit(logger) as Boolean {
    var h = new RouteSyncHarness();
    Test.assert(h.map.startRoute(h.id(), false));
    h.helper.clockValue += ROUTE_NAV_ACK_SECONDS;
    h.relay.routeNavigationSync.checkTimeouts();
    Test.assert(!h.map.isBloodhoundActive());
    Test.assert(h.helper.errors.size() > 0);
    Test.assert(h.map.startRoute(h.id(), false));
    h.relay.listeners[h.relay.listeners.size() - 1].onError();
    Test.assert(!h.map.isBloodhoundActive());
    Test.assert(h.map.startRoute(h.id(), false));
    h.relay.routeNavigationSync.connectionChanged(false);
    Test.assert(!h.map.isBloodhoundActive());
    Test.assertEqual(h.relay.routeNavigationSync.pending.size(), 0);
    Test.assert(h.map.startRoute(h.id(), false));
    Test.assert(!h.map.followingRoutePhoneOwned);
    h.map.updatePosition(new RouteGpsFix(RouteNavigation.location((h.route().get("points") as Array)[0])));
    Test.assertEqual(h.map.followingRouteIndex, 1);
    h.map.stopRoute();
    h.dispose();
    return true;
}

(:test)
function phoneRouteRemovalResetAndPointSwitchStopNativeNavigation(logger) as Boolean {
    var h = new RouteSyncHarness();
    h.receive(h.state("start", 0, 1));
    Test.assert(h.map.removeLocalRoute(h.id()));
    Test.assertEqual(h.last().get("action"), "stop");
    Test.assert(!h.map.isBloodhoundActive());
    h.dispose();
    h = new RouteSyncHarness();
    h.receive(h.state("start", 0, 1));
    h.map.receiveRoute("routes_reset", {"routeVersion" => 1});
    Test.assertEqual(h.last().get("action"), "stop");
    Test.assert(!h.map.isBloodhoundActive());
    h.dispose();
    h = new RouteSyncHarness();
    h.receive(h.state("start", 0, 1));
    h.map.updateIncomingCot("other", 1.0, 1.0, "a-f-G", "Other", null, null, {});
    h.map.toggleBloodhound("cot-other");
    Test.assertEqual(h.last().get("action"), "stop");
    Test.assert(h.map.isBloodhoundTarget("cot-other"));
    h.dispose();
    return true;
}

(:test)
function routeNavigationCapabilityIsVersionAndRelayScoped(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.status = :idle;
    relay.connect();
    Test.assertEqual((relay.envelopes[0].get("payload") as Dictionary).get("routeNavigationVersion"), 1);
    relay.listeners[0].onComplete();
    for (var i = 0; i < 4; i++) {
        var versions = [null, "1", 2, true];
        relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false,
            "routeNavigationVersion" => versions[i]});
        Test.assert(!relay.routeNavigationSync.connected);
    }
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => false, "routeNavigationVersion" => 1});
    Test.assert(!relay.routeNavigationSync.connected);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => false, "routeNavigationVersion" => 1});
    Test.assert(relay.routeNavigationSync.connected);
    relay.disconnect();
    Test.assert(!relay.routeNavigationSync.connected);
    return true;
}
