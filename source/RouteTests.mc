import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
class RouteFixtures {
    static function payload(server as String, uid as String, count as Number) as Dictionary {
        var points = [];
        for (var i = 0; i < count; i++) {
            points.add({"lat" => 0.0, "lon" => i * 0.1, "name" => i == 0 ? "Start" : null});
        }
        return {"routeVersion" => 1, "serverId" => server, "uid" => uid,
            "name" => "Test route", "missionName" => "Mission", "senderUid" => "sender",
            "points" => points};
    }
}

(:test)
function routeAtomicValidationAndCapacity(logger) as Boolean {
    var store = new RouteStore();
    Test.assert(store.receive("route", RouteFixtures.payload("server", "one", 64)));
    Test.assert(store.receive("route", RouteFixtures.payload("server", "two", 64)));
    Test.assert(!store.receive("route", RouteFixtures.payload("server", "three", 2)));
    Test.assertEqual(store.routes.size(), 2);
    Test.assert(store.error != null);
    Test.assert(!store.receive("route", RouteFixtures.payload("server", "one", 65)));
    Test.assertEqual((store.find("server", "one").get("points") as Array).size(), 64);
    var invalid = RouteFixtures.payload("server", "one", 2);
    (invalid.get("points") as Array)[1].put("lat", 91);
    Test.assert(!store.receive("route", invalid));
    Test.assertEqual((store.find("server", "one").get("points") as Array).size(), 64);
    Test.assert(store.receive("route", RouteFixtures.payload("server", "one", 2)));
    Test.assert(store.receive("route", RouteFixtures.payload("server", "three", 2)));
    Test.assert(store.receive("routes_reset", {"routeVersion" => 1}));
    for (var i = 0; i < 8; i++) { Test.assert(store.receive("route", RouteFixtures.payload("s", i.toString(), 2))); }
    Test.assert(!store.receive("route", RouteFixtures.payload("s", "overflow", 2)));
    Test.assert(store.receive("route", RouteFixtures.payload("s", "0", 3)));
    Test.assertEqual(store.routes.size(), 8);
    return true;
}

(:test)
function routeSourceIdentityAndDeletion(logger) as Boolean {
    var store = new RouteStore();
    Test.assert(store.receive("route", RouteFixtures.payload("server-1", "shared", 2)));
    Test.assert(store.receive("route", RouteFixtures.payload("server-2", "shared", 2)));
    var first = store.pointId(store.find("server-1", "shared"), 1);
    var second = store.pointId(store.find("server-2", "shared"), 1);
    Test.assert(!first.equals(second));
    Test.assertEqual((store.point(first).get("route") as Dictionary).get("serverId"), "server-1");
    Test.assertEqual((store.point(second).get("route") as Dictionary).get("serverId"), "server-2");
    Test.assertEqual(store.title(store.point(second)), "Test route #2");
    Test.assert(store.point(second + "0") == null);
    Test.assert(!store.pointId({"serverId" => "a", "uid" => "bc"}, 0)
        .equals(store.pointId({"serverId" => "ab", "uid" => "c"}, 0)));
    Test.assert(store.receive("route_remove", {"routeVersion" => 1, "serverId" => "server-1", "uid" => "shared"}));
    Test.assert(store.point(first) == null);
    Test.assert(store.point(second) != null);
    Test.assert(store.receive("routes_reset", {"routeVersion" => 1}));
    Test.assertEqual(store.routes.size(), 0);
    return true;
}

(:test)
function routeMalformedIngress(logger) as Boolean {
    var store = new RouteStore();
    var cases = [
        {"routeVersion" => 2}, {"serverId" => ""}, {"uid" => " bad"}, {"name" => "\n"},
        {"points" => []}, {"points" => [{"lat" => true, "lon" => 0}, {"lat" => 0, "lon" => 0}]},
        {"points" => [{"lat" => 0, "lon" => 181}, {"lat" => 0, "lon" => 0}]},
        {"senderUid" => 1}, {"missionName" => false}
    ];
    for (var i = 0; i < cases.size(); i++) {
        var payload = RouteFixtures.payload("server", "route", 2);
        var key = cases[i].keys()[0];
        payload.put(key, cases[i].get(key));
        Test.assert(!store.receive("route", payload));
        Test.assertEqual(store.routes.size(), 0);
    }
    var longName = "";
    for (var i = 0; i < 65; i++) { longName += "x"; }
    var payload = RouteFixtures.payload("s", "r", 2);
    payload.put("name", longName);
    Test.assert(!store.receive("route", payload));
    Test.assert(store.receive("route", RouteFixtures.payload("s", "r", 2)));
    return true;
}

(:test)
function routePointSelectionAndBloodhound(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("server-1", "shared", 2));
    var other = RouteFixtures.payload("server-2", "shared", 2);
    (other.get("points") as Array)[1].put("lon", 0.5);
    map.receiveRoute("route", other);
    var route = map.routeStore.find("server-2", "shared");
    var id = map.routeStore.pointId(route, 1);
    var screen = map.routeScreenPoint((route.get("points") as Array)[1]);
    var hits = map.pointsAtScreen(screen[0], screen[1]);
    Test.assertEqual(hits.size(), 1);
    Test.assertEqual(hits[0], id);
    var menu = buildRoutePointMenu(map, id);
    Test.assertEqual(menu.getItem(0).getSubLabel(), "Test route");
    Test.assertEqual(menu.getItem(1).getSubLabel(), "server-2");
    Test.assertEqual(menu.getItem(2).getSubLabel(), "Mission");
    Test.assertEqual(menu.getItem(3).getSubLabel(), "sender");
    map.toggleRouteBloodhound(id);
    map.currentPosition = new Position.Location({:latitude => 0.0, :longitude => 0.0, :format => :degrees});
    Test.assert(map.isBloodhoundActive());
    Test.assertEqual(map.bloodhoundTarget().get("uid"), id);
    Test.assert(map.bloodhoundRelayTarget() == null);
    Test.assertEqual(map.getBloodhoundTitle(), "Test route #2");
    Test.assertEqual(map.getBloodhoundBearingDegrees(), 90);
    Test.assert(map.getBloodhoundRangeMeters() > 55000);
    Test.assert(map.getBloodhoundRangeMeters() < 56000);
    (other.get("points") as Array)[1].put("lon", 0.25);
    map.receiveRoute("route", other);
    Test.assert(map.getBloodhoundRangeMeters() > 27000);
    Test.assert(map.getBloodhoundRangeMeters() < 28000);
    map.routesVisible = false;
    Test.assertEqual(map.pointsAtScreen(screen[0], screen[1]).size(), 0);
    Test.assert(map.isBloodhoundActive());
    map.receiveRoute("route_remove", {"routeVersion" => 1, "serverId" => "server-1", "uid" => "shared"});
    Test.assert(map.isBloodhoundActive());
    map.receiveRoute("route_remove", {"routeVersion" => 1, "serverId" => "server-2", "uid" => "shared"});
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.pointLocations.hasKey(id));
    Test.assert(buildRoutePointMenu(map, id) == null);
    return true;
}

(:test)
function routeClippingAndOverlappingSelection(logger) as Boolean {
    var segment = clippedRouteSegment([-100.0, 50.0], [300.0, 50.0], 199, 199);
    Test.assertEqual(segment[0], 0.0);
    Test.assertEqual(segment[2], 199.0);
    Test.assert(clippedRouteSegment([-20.0, -20.0], [-10.0, -10.0], 199, 199) == null);
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("one", "shared", 2));
    map.receiveRoute("route", RouteFixtures.payload("two", "shared", 2));
    var hits = map.pointsAtScreen(100, 100);
    Test.assertEqual(hits.size(), 4);
    var menu = buildMapSelectionMenu(map, hits, false);
    Test.assertEqual(menu.getItem(0).getLabel(), "Start");
    Test.assert(!menu.getItem(0).getId().equals(menu.getItem(2).getId()));
    map.mapTopLeft = new Position.Location({:latitude => 1.0, :longitude => 179.0, :format => :degrees});
    map.mapBottomRight = new Position.Location({:latitude => -1.0, :longitude => -179.0, :format => :degrees});
    var screen = map.routeScreenPoint({"lat" => 0.0, "lon" => -179.5});
    Test.assert((screen[0] - 150.0).abs() < 0.1);
    return true;
}

(:test)
function routeTrackingStaysLocalAfterSyncedPoint(logger) as Boolean {
    var map = new TestMapSelectionView();
    var harness = new BloodhoundSyncHarness();
    harness.sync.activeTargetCallback = map.method(:bloodhoundRelayTarget);
    map.updateIncomingCot("ordinary", 1.0, 1.0, "a-f-G-U-C", "Ordinary", null, null, {});
    harness.sync.connectionChanged(true);
    map.setBloodhoundPoint("cot-ordinary");
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.lastPayload().get("action"), "start");
    map.receiveRoute("route", RouteFixtures.payload("server", "route", 2));
    var id = map.routeStore.pointId(map.routeStore.find("server", "route"), 1);
    map.toggleRouteBloodhound(id);
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.lastPayload().get("action"), "stop");
    Test.assertEqual(harness.lastPayload().get("target_uid"), "ordinary");
    Test.assert(map.isBloodhoundTarget(id));
    Test.assert(harness.sync.sessionId == null);
    Test.assertEqual(harness.sent.size(), 2);
    return true;
}

(:test)
class RouteRelayHarness extends TestEntitySyncRelay {
    var received as String? = null;
    function initialize() {
        TestEntitySyncRelay.initialize();
        incomingRouteCallback = method(:routeReceived);
    }

    function routeReceived(kind as String, payload as Dictionary) as Void { received = kind; }
}

(:test)
class RouteDrawingCapture {
    var lines as Array = [];
    var circles as Array = [];
    function initialize() {}
    function setColor(foreground, background) as Void {}
    function drawLine(x1, y1, x2, y2) as Void { lines.add([x1, y1, x2, y2]); }
    function fillCircle(x, y, radius) as Void { circles.add([x, y, radius]); }
}

(:test)
function routeOverlayDrawsLinesAndEveryVisibleVertex(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.mapTopLeft = new Position.Location({:latitude => 1.0, :longitude => -1.0, :format => :degrees});
    map.mapBottomRight = new Position.Location({:latitude => -1.0, :longitude => 1.0, :format => :degrees});
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var capture = new RouteDrawingCapture();
    map.drawRoutes(capture);
    Test.assertEqual(capture.lines.size(), 2);
    Test.assertEqual(capture.circles.size(), 3);
    Test.assertEqual((capture.circles[0] as Array)[0], 100);
    Test.assertEqual((capture.circles[0] as Array)[1], 100);
    map.routesVisible = false;
    map.drawRoutes(capture);
    Test.assertEqual(capture.lines.size(), 2);
    Test.assertEqual(capture.circles.size(), 3);
    return true;
}

(:test)
function routeEnvelopeDispatchAndCapability(logger) as Boolean {
    var relay = new RouteRelayHarness();
    relay.status = :connecting;
    relay.onRelayTransmitComplete();
    Test.assertEqual(relay.sentPayload.get("routeVersion"), 1);
    var kinds = ["route", "route_remove", "routes_reset", "routes_error"];
    for (var i = 0; i < kinds.size(); i++) {
        relay.handlePhoneEnvelope({"msgType" => kinds[i], "payload" => {"routeVersion" => 1}});
        Test.assertEqual(relay.received, kinds[i]);
    }
    return true;
}

(:test)
function routePointListDistinguishesRepeatedNames(logger) as Boolean {
    var map = new TestMapSelectionView();
    var payload = RouteFixtures.payload("s", "r", 2);
    (payload.get("points") as Array)[1].put("name", "Start");
    map.receiveRoute("route", payload);
    var menu = buildRoutePointsMenu(map, map.routeStore.find("s", "r"));
    Test.assertEqual(menu.getItem(0).getLabel(), "Start");
    Test.assertEqual(menu.getItem(1).getLabel(), "Start");
    Test.assertEqual(menu.getItem(0).getSubLabel(), "#1 0.00000, 0.00000");
    Test.assertEqual(menu.getItem(1).getSubLabel(), "#2 0.00000, 0.10000");
    Test.assert(!menu.getItem(0).getId().equals(menu.getItem(1).getId()));
    Test.assertEqual(menu.getItem(2).getId(), :cancel);
    return true;
}

(:test)
class RouteUnavailableCapture extends TestMapSelectionView {
    var unavailable as Boolean = false;
    function initialize() { TestMapSelectionView.initialize(); }
    function routeUnavailable() as Void { unavailable = true; }
}

(:test)
function routeStaleChatActionRejectsRemovedSender(logger) as Boolean {
    var map = new RouteUnavailableCapture();
    var payload = RouteFixtures.payload("s", "r", 2);
    map.receiveRoute("route", payload);
    var id = map.routeStore.pointId(map.routeStore.find("s", "r"), 0);
    var menu = buildRoutePointMenu(map, id);
    var chat = menu.getItem(7);
    Test.assertEqual(chat.getId(), :chat);
    payload.put("senderUid", null);
    map.receiveRoute("route", payload);
    var rooms = map.application.chats.rooms.size();
    new RoutePointMenuDelegate(map, id).onSelect(chat);
    Test.assert(map.unavailable);
    Test.assertEqual(map.application.chats.rooms.size(), rooms);
    Test.assertEqual(buildRoutePointMenu(map, id).getItem(7).getId(), :cancel);
    return true;
}

(:test)
function routeProjectionWaitsForValidMapBounds(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 2));
    var point = {"lat" => 0.0, "lon" => 0.0};
    map.mapBottomRight = map.mapTopLeft;
    Test.assert(map.routeScreenPoint(point) == null);
    var capture = new RouteDrawingCapture();
    map.drawRoutes(capture);
    Test.assertEqual(capture.lines.size(), 0);
    Test.assertEqual(capture.circles.size(), 0);
    Test.assertEqual(map.pointsAtScreen(100, 100).size(), 0);
    map.mapBottomRight = null;
    Test.assert(map.routeScreenPoint(point) == null);
    map.mapBottomRight = new Position.Location({:latitude => -1.0, :longitude => 1.0, :format => :degrees});
    Test.assert(map.routeScreenPoint(point) != null);
    map.drawRoutes(capture);
    Test.assertEqual(capture.lines.size(), 1);
    return true;
}

(:test)
function routeGeometryReevaluatesProximityAndResetStopsTracking(logger) as Boolean {
    var map = new TestMapSelectionView();
    var payload = RouteFixtures.payload("s", "r", 2);
    map.receiveRoute("route", payload);
    var id = map.routeStore.pointId(map.routeStore.find("s", "r"), 0);
    map.toggleRouteBloodhound(id);
    map.currentPosition = new Position.Location({:latitude => 0.0, :longitude => 0.0, :format => :degrees});
    map.bloodhoundProximityNotified = true;
    (payload.get("points") as Array)[0].put("lon", 90.0);
    map.receiveRoute("route", payload);
    Test.assert(!map.bloodhoundProximityNotified);
    Test.assert(map.isBloodhoundActive());
    map.receiveRoute("routes_reset", {"routeVersion" => 1});
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.pointLocations.hasKey(id));
    Test.assert(map.bloodhoundPointId == null);
    return true;
}
