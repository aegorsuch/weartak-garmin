import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function pickerCameraRequiresExactTypeOrVideoDetail(logger) as Boolean {
    Test.assert(isIncomingCamera("b-i-v", {}));
    Test.assert(isIncomingCamera("a-f-A-M-F-Q", {"__video" => {}}));
    var notCameras = ["b-i-v-other", "b-i-video", "b-m-p-s-p-i", "a-f-G-E-S",
        "a-f-A-M-F-Q", "a-f-G-U-C"];
    for (var i = 0; i < notCameras.size(); i++) {
        Test.assert(!isIncomingCamera(notCameras[i], {"callSign" => "Video Camera", "sensor" => {}}));
        Test.assert(!isIncomingCamera(notCameras[i], {"__video" => true}));
        Test.assert(!isIncomingCamera(notCameras[i], {"__video" => "rtsp://ignored"}));
    }
    var map = new PickerMapCapture();
    map.currentPosition = RouteNavigation.location({"lat" => 0.0, "lon" => 0.0});
    map.updateIncomingCot("camera", 0.0, 0.01, "b-i-v", "Camera 1", null, null, {"isPoint" => true});
    Test.assertEqual(pickerTargetKind(map, "cot-camera"), :camera);
    var row = createMenu("Picker");
    addPickerTarget(row, map, "cot-camera");
    Test.assertEqual(row.getItem(0).getLabel(), "Camera 1");
    Test.assertEqual((row.getItem(0).getIcon() as PickerTypeGlyph).kind, :camera);
    Test.assertEqual((row.getItem(0).getIcon() as PickerTypeGlyph).width, 24);
    var subtitle = row.getItem(0).getSubLabel();
    Test.assertEqual(buildPickerTargetActions(map, "cot-camera").getItem(0).getId(), :showOnMap);
    Test.assert(applyPickerTargetAction(map, "cot-camera", :track));
    Test.assert(pickerTargetActive(map, "cot-camera"));
    Test.assertEqual(pickerTargetSubtitle(map, "cot-camera"), subtitle);
    map.updateIncomingCot("camera", 0.0, 0.01, "a-f-G", "Camera 1", null, null, {"isPoint" => true});
    Test.assertEqual(pickerTargetKind(map, "cot-camera"), :point);
    map.updateIncomingCot("camera", 0.0, 0.01, "a-f-G", "Camera 1", null, null,
        {"isPoint" => true, "__video" => {}});
    Test.assertEqual(pickerTargetKind(map, "cot-camera"), :camera);
    Test.assert(!map.incomingDetails.get("cot-camera").hasKey("__video"));
    var relay = new TestPointRelay();
    relay.incomingCotCallback = map.method(:updateIncomingCot);
    relay.forwardEntity({"uid" => "wire-video", "type" => "a-f-A-M-F-Q",
        "lat" => 0.0, "lon" => 0.01, "__video" => {}});
    Test.assertEqual(pickerTargetKind(map, "cot-wire-video"), :camera);
    relay.forwardEntity({"uid" => "wire-alias", "type" => "b-i-v",
        "lat" => 0.0, "lon" => 0.01, "isPoint" => true});
    Test.assertEqual(pickerTargetKind(map, "cot-wire-alias"), :camera);
    relay.forwardEntity({"uid" => "nested-only", "type" => "a-f-G",
        "lat" => 0.0, "lon" => 0.01, "isPoint" => true, "detail" => {"__video" => {}}});
    Test.assertEqual(pickerTargetKind(map, "cot-nested-only"), :point);
    map.updateIncomingCot("alert-video", 0.0, 0.02, "b-a-o", "Alert", null, null, {"__video" => {}});
    Test.assertEqual(pickerTargetKind(map, "cot-alert-video"), :alert);
    return true;
}

(:test)
class PickerMapCapture extends TestMapSelectionView {
    var areaApplied = 0;
    function initialize() { TestMapSelectionView.initialize(); areaApplied = 0; }
    function applyMapVisibleArea() as Void { areaApplied++; }
}

(:test)
function pickerMapActionFitsWholeRouteWithoutStarting(logger) as Boolean {
    var map = new PickerMapCapture();
    var payload = RouteFixtures.payload("s", "r", 3);
    var points = payload.get("points") as Array;
    points[0].put("lat", 1.0); points[0].put("lon", 179.5);
    points[1].put("lat", 2.0); points[1].put("lon", -179.5);
    points[2].put("lat", -1.0); points[2].put("lon", 179.8);
    map.receiveRoute("route", payload);
    var id = map.routeStore.routeId(map.routeStore.routes[0]);
    map.routesVisible = false;
    Test.assert(applyPickerTargetAction(map, id, :showOnMap));
    Test.assertEqual(map.areaApplied, 1);
    Test.assert(map.routesVisible && map.hasInitialPosition);
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.followingRouteId == null && map.currentPosition == null);
    var left = map.mapTopLeft.toDegrees();
    var right = map.mapBottomRight.toDegrees();
    Test.assert(left[0] > 2 && right[0] < -1);
    Test.assert(left[1] > 179 && right[1] < -179);
    for (var i = 0; i < points.size(); i++) {
        var screen = map.routeScreenPoint(points[i]);
        Test.assert(screen[0] > 0 && screen[0] < map.screenWidth);
        Test.assert(screen[1] > 0 && screen[1] < map.screenHeight);
    }
    return true;
}

(:test)
function pickerMapFocusPreservesExistingTargetAndClampsPoles(logger) as Boolean {
    var map = new PickerMapCapture();
    map.pointLocations.put("first", RouteNavigation.location({"lat" => 0.0, "lon" => 0.0}));
    map.pointLocations.put("pole", RouteNavigation.location({"lat" => 90.0, "lon" => 180.0}));
    map.setBloodhoundPoint("first");
    Test.assert(applyPickerTargetAction(map, "pole", :showOnMap));
    Test.assert(map.isBloodhoundTarget("first"));
    Test.assert(map.mapTopLeft.toDegrees()[0] <= 90);
    Test.assert(map.mapBottomRight.toDegrees()[0] < 90);
    Test.assertEqual(map.areaApplied, 1);
    Test.assert(!applyPickerTargetAction(map, "missing", :showOnMap));
    Test.assertEqual(map.areaApplied, 1);
    Test.assert(map.isBloodhoundTarget("first"));
    return true;
}

(:test)
function pickerPointHoundStartsImmediatelyAndStopsRoute(logger) as Boolean {
    var map = new PickerMapCapture();
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var routeId = map.routeStore.routeId(map.routeStore.routes[0]);
    Test.assert(map.startRoute(routeId, false));
    var vertex = map.bloodhoundPointId;
    map.pointLocations.put("marker", RouteNavigation.location({"lat" => 0.0, "lon" => 1.0}));
    Test.assert(applyPickerTargetAction(map, "marker", :track));
    Test.assert(map.isBloodhoundTarget("marker"));
    Test.assert(map.followingRouteId == null);
    Test.assert(!map.pointLocations.hasKey(vertex));
    Test.assertEqual(map.areaApplied, 0);
    Test.assert(applyPickerTargetAction(map, "marker", :track));
    Test.assert(!map.isBloodhoundActive());
    map.updateIncomingCot("contact", 1.0, 1.0, "a-f-G-U-C", "Contact", null, null, {});
    Test.assert(applyPickerTargetAction(map, "cot-contact", :track));
    Test.assert(map.isBloodhoundTarget("cot-contact"));
    Test.assert(!applyPickerTargetAction(map, routeId, :track));
    Test.assert(map.isBloodhoundTarget("cot-contact"));
    Test.assert(!map.startRoute(routeId, true));
    Test.assert(map.isBloodhoundTarget("cot-contact"));
    return true;
}

(:test)
function pickerActiveRouteSubtitleAndStopIcon(logger) as Boolean {
    var map = new PickerMapCapture();
    map.receiveRoute("route", RouteFixtures.payload("s", "r", 3));
    var route = map.routeStore.routes[0];
    var id = map.routeStore.routeId(route);
    Test.assert(map.startRoute(id, false));
    map.currentPosition = RouteNavigation.location({"lat" => 0.0, "lon" => -0.01});
    var row = createMenu("Picker");
    addPickerTarget(row, map, id);
    Test.assertEqual(row.getItem(0).getLabel(), "Test route");
    Test.assertEqual(row.getItem(0).getSubLabel(), "Point 1 of 3 \u00b7 23.4 km left");
    var glyph = row.getItem(0).getIcon() as PickerTypeGlyph;
    Test.assert(glyph.active && glyph.kind == :route);
    var menu = buildPickerTargetActions(map, id);
    Test.assertEqual(menu.getItem(0).getId(), :showOnMap);
    Test.assertEqual(menu.getItem(1).getLabel(), WatchUi.loadResource(Rez.Strings.TextStopBloodhound));
    Test.assertEqual(menu.getItem(1).getIcon().getWidth(), 24);
    Test.assertEqual(menu.getItem(2).getId(), :details);
    Test.assertEqual(menu.getItem(3).getId(), :remove);
    Test.assertEqual((menu.getItem(3).getIcon() as PickerDeleteGlyph).width, 24);
    Test.assert(applyPickerTargetAction(map, id, :track));
    Test.assert(!map.isBloodhoundActive());
    Test.assert(map.followingRouteId == null);
    Test.assert(!pickerTargetActive(map, id));
    return true;
}

(:test)
function pickerDeleteAndRemoveAllIncludeRoutes(logger) as Boolean {
    var map = new PickerMapCapture();
    map.receiveRoute("route", RouteFixtures.payload("one", "r", 3));
    map.receiveRoute("route", RouteFixtures.payload("two", "r", 3));
    var route = map.routeStore.routes[0];
    Test.assert(map.startRoute(map.routeStore.routeId(route), false));
    map.updateIncomingCot("delete", 0.0, 0.0, "a-n-G", "Delete", null, null, {"isPoint" => true});
    Test.assert(applyPickerTargetAction(map, "cot-delete", :remove));
    Test.assert(!map.incomingDetails.hasKey("cot-delete"));
    Test.assert(map.isBloodhoundActive());
    map.updateIncomingCot("all", 0.0, 0.0, "a-n-G", "All", null, null, {"isPoint" => true});
    map.updateIncomingCot("contact", 0.0, 0.0, "a-f-G-U-C", "Contact", null, null, {});
    map.removeAllIncomingPoints();
    Test.assertEqual(map.routeStore.routes.size(), 0);
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.incomingDetails.hasKey("cot-all"));
    Test.assert(map.incomingDetails.hasKey("cot-contact"));
    Test.assert(!applyPickerTargetAction(map, "cot-delete", :remove));
    map.removeIncomingPoint("cot-contact", false);
    map.receiveRoute("route", RouteFixtures.payload("only", "route", 2));
    map.removeAllIncomingPoints();
    Test.assertEqual(map.routeStore.routes.size(), 0);
    return true;
}

(:test)
function mainMenuHidesActiveBloodhoundAndRestoresEntry(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var map = app.getMapView();
    map.setBloodhoundPoint(null);
    var menu = new MainMenu(app);
    menu.onShow();
    Test.assertEqual(menu.getItem(0).getId(), :incomingPoints);
    map.pointLocations.put("menu-active", RouteNavigation.location({"lat" => 1.0, "lon" => 1.0}));
    map.setBloodhoundPoint("menu-active");
    for (var i = 0; menu.getItem(i) != null; i++) {
        Test.assert(menu.getItem(i).getId() != :incomingPoints);
    }
    Test.assertEqual(menu.getItem(0).getId(), :chat);
    map.setBloodhoundPoint(null);
    Test.assertEqual(menu.getItem(0).getId(), :incomingPoints);
    map.updateIncomingCot("menu-delete", 1.0, 1.0, "a-n-G", "Delete", null, null, {"isPoint" => true});
    map.setBloodhoundPoint("cot-menu-delete");
    Test.assertEqual(menu.getItem(0).getId(), :chat);
    map.removeIncomingPoint("cot-menu-delete", true);
    Test.assertEqual(menu.getItem(0).getId(), :incomingPoints);
    menu.onHide();
    map.pointLocations.remove("menu-active");
    return true;
}

(:test)
function pickerTargetTypesAndScaledAssets(logger) as Boolean {
    var map = new PickerMapCapture();
    map.pointLocations.put("local", RouteNavigation.location({"lat" => 0.0, "lon" => 0.0}));
    map.pointDetails.put("local", {"title" => "Rally Point", "type" => :friendly});
    map.updateIncomingCot("point", 0.0, 0.0, "a-n-G", "CP-2", null, null, {"isPoint" => true});
    map.updateIncomingCot("contact", 0.0, 0.0, "a-f-G-U-C", "ODIN-ALPHA", null, null, {});
    Test.assertEqual(pickerTargetKind(map, "local"), :marker);
    Test.assertEqual(pickerTargetKind(map, "cot-point"), :point);
    Test.assertEqual(pickerTargetKind(map, "cot-contact"), :contact);
    Test.assertEqual(pickerTargetTitle(map, "local"), "Rally Point");
    Test.assertEqual(pickerTargetSubtitle(map, "local"), "Marker");
    map.currentPosition = map.pointLocations.get("local");
    Test.assertEqual(pickerTargetSubtitle(map, "cot-contact"), "Contact \u00b7 0 m");
    Test.assertEqual(pickerTargetSubtitle(map, "cot-point"), "Point \u00b7 0 m");
    var icons = [Rez.Drawables.PickerHoundIcon, Rez.Drawables.PickerCrosshairIcon,
        Rez.Drawables.PickerStopIcon, Rez.Drawables.PickerHoundUnavailableIcon];
    for (var i = 0; i < icons.size(); i++) {
        var bitmap = WatchUi.loadResource(icons[i]);
        Test.assertEqual(bitmap.getWidth(), 24); Test.assertEqual(bitmap.getHeight(), 24);
    }
    return true;
}

(:test)
function pickerUnavailableLocationAndStaleActionNeverRetarget(logger) as Boolean {
    var map = new PickerMapCapture();
    map.pointLocations.put("current", RouteNavigation.location({"lat" => 0.0, "lon" => 0.0}));
    map.setBloodhoundPoint("current");
    map.incomingDetails.put("no-fix", {"uid" => "no-fix", "callSign" => "No fix", "isPoint" => true});
    var menu = buildPickerTargetActions(map, "no-fix");
    Test.assertEqual(menu.getItem(0).getSubLabel(), WatchUi.loadResource(Rez.Strings.TextLocationUnavailable));
    Test.assert(!applyPickerTargetAction(map, "no-fix", :showOnMap));
    Test.assert(!applyPickerTargetAction(map, "no-fix", :track));
    Test.assert(!applyPickerTargetAction(map, "missing", :track));
    Test.assert(map.isBloodhoundTarget("current"));
    Test.assertEqual(map.areaApplied, 0);
    return true;
}
