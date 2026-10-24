import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;
import Toybox.Position;
import Toybox.WatchUi;

(:test)
class CotSymbolCapture extends RouteDrawingCapture {
    var outlines as Array = [];
    var colors as Array = [];
    var pen as Number = 1;
    function initialize() { RouteDrawingCapture.initialize(); }
    function drawCircle(x, y, radius) as Void { outlines.add([x, y, radius]); }
    function setColor(foreground, background) as Void { colors.add(foreground); }
    function setPenWidth(width) as Void { pen = width; }
}

(:test)
function cotSymbolsClassifyAcrossAffiliations(logger) as Boolean {
    var affiliations = ["f", "a", "h", "s", "n", "u", "p", "j", "k", "o", "x"];
    var families = ["A-C-F", "A-C-H", "A-M-F-Q", "A-M", "S", "G-U-C-I-I"];
    var expected = ["fixed", "rotary", "uav", "uav", "sea", "vehicle"];
    for (var i = 0; i < affiliations.size(); i++) {
        for (var j = 0; j < families.size(); j++) {
            var type = "a-" + affiliations[i] + "-" + families[j];
            Test.assertEqual(incomingCotSymbol(type), expected[j]);
            Test.assertEqual(incomingCotSymbol(type + "-X"), expected[j]);
            Test.assert(!isIncomingUser(type, {"isUser" => true}));
        }
    }
    Test.assertEqual(incomingCotSymbol("b-m-p-s-p-i"), "spi");
    var fallback = ["a-f-A-C-Foo", "a-f-A-C-Hoo", "a-f-A-More", "a-f-Sea",
        "a-f-G-U-C-I-II", "a-f-G-U-C", "a-f-Z", "b-m-p-s-m", "u-d-c-c", ""];
    for (var i = 0; i < fallback.size(); i++) { Test.assertEqual(incomingCotSymbol(fallback[i]), ""); }
    Test.assert(isIncomingUser("a-f-G-U-C", {}));
    return true;
}

(:test)
function cotSymbolsRenderWithoutChangingPointBehavior(logger) as Boolean {
    var map = new TestMapSelectionView();
    var types = ["a-f-A-C-F", "a-h-A-C-H", "a-u-A-M-F-Q", "a-n-S", "a-s-G-U-C-I-I", "b-m-p-s-p-i"];
    var lineCounts = [5, 6, 2, 7, 4, 2];
    for (var i = 0; i < types.size(); i++) {
        var id = "symbol-" + i;
        map.updateIncomingCot(id, 0.0, 0.0, types[i], id, null, null,
            {"isPoint" => true, "stale" => "2099-01-01T00:00:00Z"});
        Test.assert(map.incomingDetails.get("cot-" + id).get("generic") == true);
        Test.assert(incomingUserChatUid(map, "cot-" + id) == null);
        var capture = new CotSymbolCapture();
        Test.assert(map.drawIncomingCotSymbol(capture, 50, 50, types[i], incomingAffiliationColor(types[i])));
        Test.assertEqual(capture.lines.size(), lineCounts[i]);
        Test.assertEqual(capture.colors[0], Graphics.COLOR_BLACK);
        Test.assertEqual(capture.colors[1], incomingAffiliationColor(types[i]));
        Test.assertEqual(capture.pen, 1);
        Test.assertEqual(capture.circles[0][2], 11);
    }
    Test.assertEqual(map.markerArray().size(), types.size());
    map.updateIncomingCot("air-alert", 0.0, 0.0, "a-h-A-C-F", "Alert", null, null, {"isAlert" => true});
    map.markerArray();
    var capture = new CotSymbolCapture();
    map.drawIncomingUserOverlays(capture);
    Test.assertEqual(capture.lines.size(), 26);
    Test.assertEqual(capture.outlines.size(), 5);
    capture = new CotSymbolCapture();
    Test.assert(!map.drawIncomingCotSymbol(capture, 50, 50, "a-f-Z", Graphics.COLOR_BLUE));
    Test.assertEqual(capture.colors.size(), 0);
    map.updateIncomingCot("symbol-4", null, null, "t-x-d-d", null, null, null, {});
    Test.assert(!map.pointLocations.hasKey("cot-symbol-4"));
    map.updateIncomingCot("expired-boat", 0.0, 0.0, "a-f-S", "Old", null, null,
        {"stale" => "2000-01-01T00:00:00Z"});
    Test.assert(!map.pointLocations.hasKey("cot-expired-boat"));
    return true;
}

(:test)
function genericCotRelayRenderingAndSafeActions(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    var types = ["a-n-A-C-F", "a-n-A-C-H", "a-f-Z", "a-f-G-E", "b-m-p-s-m", "u-d-c-c"];
    for (var i = 0; i < types.size(); i++) {
        var uid = "generic-" + i;
        relay.receive("entity", {"uid" => uid, "type" => types[i], "lat" => 0.0, "lon" => 0.1,
            "callSign" => "Test " + i, "stale" => "2099-01-01T00:00:00Z"}, "current");
        var id = "cot-" + uid;
        Test.assertEqual(map.incomingPointTitle(id), "Test " + i);
        Test.assert((map.incomingDetails.get(id) as Dictionary).get("generic") == true);
        Test.assert(incomingUserChatUid(map, id) == null);
        var menu = buildIncomingPointActions(map, id);
        for (var j = 0; menu.getItem(j) != null; j++) {
            Test.assert(menu.getItem(j).getId() != :chat);
            Test.assert(menu.getItem(j).getId() != :rgr);
            Test.assert(menu.getItem(j).getId() != :npos);
        }
    }
    Test.assertEqual(map.markerArray().size(), types.size());
    Test.assertEqual(map.drawnPointIds.size(), types.size());
    Test.assertEqual(incomingAffiliationColor("a-f-Z"), Graphics.COLOR_BLUE);
    Test.assertEqual(incomingAffiliationColor("a-a-A"), Graphics.COLOR_BLUE);
    Test.assertEqual(incomingAffiliationColor("a-h-A"), Graphics.COLOR_RED);
    Test.assertEqual(incomingAffiliationColor("a-s-A"), Graphics.COLOR_RED);
    Test.assertEqual(incomingAffiliationColor("a-n-A-C-F"), Graphics.COLOR_GREEN);
    Test.assertEqual(incomingAffiliationColor("b-m-p-s-m"), Graphics.COLOR_YELLOW);
    map.updateIncomingCot("known", 0.0, 0.1, "a-h-G-T", "Known", null, null,
        {"isPoint" => true, "senderUID" => "sender"});
    Test.assert((map.incomingDetails.get("cot-known") as Dictionary).get("generic") == false);
    Test.assertEqual(buildIncomingPointActions(map, "cot-known").getItem(1).getId(), :rgr);
    map.updateIncomingCot("aircraft-point", 0.0, 0.1, "a-n-A-C-F", "Plane", null, null, {"isPoint" => true});
    Test.assert((map.incomingDetails.get("cot-aircraft-point") as Dictionary).get("generic") == true);
    return true;
}

(:test)
function genericCotHonorsStaleAndBoundedRetention(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.updateIncomingCot("expired", 0.0, 0.1, "a-n-A-C-F", null, null, null,
        {"stale" => "2000-01-01T00:00:00Z"});
    Test.assert(!map.incomingDetails.hasKey("cot-expired"));
    for (var i = 0; i < MAP_RETAINED_LIMIT + 1; i++) {
        map.updateIncomingCot("bounded-" + i, 0.0, i * 0.00001, "a-n-A-C-F", null, null, null,
            {"stale" => "2099-01-01T00:00:00Z"});
    }
    Test.assertEqual(map.incomingIds.size(), MAP_RETAINED_LIMIT);
    Test.assertEqual(map.pointLocations.size(), MAP_RETAINED_LIMIT);
    Test.assertEqual(map.markerArray().size(), MAP_DRAWN_LIMIT);
    Test.assert(!map.incomingDetails.hasKey("cot-bounded-0"));
    var id = "cot-bounded-1";
    (map.incomingDetails.get(id) as Dictionary).put("staleDeadline", "2000-01-01T00:00:00Z");
    Test.assert(map.pruneIncomingEntities());
    Test.assert(!map.incomingDetails.hasKey(id));
    id = "cot-bounded-2";
    map.incomingLastSeen.put(id, Time.now().value() - 301);
    Test.assert(map.pruneIncomingEntities());
    Test.assert(!map.incomingDetails.hasKey(id));
    return true;
}

(:test)
function genericCotDeleteWithoutCoordinatesAndOrdering(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    var point = {"uid" => "plane", "type" => "a-n-A-C-F", "lat" => 0.0, "lon" => 0.1,
        "time" => "2026-01-01T00:00:02Z"};
    relay.receive("entity", point, "current");
    map.toggleBloodhound("cot-plane");
    relay.receive("entity", {"uid" => "delete-event", "type" => "t-x-d-d",
        "link" => {"relation" => "p-p", "uid" => "plane"}, "time" => "2026-01-01T00:00:01Z"}, "current");
    Test.assert(map.incomingDetails.hasKey("cot-plane"));
    relay.receive("entity", {"uid" => "delete-event", "type" => "t-x-d-d",
        "link" => {"relation" => "p-p", "uid" => "plane"}, "time" => "2026-01-01T00:00:03Z"}, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-plane"));
    Test.assert(map.bloodhoundPointId == null);
    Test.assert(!map.incomingDetails.hasKey("cot-delete-event"));
    relay.receive("entity", point, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-plane"));
    point.put("time", "2026-01-01T00:00:04Z");
    relay.receive("entity", point, "current");
    Test.assert(map.incomingDetails.hasKey("cot-plane"));
    relay.receive("entity", {"uid" => "plane", "type" => "t-x-d-d"}, "current");
    Test.assert(!map.pointLocations.hasKey("cot-plane"));
    relay.receive("entity", point, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-plane"));
    map.updateIncomingCot("user", 0.0, 0.1, "a-f-G-U-C", "User", null, null, {});
    relay.receive("entity", {"uid" => "user", "type" => "t-x-d-d"}, "current");
    Test.assert(!map.userSourceStates.hasKey("user"));
    relay.receive("entity", {"uid" => "unseen", "type" => "t-x-d-d"}, "current");
    relay.receive("entity", {"uid" => "unseen", "type" => "a-n-A-C-H", "lat" => 0.0, "lon" => 0.1,
        "time" => "2000-01-01T00:00:00Z"}, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-unseen"));
    return true;
}

(:test)
function genericCotCircleOutlinesAreBounded(logger) as Boolean {
    Test.assert(incomingCircleRadius({"radius" => -1}) == null);
    Test.assert(incomingCircleRadius({"radius" => 100001}) == null);
    Test.assert(incomingCircleRadius({"radius" => "100"}) == null);
    Test.assertEqual(incomingCircleRadius({"shape" => {"ellipse" => {"major" => 100, "minor" => 100}}}), 100.0f);
    Test.assert(incomingCircleRadius({"shape" => {"ellipse" => {"major" => 100, "minor" => 200}}}) == null);
    var map = new TestMapSelectionView();
    for (var i = 0; i < 20; i++) {
        map.updateIncomingCot("circle-" + i, 0.0, 0.0, "u-d-c-c", "Circle", null, null, {"radius" => 100});
    }
    map.markerArray();
    var capture = new RouteDrawingCapture();
    map.drawIncomingCircles(capture);
    Test.assertEqual(capture.lines.size(), 16 * 32);
    map.mapBottomRight = null;
    capture = new RouteDrawingCapture();
    map.drawIncomingCircles(capture);
    Test.assertEqual(capture.lines.size(), 0);
    return true;
}

(:test)
function manualAlertRepeatedPressKeepsEventIdentity(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.relayResultRequired = true;
    Test.assert(relay.activateManualAlert("911 Alert"));
    var id = relay.pointReplyInFlight;
    for (var i = 0; i < 18; i++) { Test.assert(relay.activateManualAlert("911 Alert")); }
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplyInFlight, id);
    relay.listeners[0].onError();
    relay.waitForRetry(5000);
    Test.assertEqual((relay.envelopes[0].get("payload") as Dictionary).get("messageId"),
        (relay.envelopes[1].get("payload") as Dictionary).get("messageId"));
    relay.result(id as String, true);
    Test.assert(relay.activateManualAlert("911 Alert"));
    Test.assertEqual(relay.envelopes.size(), 2);
    relay.setAlerting(false);
    Test.assertEqual(relay.envelopes.size(), 3);
    var cancelId = relay.pointReplyInFlight as String;
    Test.assertEqual((relay.envelopes[2].get("payload") as Dictionary).get("state"), "CANCEL");
    relay.result(cancelId, true);
    Test.assert(relay.activateManualAlert("911 Alert"));
    Test.assertEqual(relay.envelopes.size(), 4);
    Test.assert(!(relay.pointReplyInFlight as String).equals(id));
    return true;
}

(:test)
function manualAlertStorageFailureAllowsRetry(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.storageAvailable = false;
    Test.assert(!relay.activateManualAlert("911 Alert"));
    Test.assert(!relay.alerting);
    relay.storageAvailable = true;
    Test.assert(relay.activateManualAlert("911 Alert"));
    Test.assert(relay.activateManualAlert("In Contact"));
    Test.assertEqual(relay.alertType, "In Contact");
    Test.assertEqual(relay.cotTimestamp(new Time.Moment(0)), "1970-01-01T00:00:00Z");
    return true;
}

(:test)
function freshLocationHintsAreImmediateAndDoNotBlockOutbox(logger) as Boolean {
    var relay = new TestReliableRelay();
    var actions = ["map", "navigation", "identity", "self_marker", "pli"];
    for (var i = 0; i < actions.size(); i++) {
        relay.requestLocation(actions[i]);
        var event = relay.envelopes[i];
        Test.assertEqual(event.get("msgType"), "location_request");
        var payload = event.get("payload") as Dictionary;
        Test.assertEqual(payload.get("action"), actions[i]);
        Test.assertEqual(payload.get("requestId"), payload.get("messageId"));
        Test.assertEqual(payload.get("relaySession"), relay.relaySession);
        Test.assertEqual(payload.get("createdAt"), relay.epoch);
        if (i > 0) {
            Test.assert(!(payload.get("messageId") as String).equals(
                (relay.envelopes[i - 1].get("payload") as Dictionary).get("messageId")));
        }
    }
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes[5].get("msgType"), "chat");
    return true;
}

(:test)
class SelfMarkerMapFixture extends TestMapSelectionView {
    function initialize() { TestMapSelectionView.initialize(); }
    function savePoints() as Void {}
}

(:test)
function phoneOwnedMarkerResolvesAfterAckWithoutWatchFix(logger) as Boolean {
    var map = new SelfMarkerMapFixture();
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.relayResultRequired = true;
    relay.phoneLocationSupported = true;
    map.setTakClient(relay);
    var id = "point-" + map.nextPointNumber;
    Test.assert(map.queuePoint(null, :friendly, "Self point", "120000Z", true));
    Test.assertEqual(relay.envelopes.size(), 1);
    var payload = relay.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(payload.get("locationSource"), "phone");
    Test.assert(payload.get("lat") == null);
    Test.assertEqual(map.pendingSelfPoints.size(), 1);
    relay.result(relay.pointReplyInFlight as String, true);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual((relay.stored.get("pendingSelfPoints") as Array).size(), 1);
    Test.assert(map.hasPoints());
    map.updateIncomingCot("garmin-marker-" + id, 38.0, -77.0, "a-f-G-T", "Self point", null, null,
        {"isPoint" => true, "time" => "2026-01-01T00:00:02Z"});
    Test.assertEqual(map.pendingSelfPoints.size(), 0);
    Test.assertEqual(map.incomingDetails.size(), 0);
    Test.assert(map.pointLocations.hasKey(id));
    Test.assertEqual(map.pointOrder.size(), 1);
    Test.assertEqual((map.pointDetails.get(id) as Dictionary).get("locationSource"), "phone");
    Test.assertEqual(relay.envelopes.size(), 1);
    map.updateIncomingCot("garmin-marker-" + id, 39.0, -78.0, "a-f-G-T", "Self point", null, null,
        {"isPoint" => true, "time" => "2026-01-01T00:00:03Z"});
    map.updateIncomingCot("garmin-marker-" + id, 37.0, -76.0, "a-f-G-T", "Self point", null, null,
        {"isPoint" => true, "time" => "2026-01-01T00:00:01Z"});
    Test.assert((map.pointLocations.get(id).toDegrees()[0] - 39.0).abs() < 0.00001);
    Test.assertEqual(map.pointOrder.size(), 1);
    return true;
}

(:test)
function pendingSelfMarkerFixDoesNotMutateInFlightPayload(logger) as Boolean {
    var map = new SelfMarkerMapFixture();
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    relay.relayResultRequired = true;
    relay.phoneLocationSupported = true;
    map.setTakClient(relay);
    var id = "point-" + map.nextPointNumber;
    Test.assert(map.queuePoint(null, :neutral, "Pending", "120000Z", true));
    var eventId = relay.pointReplyInFlight;
    var fix = new Position.Location({:latitude => 38.0, :longitude => -77.0, :format => :degrees});
    map.resolvePendingPoints(fix);
    Test.assert(map.pointLocations.hasKey(id));
    Test.assert((relay.pointReplies.replies[0].get("payload") as Dictionary).get("lat") == null);
    Test.assertEqual(relay.pointReplyInFlight, eventId);
    relay.listeners[0].onError();
    relay.waitForRetry(5000);
    Test.assert((relay.envelopes[1].get("payload") as Dictionary).get("lat") == null);
    Test.assertEqual((relay.envelopes[1].get("payload") as Dictionary).get("messageId"), eventId);
    return true;
}

(:test)
class PositionActionCapture extends TestPhoneSettingsApplication {
    var actions as Array<String> = [];
    function initialize() { TestPhoneSettingsApplication.initialize(); }
    function requestPositionForAction(action as String) as Void { actions.add(action); }
    function refreshIncomingPointCount() as Void {}
}

(:test)
function selfPositionActionSurfacesRequestFreshFix(logger) as Boolean {
    var app = new PositionActionCapture();
    app.setCallsign("GPS TEST");
    app.setMyTeamColor("Red");
    app.setMyRole("MIL", "Medic");
    Test.assertEqual(app.actions.size(), 3);
    for (var i = 0; i < 3; i++) { Test.assertEqual(app.actions[i], "identity"); }
    var map = new SelfMarkerMapFixture();
    map.setApplication(app);
    map.onShow();
    Test.assertEqual(app.actions[3], "map");
    map.updateIncomingCot("contact", 0.1, 0.1, "a-f-G-U-C", "Remote", null, null, {});
    map.setBloodhoundPoint("cot-contact");
    Test.assertEqual(app.actions[4], "navigation");
    map.receiveRoute("route", RouteFixtures.payload("server", "route", 2));
    Test.assert(map.startRoute(map.routeStore.routeId(map.routeStore.routes[0]), false));
    Test.assertEqual(app.actions[5], "navigation");
    var relay = new TestReliableRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    map.setTakClient(relay);
    map.dropAtCurrentLocationAs(:friendly);
    Test.assertEqual(app.actions[6], "self_marker");
    return true;
}

(:test)
function bloodhoundIconDistinguishesRoutesAndHidesWhenInactive(logger) as Boolean {
    var map = new TestMapSelectionView();
    Test.assert(map.bloodhoundTargetIcon() == null);
    map.updateIncomingCot("contact", 0.1, 0.1, "a-f-G-U-C", "Remote", null, null, {});
    map.setBloodhoundPoint("cot-contact");
    Test.assertEqual(map.bloodhoundTargetIcon(), Rez.Drawables.PickerHoundIcon);
    map.receiveRoute("route", RouteFixtures.payload("server", "route", 2));
    var route = map.routeStore.routes[0];
    Test.assert(map.startRoute(map.routeStore.routeId(route), false));
    Test.assertEqual(map.bloodhoundTargetIcon(), Rez.Drawables.PickerRouteIcon);
    map.stopRoute();
    Test.assert(map.bloodhoundTargetIcon() == null);
    map.toggleRouteBloodhound(map.routeStore.pointId(route, 1));
    Test.assertEqual(map.bloodhoundTargetIcon(), Rez.Drawables.PickerRouteIcon);
    var icon = WatchUi.loadResource(Rez.Drawables.PickerRouteIcon);
    Test.assertEqual(icon.getWidth(), 24);
    Test.assertEqual(icon.getHeight(), 24);
    return true;
}

(:test)
class MainMenuReturnCapture extends MainMenuReturn {
    var depth as Number = 3;
    var stopped as Boolean = false;
    var pops as Number = 0;
    function initialize() { MainMenuReturn.initialize(); }
    function isMainVisible() as Boolean { return depth == 0; }
    function hasCurrentView() as Boolean { return true; }
    function popCurrentView() as Void { depth--; pops++; }
    function stop() as Void { stopped = true; }
}

(:test)
class RouteStartReturnCapture extends RouteFollowDelegate {
    var returned as Boolean = false;
    function initialize(map as StandaloneMapView, id as String) { RouteFollowDelegate.initialize(map, id); }
    function returnToMainMenu() as Void { returned = true; }
}

(:test)
function routeStartUnwindsToMainMenu(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("server", "route", 2));
    var id = map.routeStore.routeId(map.routeStore.routes[0]);
    var main = buildMainMenu(map.application);
    Test.assertEqual(main.getItem(0).getId(), :incomingPoints);
    var follow = new RouteFollowMenu(map, id);
    var delegate = new RouteStartReturnCapture(map, id);
    delegate.onSelect(follow.getItem(1));
    Test.assert(delegate.returned);
    Test.assert(map.isBloodhoundActive());
    var navigation = new MainMenuReturnCapture();
    for (var i = 0; i < 3; i++) {
        navigation.step();
        Test.assertEqual(navigation.pops, i + 1);
        Test.assert(!navigation.stopped);
    }
    navigation.step();
    Test.assert(navigation.stopped);
    Test.assertEqual(navigation.pops, 3);
    navigation = new MainMenuReturnCapture();
    navigation.depth = 30;
    for (var i = 0; i < 17; i++) { navigation.step(); }
    Test.assert(navigation.stopped);
    Test.assertEqual(navigation.pops, 16);
    return true;
}

(:test)
function phoneLocationCapabilityPreservesLegacyMarkers(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    Test.assert(relay.sendSelfMarker("legacy", null, :friendly, "Legacy", ""));
    var payload = relay.pointReplies.replies[0].get("payload") as Dictionary;
    Test.assert(payload.get("locationSource") == null);
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => true, "phoneLocation" => true});
    Test.assert(!relay.phoneLocationSupported);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true, "phoneLocation" => true});
    Test.assert(relay.phoneLocationSupported);
    Test.assert(relay.sendSelfMarker("phone", null, :friendly, "Phone", ""));
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assertEqual((relay.envelopes[0].get("payload") as Dictionary).get("locationSource"), "phone");
    relay.disconnect();
    Test.assert(!relay.phoneLocationSupported);
    return true;
}
