import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function routeNavigationNearestAndMissingPosition(logger) as Boolean {
    var points = RouteFixtures.payload("s", "r", 4).get("points") as Array;
    Test.assert(RouteNavigation.nearest(points, null) == null);
    Test.assert(RouteNavigation.nearest([], RouteNavigation.location(points[0])) == null);
    Test.assertEqual(RouteNavigation.nearest(points, RouteNavigation.location({"lat" => 0.0, "lon" => 0.19})), 2);
    points[3] = points[1];
    Test.assertEqual(RouteNavigation.nearest(points, RouteNavigation.location(points[3])), 1);
    return true;
}

(:test)
function routeNavigationArrivalRadiusDenseAndEnd(logger) as Boolean {
    Test.assertEqual(RouteNavigation.arrivalRadius("Walking"), 10);
    Test.assertEqual(RouteNavigation.arrivalRadius("Swimming"), 10);
    Test.assertEqual(RouteNavigation.arrivalRadius("Driving"), 20);
    Test.assertEqual(RouteNavigation.arrivalRadius("Watercraft"), 100);
    Test.assertEqual(RouteNavigation.arrivalRadius("Flying"), 1000);
    Test.assertEqual(RouteNavigation.arrivalRadius(null), 10);
    var points = [{"lat" => 0.0, "lon" => 0.0, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => 0.000045, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => 0.000081, "type" => "b-m-p-w"}, {"lat" => 0.0, "lon" => 0.00072}];
    var position = RouteNavigation.location(points[0]);
    var reached = [];
    Test.assertEqual(RouteNavigation.advance(points, 0, null, "Walking", reached), 0);
    Test.assertEqual(RouteNavigation.advance(points, 0, position, "Walking", reached), 1);
    position = RouteNavigation.location({"lat" => 0.0, "lon" => 0.00009});
    Test.assertEqual(RouteNavigation.advance(points, 1, position, "Walking", reached), 3);
    Test.assertEqual(RouteNavigation.advance(points, 3, RouteNavigation.location(points[3]), "Walking", reached), 4);
    Test.assertEqual(RouteNavigation.advance(points, 4, position, "Walking", reached), 4);
    return true;
}

(:test)
function routeCheckpointsRequireArrivalThenProjectedCrossing(logger) as Boolean {
    var points = [{"lat" => 0.0, "lon" => 0.0}, {"lat" => 0.0, "lon" => 0.0009, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => 0.00135, "type" => "b-m-p-c"}, {"lat" => 0.0, "lon" => 0.0027}];
    Test.assertEqual(RouteNavigation.nextObjective(points, 0), 1);
    var before = RouteNavigation.location({"lat" => 0.0, "lon" => 0.000855});
    var after = RouteNavigation.location({"lat" => 0.0, "lon" => 0.000909});
    var missed = RouteNavigation.location({"lat" => 0.0, "lon" => 0.00117});
    var reached = [];
    Test.assertEqual(RouteNavigation.advance(points, 1, missed, "Walking", reached), 1);
    Test.assertEqual(reached.size(), 0);
    Test.assertEqual(RouteNavigation.advance(points, 1, before, "Walking", reached), 1);
    Test.assertEqual(reached.size(), 1);
    Test.assertEqual(RouteNavigation.advance(points, 1, after, "Walking", reached), 3);
    Test.assertEqual(RouteNavigation.advance(points, 1, RouteNavigation.location(points[3]), "Walking", []), 4);
    (points[1] as Dictionary).remove("type");
    Test.assertEqual(RouteNavigation.nextObjective(points, 0), 3);
    Test.assertEqual(RouteNavigation.nearestObjective(points, before), 3);
    return true;
}

(:test)
function routeNearestUsesSegmentProjectionAndEarliestLoop(logger) as Boolean {
    var points = [{"lat" => 0.0, "lon" => 0.0, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => 0.001, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => 0.0, "type" => "b-m-p-w"}];
    Test.assertEqual(RouteNavigation.nearestObjective(points, RouteNavigation.location({"lat" => 0.0, "lon" => 0.0004})), 1);
    Test.assert(RouteNavigation.nearestObjective(points, null) == null);
    points = [{"lat" => 0.0, "lon" => 179.99}, {"lat" => 0.0, "lon" => -179.99, "type" => "b-m-p-w"},
        {"lat" => 0.0, "lon" => -179.98}];
    Test.assertEqual(RouteNavigation.nearestObjective(points, RouteNavigation.location({"lat" => 0.0, "lon" => 180.0})), 1);
    Test.assertEqual(RouteNavigation.nearestObjective(points, RouteNavigation.location(points[2])), 2);
    points = [{"lat" => 0.0, "lon" => 0.0}, {"lat" => 0.0, "lon" => 0.0},
        {"lat" => 0.0, "lon" => 0.0, "type" => "b-m-p-w"}];
    Test.assertEqual(RouteNavigation.advance(points, 2, RouteNavigation.location(points[0]), null, []), 3);
    return true;
}

(:test)
function routeFinalMethodRadiusThresholds(logger) as Boolean {
    var points = [{"lat" => 0.0, "lon" => -1.0}, {"lat" => 0.0, "lon" => 0.0}];
    var methods = ["Walking", "Swimming", "Driving", "Watercraft", "Flying"];
    for (var i = 0; i < methods.size(); i++) {
        var radius = RouteNavigation.arrivalRadius(methods[i]);
        var inside = RouteNavigation.location({"lat" => 0.0, "lon" => (radius - 0.1) / 111194.9266});
        var outside = RouteNavigation.location({"lat" => 0.0, "lon" => (radius + 0.1) / 111194.9266});
        Test.assertEqual(RouteNavigation.advance(points, 1, outside, methods[i], []), 1);
        Test.assertEqual(RouteNavigation.advance(points, 1, inside, methods[i], []), 2);
    }
    return true;
}

(:test)
function routePoorOrMissingGpsNeverConsumesCheckpoint(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.hasInitialPosition = true;
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var route = map.routeStore.routes[0];
    Test.assert(map.startRoute(map.routeStore.routeId(route), false));
    var fix = new RouteGpsFix(RouteNavigation.location((route.get("points") as Array)[0]));
    fix.accuracy = Position.QUALITY_POOR;
    map.updatePosition(fix);
    Test.assertEqual(map.followingRouteIndex, 0);
    Test.assertEqual(map.reachedRoutePoints.size(), 0);
    fix.accuracy = Position.QUALITY_USABLE;
    map.updatePosition(fix);
    Test.assertEqual(map.followingRouteIndex, 1);
    map.updatePosition(new RouteGpsFix(null));
    Test.assert(!map.routePositionUsable);
    map.stopRoute();
    return true;
}

(:test)
function routeNavigationRemainingIncludesApproachAndOriginalVertices(logger) as Boolean {
    var points = [{"lat" => 0.0, "lon" => 0.0}, {"lat" => 0.1, "lon" => 0.0},
        {"lat" => 0.1, "lon" => 0.1}];
    var position = RouteNavigation.location({"lat" => 0.0, "lon" => -0.1});
    var remaining = RouteNavigation.remaining(points, 0, position);
    Test.assert(remaining > 33300 && remaining < 33400);
    Test.assert(RouteNavigation.remaining(points, 0, null) > 22200);
    Test.assert(RouteNavigation.remaining(points, 1, position) < remaining);
    Test.assertEqual(RouteNavigation.remaining(points, 3, position), 0.0);
    var dateline = [{"lat" => 0.0, "lon" => 179.9}, {"lat" => 0.0, "lon" => -179.9}];
    var meters = RouteNavigation.remaining(dateline, 0, null);
    Test.assert(meters > 22200 && meters < 22300);
    Test.assert(RouteNavigation.distance(RouteNavigation.location({"lat" => 90.0, "lon" => 0.0}),
        RouteNavigation.location({"lat" => -90.0, "lon" => 180.0})) > 20000000);
    return true;
}

(:test)
function wholeRouteStartModesAndUnavailableNearest(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 4));
    var route = map.routeStore.routes[0];
    var id = map.routeStore.routeId(route);
    Test.assert(!map.startRoute(id, true));
    Test.assert(!map.isBloodhoundActive());
    var menu = new RouteFollowMenu(map, id);
    Test.assertEqual(menu.getItem(0).getId(), :noLocation);
    Test.assertEqual(menu.getItem(0).getSubLabel(), WatchUi.loadResource(Rez.Strings.RouteNeedsLocation));
    Test.assertEqual(menu.getItem(1).getId(), :beginning);
    Test.assert(map.startRoute(id, false));
    Test.assertEqual(map.followingRouteIndex, 0);
    Test.assertEqual(map.routeProgress(), "Point 1 of 4");
    Test.assertEqual(map.routeRemainingLabel(), WatchUi.loadResource(Rez.Strings.RouteNeedsLocation));
    Test.assert(map.isBloodhoundTarget(map.routeStore.pointId(route, 0)));
    map.currentPosition = RouteNavigation.location({"lat" => 0.0, "lon" => 0.19});
    Test.assert(map.startRoute(id, true));
    Test.assertEqual(map.followingRouteIndex, 2);
    Test.assert(map.isBloodhoundTarget(map.routeStore.pointId(route, 2)));
    Test.assertEqual(map.getBloodhoundTitle(), "Test route");
    Test.assert(map.bloodhoundRelayTarget() == null);
    menu = new RouteFollowMenu(map, id);
    Test.assertEqual(menu.getItem(0).getLabel(), "Point 3 of 4");
    Test.assertEqual(menu.getItem(1).getId(), :stopRoute);
    new RouteFollowDelegate(map, id).onSelect(new WatchUi.MenuItem("", null, :noLocation, null));
    Test.assertEqual(map.followingRouteIndex, 2);
    map.stopRoute();
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.followingRouteId == null);
    return true;
}

(:test)
function wholeRouteAdvancesDenseVerticesAndCompletes(logger) as Boolean {
    var map = new TestMapSelectionView();
    var payload = RouteFixtures.payload("s", "r", 4);
    var points = payload.get("points") as Array;
    points[1].put("lon", 0.00001);
    points[2].put("lon", 0.00002);
    points[3].put("lon", 0.001);
    map.receiveRoute("route", payload);
    var route = map.routeStore.routes[0];
    var id = map.routeStore.routeId(route);
    Test.assert(map.startRoute(id, false));
    var first = map.bloodhoundPointId;
    map.currentPosition = RouteNavigation.location(points[0]);
    map.updateRouteFollow();
    Test.assertEqual(map.followingRouteIndex, 1);
    Test.assertEqual(map.routeProgress(), "Point 2 of 4");
    Test.assert(map.routeRemainingLabel().find("111") == 0);
    Test.assert(!map.pointLocations.hasKey(first));
    Test.assertEqual(map.pointLocations.size(), 1);
    var last = map.bloodhoundPointId;
    map.currentPosition = RouteNavigation.location(points[3]);
    map.updateRouteFollow();
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.pointLocations.hasKey(last));
    map.updateRouteFollow();
    Test.assert(!map.isBloodhoundActive());
    return true;
}

(:test)
function wholeRouteReplacedByOtherTargetsAndSinglePoint(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 3));
    map.receiveRoute("route", RouteFixtures.payload("two", "r", 3));
    var first = map.routeStore.routes[0];
    var second = map.routeStore.routes[1];
    Test.assert(map.startRoute(map.routeStore.routeId(first), false));
    var old = map.bloodhoundPointId;
    Test.assert(map.startRoute(map.routeStore.routeId(second), false));
    Test.assert(!map.pointLocations.hasKey(old));
    var point = map.routeStore.pointId(first, 2);
    map.toggleRouteBloodhound(point);
    Test.assert(map.followingRouteId == null);
    Test.assert(map.isBloodhoundTarget(point));
    map.currentPosition = RouteNavigation.location((first.get("points") as Array)[2]);
    map.updateRouteFollow();
    Test.assert(map.isBloodhoundTarget(point));
    map.toggleRouteBloodhound(point);
    Test.assert(!map.isBloodhoundActive());
    map.currentPosition = null;
    Test.assert(map.startRoute(map.routeStore.routeId(first), false));
    old = map.bloodhoundPointId;
    map.updateIncomingCot("ordinary", 1.0, 1.0, "a-f-G", "Other", null, null, {});
    map.toggleBloodhound("cot-ordinary");
    Test.assert(map.followingRouteId == null);
    Test.assert(map.isBloodhoundTarget("cot-ordinary"));
    Test.assert(!map.pointLocations.hasKey(old));
    return true;
}

(:test)
function wholeRouteRemovalResetAndUpdate(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 4));
    map.receiveRoute("route", RouteFixtures.payload("two", "r", 4));
    var first = map.routeStore.routes[0];
    var id = map.routeStore.routeId(first);
    Test.assert(map.startRoute(id, false));
    Test.assert(map.removeLocalRoute(map.routeStore.routeId(map.routeStore.routes[1])));
    Test.assertEqual(map.followingRouteId, id);
    Test.assert(map.removeLocalRoute(id));
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.startRoute(id, false));
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 4));
    map.currentPosition = RouteNavigation.location({"lat" => 0.0, "lon" => 0.29});
    Test.assert(map.startRoute(id, true));
    Test.assertEqual(map.followingRouteIndex, 3);
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 2));
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.followingRouteId == null);
    Test.assert(map.startRoute(id, false));
    var old = map.bloodhoundPointId;
    map.receiveRoute("routes_reset", {"routeVersion" => 1});
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.pointLocations.hasKey(old));
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 2));
    Test.assert(map.startRoute(id, false));
    map.receiveRoute("route_remove", {"routeVersion" => 1, "serverId" => "one", "uid" => "r"});
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.isBloodhoundActive());
    return true;
}

(:test)
function wholeRouteBloodhoundPickerHasOneRowPerRoute(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 4));
    map.receiveRoute("route", RouteFixtures.payload("two", "r", 2));
    var menu = createMenu("Bloodhound");
    Test.assertEqual(addBloodhoundRoutes(menu, map), 2);
    Test.assertEqual(menu.getItem(0).getLabel(), "Test route");
    Test.assertEqual(menu.getItem(0).getSubLabel(), "Route \u00b7 4 points");
    Test.assert(menu.getItem(2) == null);
    Test.assert(!menu.getItem(0).getId().equals(menu.getItem(1).getId()));
    map.currentPosition = RouteNavigation.location({"lat" => 0.0, "lon" => 0.19});
    menu = createMenu("Bloodhound");
    addBloodhoundRoutes(menu, map);
    Test.assert(menu.getItem(0).getSubLabel().find("Route \u00b7 4 points \u00b7 1.1 km") == 0);
    Test.assertEqual(menu.getItem(0).getId(), map.routeStore.routeId(map.routeStore.routes[0]));
    return true;
}

(:test)
function wholeRouteLocalOnlyAcrossAdvanceAndStop(logger) as Boolean {
    var map = new TestMapSelectionView();
    var harness = new BloodhoundSyncHarness();
    harness.sync.activeTargetCallback = map.method(:bloodhoundRelayTarget);
    harness.sync.connectionChanged(true);
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var route = map.routeStore.routes[0];
    Test.assert(map.startRoute(map.routeStore.routeId(route), false));
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.sent.size(), 0);
    map.currentPosition = RouteNavigation.location((route.get("points") as Array)[0]);
    map.updateRouteFollow();
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.sent.size(), 0);
    map.stopRoute();
    harness.sync.localTargetChanged();
    Test.assertEqual(harness.sent.size(), 0);
    return true;
}

(:test)
class RouteGpsFix {
    var position;
    var accuracy = Position.QUALITY_USABLE;
    function initialize(location) { position = location; }
}

(:test)
function wholeRouteGpsUpdatesDriveArrivalAndPhoneTargetCancels(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.hasInitialPosition = true;
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var route = map.routeStore.routes[0];
    var id = map.routeStore.routeId(route);
    Test.assert(map.startRoute(id, false));
    map.updatePosition(new RouteGpsFix(null));
    Test.assertEqual(map.followingRouteIndex, 0);
    map.updatePosition(new RouteGpsFix(RouteNavigation.location((route.get("points") as Array)[0])));
    Test.assertEqual(map.followingRouteIndex, 1);
    var old = map.bloodhoundPointId;
    var invalid = RouteFixtures.payload("s", "r", 3);
    (invalid.get("points") as Array)[1].put("lat", 91);
    map.receiveRoute("route", invalid);
    Test.assertEqual(map.followingRouteId, id);
    Test.assert(map.isBloodhoundTarget(old));
    map.updateIncomingCot("phone-point", 1.0, 1.0, "a-f-G", "Phone target", null, null, {});
    Test.assert(map.startBloodhoundFromPhone({"uid" => "phone-point"}));
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.pointLocations.hasKey(old));
    Test.assert(map.isBloodhoundTarget("cot-phone-point"));
    return true;
}

(:test)
function wholeRouteIncomingPickerIntegrationAndEmptyState(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var map = app.getMapView();
    var previous = map.routeStore;
    map.routeStore = new RouteStore();
    var payload = RouteFixtures.payload("picker", "whole", 5);
    Test.assert(map.routeStore.receive("route", payload));
    var id = map.routeStore.routeId(map.routeStore.routes[0]);
    var menu = buildIncomingPointsMenu(app);
    var routes = 0;
    for (var i = 0; menu.getItem(i) != null; i++) {
        var item = menu.getItem(i);
        Test.assert(item.getId() != :empty);
        if (id.equals(item.getId())) {
            routes++;
            Test.assertEqual(item.getLabel(), "Test route");
            Test.assert(item.getSubLabel().find("Route \u00b7 5 points") == 0);
        }
    }
    map.routeStore = previous;
    Test.assertEqual(routes, 1);
    return true;
}

(:test)
function wholeRouteChooserRefreshesOnGpsProgressAndRemoval(logger) as Boolean {
    var map = new TestMapSelectionView();
    map.hasInitialPosition = true;
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var route = map.routeStore.routes[0];
    var id = map.routeStore.routeId(route);
    var menu = new RouteFollowMenu(map, id);
    menu.onShow();
    Test.assertEqual(menu.getItem(0).getId(), :noLocation);
    map.updatePosition(new RouteGpsFix(RouteNavigation.location({"lat" => 0.0, "lon" => -0.01})));
    Test.assertEqual(menu.getItem(0).getId(), :nearest);
    Test.assert(map.startRoute(id, false));
    Test.assertEqual(menu.getItem(0).getId(), :progress);
    Test.assertEqual(menu.getItem(0).getLabel(), "Point 1 of 3");
    map.updatePosition(new RouteGpsFix(RouteNavigation.location((route.get("points") as Array)[0])));
    Test.assertEqual(menu.getItem(0).getLabel(), "Point 2 of 3");
    Test.assertEqual(menu.getItem(1).getId(), :stopRoute);
    map.receiveRoute("route_remove", {"routeVersion" => 1, "serverId" => "s", "uid" => "r"});
    Test.assertEqual(menu.getItem(0).getId(), :empty);
    Test.assert(!map.isBloodhoundActive());
    menu.onHide();
    Test.assert(map.routeFollowMenu == null);
    return true;
}
