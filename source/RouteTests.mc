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
            points.add({"lat" => 0.0, "lon" => i * 0.1, "name" => i == 0 ? "Start" : null, "type" => "b-m-p-w"});
        }
        return {"routeVersion" => 1, "serverId" => server, "uid" => uid,
            "name" => "Test route", "missionName" => "Mission", "senderUid" => "sender", "method" => "Driving",
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
        {"senderUid" => 1}, {"missionName" => false}, {"method" => 4},
        {"points" => [{"lat" => 0, "lon" => 0, "type" => 1}, {"lat" => 0, "lon" => 1}]}
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
function routeRetainsMethodAndRawControlPointMetadata(logger) as Boolean {
    var payload = RouteFixtures.payload("s", "r", 3);
    payload.put("method", "Watercraft");
    var points = payload.get("points") as Array;
    (points[0] as Dictionary).remove("type");
    points[1].put("type", "b-m-p-c");
    var store = new RouteStore();
    Test.assert(store.receive("route", payload));
    var route = store.routes[0];
    var saved = route.get("points") as Array;
    Test.assertEqual(route.get("method"), "Watercraft");
    Test.assert(saved[0].get("type") == null);
    Test.assertEqual(saved[1].get("type"), "b-m-p-c");
    Test.assertEqual(saved[2].get("type"), "b-m-p-w");
    Test.assertEqual(saved.size(), 3);
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

(:test)
class RouteSelectionCapture extends RouteUnavailableCapture {
    var openedRoute as String? = null;
    var openedPoint as String? = null;
    function initialize() { RouteUnavailableCapture.initialize(); }
    function showRoute(id as String) as Void { openedRoute = id; }
    function showRoutePoint(id as String) as Void { openedPoint = id; }
}

(:test)
class RouteRemovalCapture extends RouteRemovalDelegate {
    var closed as Boolean = false;
    var removed as Boolean = false;
    function initialize(map as StandaloneMapView, id as String) {
        RouteRemovalDelegate.initialize(map, id);
    }
    function close(didRemove as Boolean) as Void { closed = true; removed = didRemove; }
}

(:test)
function routeWholeDetailsAndPointNavigation(logger) as Boolean {
    var map = new RouteSelectionCapture();
    var payload = RouteFixtures.payload("server", "route", 3);
    (payload.get("points") as Array)[2].put("name", "Finish");
    map.receiveRoute("route", payload);
    var route = map.routeStore.find("server", "route");
    var id = map.routeStore.routeId(route);
    new RoutesMenuDelegate(map).onSelect(buildRoutesMenu(map).getItem(1));
    Test.assertEqual(map.openedRoute, id);
    var menu = buildRouteMenu(map, id);
    Test.assertEqual(menu.getItem(0).getId(), :points);
    Test.assertEqual(menu.getItem(0).getSubLabel(), "2 named / 3 total");
    Test.assertEqual(menu.getItem(1).getSubLabel(), "server");
    Test.assertEqual(menu.getItem(2).getSubLabel(), "Mission");
    Test.assertEqual(menu.getItem(3).getSubLabel(), "sender");
    Test.assertEqual(menu.getItem(4).getId(), :remove);
    var points = buildRoutePointsMenu(map, route);
    new RoutePointListDelegate(map).onSelect(points.getItem(1));
    var pointId = map.routeStore.pointId(route, 2);
    Test.assertEqual(map.openedPoint, pointId);
    map.openedRoute = null;
    var pointMenu = buildRoutePointMenu(map, pointId);
    Test.assertEqual(pointMenu.getItem(0).getId(), :route);
    new RoutePointMenuDelegate(map, pointId).onSelect(pointMenu.getItem(0));
    Test.assertEqual(map.openedRoute, id);
    map.openedRoute = null;
    map.showSelectedMapItem(id);
    Test.assertEqual(map.openedRoute, id);
    return true;
}

(:test)
function routePointListFiltersOnlyNamesAndPreservesOriginalGeometry(logger) as Boolean {
    var map = new RouteSelectionCapture();
    var payload = RouteFixtures.payload("one", "shared", 6);
    var points = payload.get("points") as Array;
    points[0].put("name", null);
    points[1].put("name", "");
    points[2].put("name", "Checkpoint");
    points[3].put("name", "\u00a0\u2003");
    points[4].put("name", null);
    points[5].put("name", "Checkpoint");
    map.receiveRoute("route", payload);
    payload.put("serverId", "two");
    map.receiveRoute("route", payload);
    var route = map.routeStore.find("one", "shared");
    var other = map.routeStore.find("two", "shared");
    var indices = map.routeStore.namedPointIndices(route);
    Test.assertEqual(indices.size(), 2);
    Test.assertEqual(indices[0], 2);
    Test.assertEqual(indices[1], 5);
    var menu = buildRoutePointsMenu(map, route);
    Test.assertEqual(menu.getItem(0).getLabel(), "Checkpoint");
    Test.assertEqual(menu.getItem(1).getLabel(), "Checkpoint");
    Test.assertEqual(menu.getItem(0).getSubLabel(), "#3 0.00000, 0.20000");
    Test.assertEqual(menu.getItem(1).getSubLabel(), "#6 0.00000, 0.50000");
    Test.assertEqual(menu.getItem(0).getId(), map.routeStore.pointId(route, 2));
    Test.assertEqual(menu.getItem(1).getId(), map.routeStore.pointId(route, 5));
    Test.assertEqual(menu.getItem(2).getId(), :cancel);
    Test.assert(menu.getItem(3) == null);
    Test.assert(!menu.getItem(1).getId().equals(map.routeStore.pointId(other, 5)));
    new RoutePointListDelegate(map).onSelect(menu.getItem(1));
    Test.assertEqual(map.openedPoint, map.routeStore.pointId(route, 5));
    map.toggleRouteBloodhound(map.openedPoint);
    Test.assertEqual(map.routeStore.point(map.openedPoint).get("index"), 5);
    Test.assertEqual((map.routeStore.point(map.openedPoint).get("point") as Dictionary).get("lon"), 0.5);
    Test.assertEqual((route.get("points") as Array).size(), 6);
    for (var i = 0; i < 6; i++) {
        Test.assertEqual((route.get("points") as Array)[i].get("lon"), points[i].get("lon"));
    }
    var summary = buildRouteMenu(map, map.routeStore.routeId(route));
    Test.assertEqual(summary.getItem(0).getSubLabel(), "2 named / 6 total");
    var unnamedId = map.routeStore.pointId(route, 4);
    Test.assert(buildRoutePointMenu(map, unnamedId) != null);
    map.showSelectedMapItem(unnamedId);
    Test.assertEqual(map.openedPoint, unnamedId);
    map.toggleRouteBloodhound(unnamedId);
    Test.assert(map.isBloodhoundTarget(unnamedId));
    var screen = map.routeScreenPoint((route.get("points") as Array)[4]);
    Test.assert(map.pointsAtScreen(screen[0], screen[1]).indexOf(unnamedId) != -1);
    return true;
}

(:test)
function routePointListEmptyStateKeepsWholeRouteActions(logger) as Boolean {
    var map = new RouteSelectionCapture();
    var payload = RouteFixtures.payload("s", "r", 2);
    (payload.get("points") as Array)[0].put("name", "");
    map.receiveRoute("route", payload);
    var route = map.routeStore.find("s", "r");
    var menu = buildRoutePointsMenu(map, route);
    Test.assertEqual(menu.getItem(0).getLabel(), WatchUi.loadResource(Rez.Strings.RoutesNoNamedPoints));
    Test.assertEqual(menu.getItem(0).getId(), :empty);
    Test.assertEqual(menu.getItem(1).getId(), :cancel);
    Test.assert(menu.getItem(2) == null);
    new RoutePointListDelegate(map).onSelect(menu.getItem(0));
    Test.assert(map.openedPoint == null);
    var summary = buildRouteMenu(map, map.routeStore.routeId(route));
    Test.assertEqual(summary.getItem(0).getSubLabel(), "0 named / 2 total");
    Test.assertEqual(summary.getItem(4).getId(), :remove);
    Test.assertEqual((route.get("points") as Array).size(), 2);
    Test.assert(!map.routeStore.hasPointName({"name" => " \t\r\n"}));
    Test.assert(!map.routeStore.hasPointName({"name" => "\u0085\u1680\u2000\u200a\u2028\u2029\u202f\u205f\u3000"}));
    Test.assert(map.routeStore.hasPointName({"name" => "CP 1"}));
    return true;
}

(:test)
function routeLineSelectionThresholdClippingAndOverlap(logger) as Boolean {
    var map = new TestMapSelectionView();
    var payload = RouteFixtures.payload("one", "shared", 2);
    (payload.get("points") as Array)[0].put("lon", -2.0);
    (payload.get("points") as Array)[1].put("lon", 2.0);
    map.receiveRoute("route", payload);
    var id = map.routeStore.routeId(map.routeStore.find("one", "shared"));
    Test.assertEqual(map.pointsAtScreen(100, 100).size(), 0);
    Test.assertEqual(map.routesAtScreen(100, 114).size(), 1);
    Test.assertEqual(map.routesAtScreen(100, 115).size(), 0);
    Test.assertEqual(map.routesAtScreen(-1, 100).size(), 0);
    Test.assertEqual(map.routesAtScreen(200, 100).size(), 0);
    map.showMapItemsAtScreen(100, 100);
    Test.assertEqual(map.openedId, id);
    payload.put("serverId", "two");
    map.receiveRoute("route", payload);
    var hits = map.routesAtScreen(100, 100);
    Test.assertEqual(hits.size(), 2);
    Test.assert(!hits[0].equals(hits[1]));
    map.showMapItemsAtScreen(100, 100);
    var menu = map.selectionMenu;
    Test.assertEqual(menu.getItem(0).getId(), hits[0]);
    Test.assertEqual(menu.getItem(1).getId(), hits[1]);
    Test.assertEqual(menu.getItem(0).getSubLabel(), "Whole route | one");
    Test.assertEqual(menu.getItem(1).getSubLabel(), "Whole route | two");
    map.routesVisible = false;
    Test.assertEqual(map.routesAtScreen(100, 100).size(), 0);
    map.routesVisible = true;
    map.mapBottomRight = map.mapTopLeft;
    Test.assertEqual(map.routesAtScreen(100, 100).size(), 0);
    map.mapBottomRight = null;
    Test.assertEqual(map.routesAtScreen(100, 100).size(), 0);
    return true;
}

(:test)
function routeLineSelectionVerticesAndDateline(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.mapTopLeft = new Position.Location({:latitude => 1.0, :longitude => 179.0, :format => :degrees});
    map.mapBottomRight = new Position.Location({:latitude => -1.0, :longitude => -179.0, :format => :degrees});
    var payload = RouteFixtures.payload("s", "r", 3);
    var points = payload.get("points") as Array;
    points[0].put("lon", 179.25);
    points[1].put("lon", -179.25);
    points[2].put("lon", -179.25);
    map.receiveRoute("route", payload);
    Test.assertEqual(map.routesAtScreen(100, 100).size(), 1);
    Test.assertEqual(map.routesAtScreen(175, 100).size(), 1);
    map.showMapItemsAtScreen(175, 100);
    var menu = map.selectionMenu;
    Test.assertEqual(menu.getItem(0).getLabel(), "Test route #2");
    Test.assertEqual(menu.getItem(1).getLabel(), "Test route #3");
    Test.assertEqual(menu.getItem(2).getId(), map.routeStore.routeId(map.routeStore.find("s", "r")));
    Test.assertEqual(menu.getItem(3).getId(), :cancel);
    Test.assert(routeSegmentAtScreen([100.0, 100.0, 100.0, 100.0], 100, 114));
    Test.assert(!routeSegmentAtScreen([100.0, 100.0, 100.0, 100.0], 100, 115));
    points[0].put("lon", 0.0);
    points[1].put("lon", 1.0);
    points[2].put("lon", 2.0);
    map.receiveRoute("route", payload);
    Test.assertEqual(map.routesAtScreen(100, 100).size(), 0);
    return true;
}

(:test)
function routeRemovalRequiresConfirmationAndStaysWatchLocal(logger) as Boolean {
    var map = new RouteUnavailableCapture();
    var relay = new TestEntitySyncRelay();
    map.takClient = relay;
    map.receiveRoute("route", RouteFixtures.payload("one", "shared", 2));
    map.receiveRoute("route", RouteFixtures.payload("two", "shared", 2));
    var first = map.routeStore.find("one", "shared");
    var second = map.routeStore.find("two", "shared");
    var id = map.routeStore.routeId(first);
    var target = map.routeStore.pointId(first, 0);
    var otherTarget = map.routeStore.pointId(second, 0);
    map.toggleRouteBloodhound(target);
    var menu = buildRouteRemovalMenu(first);
    Test.assertEqual(menu.getItem(0).getSubLabel(), "one");
    Test.assertEqual(menu.getItem(1).getLabel(), "Server route is unchanged");
    Test.assertEqual(menu.getItem(2).getId(), :cancel);
    Test.assertEqual(menu.getItem(3).getId(), :confirmRemove);
    var cancelled = new RouteRemovalCapture(map, id);
    cancelled.onSelect(menu.getItem(0));
    Test.assert(!cancelled.closed);
    cancelled.onSelect(menu.getItem(2));
    Test.assert(cancelled.closed && !cancelled.removed);
    Test.assert(map.routeStore.route(id) != null);
    Test.assert(map.isBloodhoundTarget(target));
    var confirmed = new RouteRemovalCapture(map, id);
    confirmed.onSelect(menu.getItem(3));
    Test.assert(confirmed.closed && confirmed.removed);
    Test.assert(map.routeStore.route(id) == null);
    Test.assert(map.routeStore.point(target) == null);
    Test.assert(!map.pointLocations.hasKey(target));
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.routeStore.point(otherTarget) != null);
    Test.assertEqual(relay.sentKind, "");
    Test.assert(buildRouteMenu(map, id) == null);
    var stale = new RouteRemovalCapture(map, id);
    stale.onSelect(menu.getItem(3));
    Test.assert(!stale.closed);
    Test.assert(map.unavailable);
    Test.assertEqual(map.routeStore.routes.size(), 1);
    // This removes the current watch copy, not the companion's source route.
    map.receiveRoute("route", RouteFixtures.payload("one", "shared", 2));
    Test.assert(map.routeStore.route(id) != null);
    Test.assert(!map.isBloodhoundActive());
    return true;
}

(:test)
function routeLocalRemovalPreservesOtherTargetsAndRejectsStaleActions(logger) as Boolean {
    var map = new RouteSelectionCapture();
    map.receiveRoute("route", RouteFixtures.payload("one", "shared", 2));
    map.receiveRoute("route", RouteFixtures.payload("two", "shared", 2));
    var first = map.routeStore.find("one", "shared");
    var second = map.routeStore.find("two", "shared");
    var id = map.routeStore.routeId(first);
    var target = map.routeStore.pointId(second, 0);
    map.toggleRouteBloodhound(target);
    var staleMenu = buildRouteMenu(map, id);
    Test.assert(map.removeLocalRoute(id));
    Test.assert(map.isBloodhoundTarget(target));
    new RouteMenuDelegate(map, id).onSelect(staleMenu.getItem(0));
    Test.assert(map.unavailable);
    Test.assert(map.openedRoute == null);
    map.updateIncomingCot("ordinary", 0.0, 0.0, "a-f-G", "Ordinary", null, null, {});
    map.setBloodhoundPoint("cot-ordinary");
    Test.assert(map.removeLocalRoute(map.routeStore.routeId(second)));
    Test.assert(map.isBloodhoundTarget("cot-ordinary"));
    Test.assert(!map.routeStore.routeId({"serverId" => "a", "uid" => "bc"})
        .equals(map.routeStore.routeId({"serverId" => "ab", "uid" => "c"})));
    return true;
}
