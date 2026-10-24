import Toybox.Application;
import Toybox.Graphics;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class StandaloneMapView extends WatchUi.MapView {
    var screenWidth;
    var screenHeight;
    var mapTopLeft;
    var mapBottomRight;
    var markers = {};
    var pointLocations = {};
    var pointDetails = {};
    var pointOrder as Array<String> = [];
    var defaultPointType as Symbol = :unknown;
    var incomingIds = [];
    var incomingLastSeen = {};
    var incomingDetails = {};
    var pendingIncomingPoints as Array<String> = [];
    var dismissedIncomingPoints = {};
    var alertSourceStates = {};
    var userSourceStates = {};
    var phoneUserExcludedUids = [];
    var phoneUserIdentityReady as Boolean = false;
    var phoneUserSyncRequested as Boolean = false;
    var alertOrdering = {};
    var hiddenMapTeams as Array<String> = [];
    var hiddenMapRoles as Array<String> = [];
    var mapButtonsVisible as Boolean = true;
    var nextPointNumber = 1;
    var takClient as TakClient? = null;
    var controlSize = 40;
    var controlGap = 6;
    var controlMargin = 8;
    var hasInitialPosition = false;
    var currentPosition = null;
    var bloodhoundPointId = null;
    var application;
    var bloodhoundProximityNotified = false;
    var entityPruneTimer;
    var mapAreaDirty = true;
    var markersDirty = true;
    var drawnPointIds as Array<String> = [];
    var routeStore as RouteStore = new RouteStore();
    var routesVisible as Boolean = true;
    var followingRouteId as String? = null;
    var followingRouteIndex as Number = 0;
    var followingRoutePhoneOwned as Boolean = false;
    var applyingPhoneRoute as Boolean = false;
    var reachedRoutePoints as Array<Number> = [];
    var routePositionUsable as Boolean = false;
    var routeFollowMenu as RouteFollowMenu? = null;
    var pendingSelfPoints as Array<Dictionary> = [];

    function startRoute(id as String, nearest as Boolean) as Boolean {
        if (application != null) { application.requestPositionForAction("navigation"); }
        var route = routeStore.route(id);
        if (route == null) { routeUnavailable(); return false; }
        var points = route.get("points") as Array;
        var index = nearest ? RouteNavigation.nearestObjective(points, currentPosition) : RouteNavigation.nextObjective(points, 0);
        if (index == null) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.RouteNeedsLocation), null);
            return false;
        }
        setBloodhoundPoint(null);
        notifyBloodhoundChanged();
        followingRouteId = id;
        followingRouteIndex = index;
        followingRoutePhoneOwned = takClient != null && takClient.routeNavigationSync.connected;
        if (followingRoutePhoneOwned && !takClient.routeNavigationSync.startLocal(route, index)) {
            setBloodhoundPoint(null);
            return false;
        }
        updateRouteFollow();
        refreshBloodhoundPicker();
        if (application != null) { application.refreshIncomingPointCount(); }
        notifyBloodhoundChanged();
        WatchUi.requestUpdate();
        return true;
    }

    function stopRoute() as Void {
        if (followingRouteId == null) { return; }
        setBloodhoundPoint(null);
        notifyBloodhoundChanged();
    }

    function updateRouteFollow() as Void {
        if (followingRouteId == null) { return; }
        var route = routeStore.route(followingRouteId);
        if (route == null || followingRouteIndex >= (route.get("points") as Array).size()) {
            stopRoute();
            return;
        }
        var points = route.get("points") as Array;
        if (!followingRoutePhoneOwned) {
            followingRouteIndex = RouteNavigation.advance(points, followingRouteIndex,
                routePositionUsable ? currentPosition : null, route.get("method"), reachedRoutePoints);
        }
        if (followingRouteIndex == points.size()) {
            stopRoute();
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.RouteComplete), null);
            return;
        }
        var id = routeStore.pointId(route, followingRouteIndex);
        if (bloodhoundPointId != null && !id.equals(bloodhoundPointId)) {
            pointLocations.remove(bloodhoundPointId);
            bloodhoundProximityNotified = false;
        }
        bloodhoundPointId = id;
        pointLocations.put(id, routeStore.location(points[followingRouteIndex]));
    }

    function applyPhoneRouteState(payload as Dictionary) as Boolean {
        if (payload.get("action").equals("stop")) {
            if (!followingRoutePhoneOwned) { return true; }
            applyingPhoneRoute = true;
            setBloodhoundPoint(null);
            applyingPhoneRoute = false;
            if (payload.get("completed") == true) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.RouteComplete), null);
            }
            return true;
        }
        var route = routeStore.find(payload.get("serverId") as String, payload.get("routeUid") as String);
        var index = payload.get("targetPointIndex");
        if (!(index instanceof Number) || index < 0 || route == null || index >= (route.get("points") as Array).size()) { return false; }
        var id = routeStore.routeId(route);
        if (!followingRoutePhoneOwned || !id.equals(followingRouteId)) {
            applyingPhoneRoute = true;
            setBloodhoundPoint(null);
            applyingPhoneRoute = false;
        }
        followingRouteId = id;
        followingRouteIndex = index;
        followingRoutePhoneOwned = true;
        updateRouteFollow();
        refreshBloodhoundPicker();
        if (application != null) { application.refreshIncomingPointCount(); }
        notifyBloodhoundChanged();
        WatchUi.requestUpdate();
        return true;
    }

    function routeProgress() as String {
        var route = followingRouteId == null ? null : routeStore.route(followingRouteId);
        return route == null ? "" : Lang.format(WatchUi.loadResource(Rez.Strings.RouteProgress),
            [followingRouteIndex + 1, (route.get("points") as Array).size()]);
    }

    function routeRemainingLabel() as String {
        if (currentPosition == null) { return WatchUi.loadResource(Rez.Strings.RouteNeedsLocation); }
        var route = followingRouteId == null ? null : routeStore.route(followingRouteId);
        return route == null ? "" : application.formatDistance(RouteNavigation.remaining(
            route.get("points") as Array, followingRouteIndex, currentPosition), 1) + " remaining";
    }

    function receiveRoute(kind as String, payload as Dictionary) as Void {
        var following = followingRouteId == null ? null : routeStore.route(followingRouteId);
        var resetArrival = following != null && (kind.equals("routes_reset")
            || (following.get("serverId").equals(payload.get("serverId")) && following.get("uid").equals(payload.get("uid"))));
        if (kind.equals("routes_error")) {
            var message = payload.get("error");
            if (payload.get("routeVersion") == 1 && routeStore.validText(message, 256, false)) {
                System.println("TAK route transfer failed");
                WatchUi.showToast(message as String, null);
            } else {
                System.println("TAK route error rejected: invalid payload");
            }
            return;
        }
        if (!routeStore.receive(kind, payload)) {
            System.println("TAK route rejected: " + routeStore.error);
            WatchUi.showToast(routeStore.error, null);
            return;
        }
        if (resetArrival) { reachedRoutePoints = []; }
        refreshRouteBloodhound();
        if (application != null) { application.refreshIncomingPointCount(); }
        refreshBloodhoundPicker();
        WatchUi.requestUpdate();
    }

    function refreshRouteBloodhound() as Void {
        if (followingRouteId != null) { updateRouteFollow(); evaluateBloodhoundProximity(); return; }
        if (!(bloodhoundPointId instanceof String) || bloodhoundPointId.find("route-point:") != 0) { return; }
        var selected = routeStore.point(bloodhoundPointId);
        if (selected == null) {
            pointLocations.remove(bloodhoundPointId);
            setBloodhoundPoint(null);
        } else {
            pointLocations.put(bloodhoundPointId, routeStore.location(selected.get("point") as Dictionary));
            evaluateBloodhoundProximity();
        }
        notifyBloodhoundChanged();
    }

    function toggleRouteBloodhound(id as String) as Void {
        var selected = routeStore.point(id);
        if (selected == null) { routeUnavailable(); return; }
        if (isBloodhoundTarget(id)) {
            setBloodhoundPoint(null);
            pointLocations.remove(id);
        } else {
            if (bloodhoundPointId instanceof String && bloodhoundPointId.find("route-point:") == 0) {
                pointLocations.remove(bloodhoundPointId);
            }
            pointLocations.put(id, routeStore.location(selected.get("point") as Dictionary));
            setBloodhoundPoint(id);
        }
        notifyBloodhoundChanged();
    }

    function routeUnavailable() as Void {
        WatchUi.showToast(WatchUi.loadResource(Rez.Strings.RoutesUnavailable), null);
    }

    function removeLocalRoute(id as String) as Boolean {
        if (!routeStore.removeLocal(id)) { routeUnavailable(); return false; }
        refreshRouteBloodhound();
        if (application != null) { application.refreshIncomingPointCount(); }
        refreshBloodhoundPicker();
        WatchUi.requestUpdate();
        return true;
    }

    function focusBloodhoundItem(id as String) as Boolean {
        var route = routeStore.route(id);
        var points;
        if (route != null) { points = route.get("points") as Array; routesVisible = true; }
        else {
            var location = pointLocations.get(id);
            if (location == null) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.TextLocationUnavailable), null); return false;
            }
            var degrees = location.toDegrees();
            points = [{"lat" => degrees[0], "lon" => degrees[1]}];
        }
        var bounds = RouteNavigation.bounds(points);
        mapTopLeft = RouteNavigation.location({"lat" => bounds[0], "lon" => bounds[1]});
        mapBottomRight = RouteNavigation.location({"lat" => bounds[2], "lon" => bounds[3]});
        hasInitialPosition = true;
        markersDirty = true;
        applyMapVisibleArea();
        return true;
    }

    function refreshBloodhoundPicker() as Void {
        if (routeFollowMenu != null) { routeFollowMenu.refresh(); }
        if (application != null && application.incomingPointsMenu != null) { application.incomingPointsMenu.refresh(); }
    }

    function showRouteFollow(id as String) as Void {
        if (routeStore.route(id) == null) { routeUnavailable(); return; }
        WatchUi.pushView(new RouteFollowMenu(self, id), new RouteFollowDelegate(self, id), WatchUi.SLIDE_LEFT);
    }

    function showRoute(id as String) as Void {
        var menu = buildRouteMenu(self, id);
        if (menu == null) { routeUnavailable(); return; }
        WatchUi.pushView(menu, new RouteMenuDelegate(self, id), WatchUi.SLIDE_LEFT);
    }

    function showRoutePoint(id as String) as Void {
        var menu = buildRoutePointMenu(self, id);
        if (menu == null) { routeUnavailable(); return; }
        WatchUi.pushView(menu, new RoutePointMenuDelegate(self, id), WatchUi.SLIDE_LEFT);
    }

    function routeScreenPoint(point as Dictionary) as Array? {
        if (mapTopLeft == null || mapBottomRight == null || screenWidth <= 0 || screenHeight <= 0) { return null; }
        var left = mapTopLeft.toDegrees();
        var right = mapBottomRight.toDegrees();
        var span = right[1] - left[1];
        if (span < 0) { span += 360; }
        if (span == 0 || left[0] == right[0]) { return null; }
        var delta = point.get("lon") - (left[1] + span / 2.0);
        while (delta < -180) { delta += 360; }
        while (delta > 180) { delta -= 360; }
        return [(delta + span / 2.0) / span * screenWidth,
            (left[0] - point.get("lat")) / (left[0] - right[0]) * screenHeight];
    }

    function drawRoutes(dc) as Void {
        if (!routesVisible || mapTopLeft == null || mapBottomRight == null) { return; }
        dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
        for (var r = 0; r < routeStore.routes.size(); r++) {
            var points = routeStore.routes[r].get("points") as Array;
            var previous = [];
            for (var p = 0; p < points.size(); p++) {
                var screen = routeScreenPoint(points[p]);
                if (screen == null) { previous = []; continue; }
                var lonSpan = mapBottomRight.toDegrees()[1] - mapTopLeft.toDegrees()[1];
                if (lonSpan < 0) { lonSpan += 360; }
                var dx = previous.size() == 0 ? 0 : screen[0] - previous[0];
                if (previous.size() > 0 && dx.abs() <= screenWidth * 180.0 / lonSpan) {
                    var line = clippedRouteSegment(previous, screen, screenWidth - 1, screenHeight - 1);
                    if (line != null) {
                        dc.drawLine(line[0].toNumber(), line[1].toNumber(), line[2].toNumber(), line[3].toNumber());
                    }
                }
                if (screen[0] >= 0 && screen[0] < screenWidth && screen[1] >= 0 && screen[1] < screenHeight) {
                    dc.fillCircle(screen[0].toNumber(), screen[1].toNumber(), 4);
                }
                previous = screen;
            }
        }
    }

    function routesAtScreen(x, y) as Array<String> {
        var hits = [];
        if (!routesVisible || mapTopLeft == null || mapBottomRight == null
                || x < 0 || x >= screenWidth || y < 0 || y >= screenHeight) { return hits; }
        var lonSpan = mapBottomRight.toDegrees()[1] - mapTopLeft.toDegrees()[1];
        if (lonSpan < 0) { lonSpan += 360; }
        if (lonSpan == 0) { return hits; }
        for (var r = 0; r < routeStore.routes.size(); r++) {
            var route = routeStore.routes[r];
            var points = route.get("points") as Array;
            var previous = [];
            for (var p = 0; p < points.size(); p++) {
                var screen = routeScreenPoint(points[p]);
                if (screen == null) { previous = []; continue; }
                var dx = previous.size() == 0 ? 0 : screen[0] - previous[0];
                if (previous.size() > 0 && dx.abs() <= screenWidth * 180.0 / lonSpan) {
                    var line = clippedRouteSegment(previous, screen, screenWidth - 1, screenHeight - 1);
                    if (line != null && routeSegmentAtScreen(line, x, y)) {
                        hits.add(routeStore.routeId(route));
                        break;
                    }
                }
                previous = screen;
            }
        }
        return hits;
    }

    function initialize() {
        WatchUi.MapView.initialize();
        screenWidth = System.getDeviceSettings().screenWidth;
        screenHeight = System.getDeviceSettings().screenHeight;
        setScreenVisibleArea(0, 0, screenWidth, screenHeight);
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
        var currentInfo = Position.getInfo();
        if (currentInfo != null && currentInfo.position != null) {
            currentPosition = currentInfo.position;
        }
        centerOn(currentPosition);
        entityPruneTimer = new Timer.Timer();
        entityPruneTimer.start(method(:pruneIncomingEntitiesOnTimer), 60000, true);
        hiddenMapTeams = loadStoredStringArray("hiddenMapTeams");
        hiddenMapRoles = loadStoredStringArray("hiddenMapRoles");
        var storedButtons = Application.Storage.getValue("mapButtonsVisible");
        if (storedButtons instanceof Boolean) { mapButtonsVisible = storedButtons as Boolean; }
        loadPoints();
        loadIncomingAlertPersistence();
        var pending = Application.Storage.getValue("pendingSelfPoints");
        if (pending instanceof Array) {
            for (var i = 0; i < pending.size() && pendingSelfPoints.size() < 20; i++) {
                var entry = pending[i];
                if (entry instanceof Dictionary && entry.get("id") instanceof String
                        && entry.get("type") instanceof String && entry.get("title") instanceof String
                        && entry.get("droppedAt") instanceof String && entry.get("createdAt") instanceof Number) {
                    pendingSelfPoints.add(entry);
                } else { System.println("Invalid pending self marker ignored"); }
            }
        }
        expirePendingSelfPoints();
    }

    function onShow() as Void {
        if (application != null) { application.requestPositionForAction("map"); }
    }

    function loadIncomingAlertPersistence() as Void {
        var stored = Application.Storage.getValue("dismissedIncomingPoints");
        if (stored instanceof Dictionary) {
            dismissedIncomingPoints = stored;
        }
        var storedOrdering = Application.Storage.getValue("incomingAlertOrdering");
        if (storedOrdering instanceof Dictionary) {
            alertOrdering = storedOrdering;
        }
    }

    function saveIncomingAlertPersistence() as Void {
        try {
            Application.Storage.setValue("dismissedIncomingPoints", dismissedIncomingPoints);
            Application.Storage.setValue("incomingAlertOrdering", alertOrdering);
        } catch (error instanceof Lang.StorageFullException) {
            System.println("Incoming alert lifecycle not saved: storage full");
        } catch (error instanceof Application.ObjectStoreAccessException) {
            System.println("Incoming alert lifecycle not saved: storage unavailable");
        }
    }

    function loadStoredStringArray(key as String) as Array<String> {
        var value = Application.Storage.getValue(key);
        if (!(value instanceof Array)) { return []; }
        var normalized = [];
        var values = value as Array;
        for (var index = 0; index < values.size(); index++) {
            if (values[index] instanceof String) {
                var groupKey = normalizeMapGroup(values[index] as String);
                var exists = false;
                for (var normalizedIndex = 0; normalizedIndex < normalized.size(); normalizedIndex++) {
                    if ((normalized[normalizedIndex] as String).equals(groupKey)) { exists = true; }
                }
                if (groupKey.length() > 0 && !exists) { normalized.add(groupKey); }
            }
        }
        return normalized;
    }

    function typeToString(type as Symbol) as String {
        if (type == :friendly) {
            return "friendly";
        } else if (type == :hostile) {
            return "hostile";
        } else if (type == :neutral) {
            return "neutral";
        }
        return "unknown";
    }

    function typeFromString(type as String) as Symbol {
        if (type.equals("friendly")) {
            return :friendly;
        } else if (type.equals("hostile")) {
            return :hostile;
        } else if (type.equals("neutral")) {
            return :neutral;
        }
        return :unknown;
    }

    function savePoints() as Void {
        var saved = [];
        for (var i = 0; i < pointOrder.size(); i++) {
            var id = pointOrder[i] as String;
            if (!pointLocations.hasKey(id) || !pointDetails.hasKey(id)) { continue; }
            var details = pointDetails.get(id) as Dictionary;
            var degrees = pointLocations.get(id).toDegrees();
            saved.add({
                "id" => id,
                "lat" => degrees[0],
                "lon" => degrees[1],
                "type" => typeToString(details.get("type") as Symbol),
                "title" => safeDetailString(details, "title", ""),
                "remark" => safeDetailString(details, "remark", ""),
                "droppedAt" => safeDetailString(details, "droppedAt", "Unknown"),
                "localTime" => safeDetailString(details, "localTime", "Unknown"),
                "locationSource" => safeDetailString(details, "locationSource", ""),
                "phoneRevision" => safeDetailString(details, "phoneRevision", ""),
                "createdAt" => details.get("createdAt") == null ? 0 : details.get("createdAt") as Number
            });
        }
        Application.Storage.setValue("droppedPoints", saved);
        Application.Storage.setValue("nextPointNumber", nextPointNumber);
    }

    function loadPoints() as Void {
        var nextNumber = Application.Storage.getValue("nextPointNumber");
        if (nextNumber instanceof Number) { nextPointNumber = nextNumber; }
        var storedDefaultType = Application.Storage.getValue("defaultPointType");
        if (storedDefaultType instanceof String) {
            defaultPointType = typeFromString(storedDefaultType as String);
        }
        var saved = Application.Storage.getValue("droppedPoints");
        if (saved == null) {
            return;
        }
        var savedArray = saved as Array;
        for (var i = 0; i < savedArray.size(); i++) {
            var entry = savedArray[i] as Dictionary;
            var id = entry.get("id") as String;
            var location = new Position.Location({:latitude => entry.get("lat") as Double, :longitude => entry.get("lon") as Double, :format => :degrees});
            var type = typeFromString(entry.get("type") as String);
            var title = entry.get("title") as String;
            var droppedAt = entry.get("droppedAt");
            var localTime = entry.get("localTime");
            var createdAt = entry.get("createdAt");
            markers.put(id, createPointMarker(location, type, title));
            pointLocations.put(id, location);
            pointDetails.put(id, {"type" => type, "title" => title, "remark" => entry.get("remark") as String, "droppedAt" => droppedAt == null ? "Unknown" : droppedAt.toString(), "localTime" => localTime == null ? "Unknown" : localTime.toString(), "createdAt" => createdAt == null ? 0 : createdAt as Number});
            (pointDetails.get(id) as Dictionary).put("locationSource", safeDetailString(entry, "locationSource", ""));
            (pointDetails.get(id) as Dictionary).put("phoneRevision", safeDetailString(entry, "phoneRevision", ""));
            pointOrder.add(id);
        }
        sortPointOrderNewestFirst();
        var storedNextPointNumber = Application.Storage.getValue("nextPointNumber");
        if (storedNextPointNumber != null) {
            nextPointNumber = storedNextPointNumber as Number;
        }
        markersDirty = true;
    }

    function updatePosition(info) {
        if (info == null || info.position == null) {
            routePositionUsable = false;
            return;
        }
        routePositionUsable = info.accuracy >= Position.QUALITY_USABLE;
        currentPosition = info.position;
        markersDirty = true;
        if (info.accuracy >= Position.QUALITY_USABLE) { resolvePendingPoints(info.position); }
        updateRouteFollow();
        refreshBloodhoundPicker();
        evaluateBloodhoundProximity();

        if (!hasInitialPosition) {
            centerOn(info.position);
        }
        WatchUi.requestUpdate();
    }

    function setTakClient(client as TakClient) as Void {
        takClient = client;
        client.bloodhoundSync.activeTargetCallback = method(:bloodhoundRelayTarget);
        client.bloodhoundSync.startTrackingCallback = method(:startBloodhoundFromPhone);
        client.bloodhoundSync.stopTrackingCallback = method(:stopBloodhoundFromPhone);
        client.bloodhoundSync.updateTrackingCallback = method(:updateBloodhoundFromPhone);
        client.routeNavigationSync.applyCallback = method(:applyPhoneRouteState);
    }

    function setApplication(app as StandaloneApp) as Void {
        application = app;
    }

    function evaluateBloodhoundProximity() as Void {
        if (application == null || currentPosition == null || !isBloodhoundActive()) {
            bloodhoundProximityNotified = false;
            return;
        }
        var rangeMeters = getBloodhoundRangeMeters();
        if (rangeMeters > application.getBloodhoundProximityRadius()) {
            bloodhoundProximityNotified = false;
            return;
        }
        if (bloodhoundProximityNotified) {
            return;
        }
        bloodhoundProximityNotified = true;
        if (application.isBloodhoundProximityVibrationEnabled()) {
            vibrateForProximity(application.getBloodhoundProximityIntensity());
        }
        WatchUi.showToast(application.text(Rez.Strings.TextProximity), null);
    }

    function vibrateForProximity(intensity as String) as Void {
        if (intensity.equals("Triple Burst")) {
            Attention.vibrate([
                new Attention.VibeProfile(80, 250),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(80, 250),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(80, 250)
            ]);
        } else if (intensity.equals("Until In Position")) {
            Attention.vibrate([new Attention.VibeProfile(80, 1000)]);
        } else {
            Attention.vibrate([new Attention.VibeProfile(80, 400)]);
        }
    }

    function showPointTypeMenu(pointId) as Void {
        if (routeStore.route(pointId) != null) { showRoute(pointId); return; }
        if (routeStore.point(pointId) != null) { showRoutePoint(pointId); return; }
        if (incomingDetails.hasKey(pointId)) {
            WatchUi.pushView(buildIncomingPointActions(self, pointId),
                new IncomingPointActionsDelegate(self, pointId), WatchUi.SLIDE_LEFT);
            return;
        }
        var menu = buildPointDetailsMenu(self, pointId);
        WatchUi.pushView(menu, new PointDetailsMenuDelegate(self, pointId, menu), WatchUi.SLIDE_LEFT);
    }

    function showSelfMenu() as Void {
        if (currentPosition != null) {
            showCoordinateMenu(application.text(Rez.Strings.TextSelf), currentPosition);
        }
    }

    function showMapItemsAtScreen(x, y) as Void {
        var ids = pointsAtScreen(x, y);
        var routes = routesAtScreen(x, y);
        for (var i = 0; i < routes.size(); i++) { ids.add(routes[i]); }
        var includeSelf = isSelfAtScreen(x, y);
        if (ids.size() + (includeSelf ? 1 : 0) > 1) {
            showMapSelectionMenu(ids, includeSelf);
        } else if (ids.size() == 1) {
            showPointTypeMenu(ids[0]);
        } else if (includeSelf) {
            showSelfMenu();
        }
    }

    function showMapSelectionMenu(ids as Array<String>, includeSelf as Boolean) as Void {
        WatchUi.pushView(buildMapSelectionMenu(self, ids, includeSelf),
            new MapSelectionMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function showSelectedMapItem(id as String or Symbol) as Void {
        if (id == :self) {
            if (currentPosition == null) {
                WatchUi.showToast(application.text(Rez.Strings.TextLocationUnavailable), null);
                return;
            }
            showSelfMenu();
        } else if (id instanceof String) {
            if (id.find("route:") == 0) { showRoute(id); return; }
            if (routeStore.point(id) != null) { showRoutePoint(id); return; }
            if (!pointLocations.hasKey(id) || !isIncomingUserVisible(id)) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
                return;
            }
            showPointTypeMenu(id);
        }
    }

    function toggleBloodhound(pointId) as Void {
        if (bloodhoundPointId != null && bloodhoundPointId.equals(pointId)) {
            setBloodhoundPoint(null);
        } else {
            setBloodhoundPoint(pointId);
        }
        notifyBloodhoundChanged();
    }

    function setBloodhoundPoint(pointId) as Void {
        if (followingRoutePhoneOwned && !applyingPhoneRoute && takClient != null) {
            takClient.routeNavigationSync.stopLocal();
        }
        followingRouteId = null;
        followingRouteIndex = 0;
        followingRoutePhoneOwned = false;
        reachedRoutePoints = [];
        if (bloodhoundPointId instanceof String && bloodhoundPointId.find("route-point:") == 0
                && !bloodhoundPointId.equals(pointId)) { pointLocations.remove(bloodhoundPointId); }
        bloodhoundPointId = pointId;
        if (pointId != null) {
            if (application != null) { application.requestPositionForAction("navigation"); }
            var currentInfo = Position.getInfo();
            if (currentInfo != null && currentInfo.position != null) {
                currentPosition = currentInfo.position;
                routePositionUsable = currentInfo.accuracy >= Position.QUALITY_USABLE;
                markersDirty = true;
            }
        }
        bloodhoundProximityNotified = false;
        evaluateBloodhoundProximity();
        refreshBloodhoundPicker();
        if (application != null) { application.refreshIncomingPointCount(); }
        WatchUi.requestUpdate();
    }

    // Phone-initiated changes must not echo a command back, so only local edits notify.
    function notifyBloodhoundChanged() as Void {
        if (takClient != null) { takClient.bloodhoundSync.localTargetChanged(); }
        if (application != null) { application.refreshIncomingPointCount(); }
    }

    function bloodhoundTarget() as Dictionary? {
        return bloodhoundPointId == null ? null : bloodhoundTargetFor(bloodhoundPointId as String);
    }

    function bloodhoundRelayTarget() as Dictionary? {
        // Route vertices have no native ATAK point UID; keep their tracking local.
        if (bloodhoundPointId instanceof String && bloodhoundPointId.find("route-point:") == 0) { return null; }
        return bloodhoundTarget();
    }

    function bloodhoundTargetFor(pointId as String) as Dictionary? {
        var uid = bloodhoundTargetUid(pointId);
        var location = pointLocations.get(pointId);
        if (uid == null || location == null) { return null; }
        var degrees = location.toDegrees();
        return {
            "uid" => uid,
            "callsign" => bloodhoundTargetLabel(pointId, uid as String),
            "lat" => degrees[0].toDouble(),
            "lon" => degrees[1].toDouble(),
            "hae" => 0.0d
        };
    }

    function bloodhoundTargetUid(pointId as String) as String? {
        if (routeStore.point(pointId) != null) { return pointId; }
        var details = incomingDetails.get(pointId);
        if (details instanceof Dictionary) {
            var uid = (details as Dictionary).get("uid");
            if (uid instanceof String && (uid as String).length() > 0) { return uid as String; }
        }
        return pointDetails.hasKey(pointId) ? "garmin-marker-" + pointId : null;
    }

    function bloodhoundTargetLabel(pointId as String, uid as String) as String {
        var selected = routeStore.point(pointId);
        if (selected != null) { return routeStore.title(selected); }
        var details = incomingDetails.get(pointId);
        if (details instanceof Dictionary) {
            var callSign = (details as Dictionary).get("callSign");
            return callSign instanceof String && (callSign as String).length() > 0 ? callSign as String : uid;
        }
        details = pointDetails.get(pointId);
        if (details instanceof Dictionary) {
            var title = (details as Dictionary).get("title");
            if (title instanceof String && (title as String).length() > 0) { return title as String; }
        }
        return uid;
    }

    function bloodhoundPointIdForUid(uid as String) as String? {
        var selected = routeStore.point(uid);
        if (selected != null) {
            pointLocations.put(uid, routeStore.location(selected.get("point") as Dictionary));
            return uid;
        }
        var ids = incomingDetails.keys();
        for (var index = 0; index < ids.size(); index++) {
            var pointId = ids[index] as String;
            var details = incomingDetails.get(pointId);
            if (!(details instanceof Dictionary)) { continue; }
            var candidate = (details as Dictionary).get("uid");
            if (candidate instanceof String && uid.equals(candidate as String)
                    && pointLocations.hasKey(pointId)) { return pointId; }
        }
        var prefix = "garmin-marker-";
        if (uid.length() > prefix.length() && uid.substring(0, prefix.length()).equals(prefix)) {
            var localId = uid.substring(prefix.length(), uid.length());
            if (pointLocations.hasKey(localId)) { return localId; }
        }
        return null;
    }

    function startBloodhoundFromPhone(target as Dictionary) as Boolean {
        var uid = target.get("uid");
        if (!(uid instanceof String)) { return false; }
        var pointId = bloodhoundPointIdForUid(uid as String);
        if (pointId == null) { return false; }
        setBloodhoundPoint(pointId);
        return true;
    }

    function stopBloodhoundFromPhone(uid as String) as Boolean {
        if (bloodhoundPointId == null || !uid.equals(bloodhoundTargetUid(bloodhoundPointId as String))) {
            return false;
        }
        setBloodhoundPoint(null);
        return true;
    }

    // The watch tracks the target from its own entity stream, so a move only needs acknowledging.
    function updateBloodhoundFromPhone(target as Dictionary) as Boolean {
        var uid = target.get("uid");
        return uid instanceof String && bloodhoundPointId != null
            && (uid as String).equals(bloodhoundTargetUid(bloodhoundPointId as String));
    }

    function reconcileSelfMarker(uid as String, latitude, longitude, metadata as Dictionary) as Boolean {
        var prefix = "garmin-marker-";
        if (uid.find(prefix) != 0 || uid.length() <= prefix.length()) { return false; }
        expirePendingSelfPoints();
        var id = uid.substring(prefix.length(), uid.length());
        var details = pointDetails.get(id);
        var pending = null;
        for (var i = 0; i < pendingSelfPoints.size(); i++) {
            if ((pendingSelfPoints[i].get("id") as String).equals(id)) { pending = pendingSelfPoints[i]; break; }
        }
        if (pending == null && (!(details instanceof Dictionary)
                || !safeDetailString(details, "locationSource", "").equals("phone"))) { return false; }
        if (!isUsableIncomingLocation(latitude, longitude)) {
            System.println("Phone self marker update rejected: unusable coordinates");
            return true;
        }
        var revision = incomingPointRevision(metadata);
        if (details instanceof Dictionary && revision.length() > 0
                && compareIncomingRevision(revision, safeDetailString(details, "phoneRevision", "")) < 0) { return true; }
        var location = new Position.Location({:latitude => latitude as Double, :longitude => longitude as Double, :format => :degrees});
        if (!(details instanceof Dictionary) && pending instanceof Dictionary) {
            storeResolvedPoint(id, location, typeFromString(pending.get("type") as String),
                pending.get("title"), pending.get("droppedAt") as String, "phone", revision);
        } else {
            pointLocations.put(id, location);
            markers.put(id, createPointMarker(location, details.get("type"), details.get("title")));
            details.put("locationSource", "phone");
            details.put("phoneRevision", revision);
            savePoints();
        }
        if (pending instanceof Dictionary) {
            pendingSelfPoints.remove(pending);
            if (takClient != null && !takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints)) {
                pendingSelfPoints.add(pending);
            }
        }
        markersDirty = true;
        evaluateBloodhoundProximity();
        refreshBloodhoundPicker();
        WatchUi.requestUpdate();
        return true;
    }

    function updateIncomingCot(uid as String, latitude, longitude, cotType as String, callSign as String?, team as String?, role as String?, metadata as Dictionary) as Void {
        var markerId = "cot-" + uid;
        if (metadata == null) { metadata = {}; }
        if (cotType.equals("t-x-d-d")) {
            var link = metadata.get("link");
            var relation = link instanceof Dictionary ? link.get("relation") : null;
            var target = relation instanceof String && relation.equals("p-p") ? link.get("uid") : uid;
            if (!(target instanceof String) || target.length() == 0) {
                System.println("Incoming delete rejected: missing target UID");
                return;
            }
            markerId = "cot-" + target;
            var previous = incomingDetails.get(markerId);
            var revision = incomingPointRevision(metadata);
            if (revision.length() == 0) {
                revision = currentCotTimestamp();
                if (previous instanceof Dictionary
                        && compareIncomingRevision(previous.get("revision") as String, revision) > 0) {
                    revision = previous.get("revision") as String;
                }
            }
            if (previous instanceof Dictionary
                    && compareIncomingRevision(revision, previous.get("revision") as String) < 0) { return; }
            var deleted = dismissedIncomingPoints.get(markerId);
            if (deleted instanceof Dictionary && deleted.get("revision") instanceof String
                    && compareIncomingRevision(revision, deleted.get("revision") as String) < 0) { return; }
            if (dismissedIncomingPoints.size() >= MAP_RETAINED_LIMIT) {
                dismissedIncomingPoints.remove(dismissedIncomingPoints.keys()[0]);
            }
            dismissedIncomingPoints.put(markerId, {
                "revision" => revision, "removedAt" => Time.now().value(), "isAlert" => false
            });
            userSourceStates.remove(target);
            alertSourceStates.remove(markerId);
            removeIncomingPoint(markerId, false);
            saveIncomingAlertPersistence();
            return;
        }
        if (reconcileSelfMarker(uid, latitude, longitude, metadata)) { return; }
        if (isIncomingUser(cotType, metadata) && metadata.get("__userRebuild") != true) {
            updateIncomingUser(uid, latitude, longitude, cotType, callSign, team, role, metadata);
            return;
        }
        var alertType = isIncomingAlert(cotType, metadata);
        if (alertType) {
            if (isSelfIncomingAlert(uid, metadata)) {
                System.println("Incoming alert rejected: local sender");
                return;
            }
            updateIncomingAlert(uid, latitude, longitude, cotType, callSign, team, role, metadata);
            return;
        }
        var isAlert = false;
        var isPoint = isIncomingMapPoint(cotType, metadata);
        var revision = incomingPointRevision(metadata);
        var staleDeadline = incomingPointStaleDeadline(metadata);
        if (staleDeadline.length() > 0 && userDeadlineExpired(staleDeadline)) {
            System.println("Incoming point rejected: expired location");
            return;
        }
        if (dismissedIncomingPoints.hasKey(markerId)) {
            var dismissed = dismissedIncomingPoints.get(markerId) as Dictionary;
            var dismissedRevision = dismissed.get("revision");
            if (revision.equals(dismissedRevision) || revision.length() == 0) { return; }
            if (dismissedRevision instanceof String && revision.length() > 0 && compareIncomingRevision(revision, dismissedRevision) < 0) { return; }
            dismissedIncomingPoints.remove(markerId);
            saveIncomingAlertPersistence();
        }
        var previous = incomingDetails.get(markerId);
        if (metadata.get("__userRebuild") != true && previous instanceof Dictionary && revision.length() > 0
                && compareIncomingRevision(revision, previous.get("revision") as String) < 0) { return; }
        var notify = (isPoint || isAlert) && (previous == null
            || (isAlert && previous.get("isAlert") != true)
            || (revision.length() > 0 && !revision.equals(previous.get("revision"))));
        if (previous instanceof Dictionary && previous.get("isAlert") == true && !isAlert) {
            pendingIncomingPoints.remove(markerId);
            if (isBloodhoundTarget(markerId)) { toggleBloodhound(markerId); }
        }
        var validLocation = isIncomingCoordinateValue(latitude) && isIncomingCoordinateValue(longitude);
        if (validLocation) {
            var lat = latitude as Number;
            var lon = longitude as Number;
            validLocation = lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
        }
        var location = null;
        if (validLocation) {
            location = new Position.Location({:latitude => latitude as Double, :longitude => longitude as Double, :format => :degrees});
        }
        if (!incomingDetails.hasKey(markerId)) {
            incomingIds.add(markerId);
            if (incomingIds.size() > MAP_RETAINED_LIMIT) {
                removeIncomingPoint(incomingIds[0], false);
            }
        }
        incomingLastSeen.put(markerId, incomingEntityNow());
        incomingDetails.put(markerId, {
            "uid" => uid, "type" => cotType,
            "callSign" => callSign == null ? "" : trimMapText(callSign),
            "team" => team == null ? "" : trimMapText(team),
            "role" => role == null ? "" : trimMapText(role),
            "isPoint" => isPoint, "isAlert" => isAlert,
            "isUser" => isIncomingUser(cotType, metadata),
            "source" => incomingPointSource(metadata),
            "senderUID" => incomingPointSender(metadata),
            "revision" => revision,
            "staleDeadline" => staleDeadline,
            "generic" => !isIncomingUser(cotType, metadata) && ((cotType.find("a-") == 0
                    && (!isPoint || (cotType.find("-G-T") != 3 && cotType.find("-G-E") != 3)))
                || cotType.equals("b-m-p-s-m") || cotType.equals("b-m-p-s-p-i") || cotType.find("u-d-") == 0),
            "circleRadius" => cotType.equals("u-d-c-c") ? incomingCircleRadius(metadata) : null,
            "stale" => false,
            "lastKnownLocation" => location
        });
        if (isIncomingCamera(cotType, metadata)) {
            incomingDetails.get(markerId).put("isCamera", true);
        }
        if (location != null) {
            pointLocations.put(markerId, location);
        } else {
            pointLocations.remove(markerId);
        }
        if (notify) {
            if (pendingIncomingPoints.indexOf(markerId) == -1) { pendingIncomingPoints.add(markerId); }
            Attention.vibrate([new Attention.VibeProfile(80, 250)]);
            WatchUi.showToast(isAlert ? incomingPointTitle(markerId)
                : WatchUi.loadResource(Rez.Strings.IncomingPointReceived), null);
        }
        application.refreshIncomingPointCount();
        if (metadata.get("__userRebuild") != true) { pruneIncomingEntities(); }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function applyPhoneUserLifecycle(action as String, payload as Dictionary) as Void {
        if (action.equals("remove")) {
            var uid = payload.get("uid");
            if (uid instanceof String) {
                var sources = userSourceStates.get(uid);
                var previous = sources instanceof Dictionary ? sources.get("phone-relay") : null;
                var revision = incomingPointRevision(payload);
                if (previous instanceof Dictionary && revision.length() > 0
                        && compareIncomingRevision(revision, previous.get("revision") as String) < 0) { return; }
                removeIncomingUserSource(uid as String, "phone-relay");
            }
            return;
        }
        if (action.equals("snapshot")) {
            var excluded = payload.get("excludedUids");
            var deviceId = System.getDeviceSettings().uniqueIdentifier;
            if (!(excluded instanceof Array) || deviceId == null) {
                System.println("Phone user snapshot rejected: identity exclusions are missing");
                return;
            }
            var validatedExcluded = [];
            for (var index = 0; index < excluded.size(); index++) {
                var uid = excluded[index];
                if (!(uid instanceof String) || (uid as String).length() == 0) {
                    System.println("Phone user snapshot rejected: invalid identity exclusion");
                    return;
                }
                if (validatedExcluded.indexOf(uid) == -1) { validatedExcluded.add(uid); }
            }
            if (validatedExcluded.size() < 2 || validatedExcluded.indexOf(deviceId) == -1) {
                System.println("Phone user snapshot rejected: phone/watch identities are incomplete");
                return;
            }
            phoneUserSyncRequested = false;
            phoneUserExcludedUids = validatedExcluded;
            phoneUserIdentityReady = true;
            var retained = [];
            var entities = payload.get("entities");
            if (!(entities instanceof Array)) { return; }
            for (var index = 0; index < entities.size(); index++) {
                var entity = entities[index];
                if (entity instanceof Dictionary && entity.get("uid") instanceof String
                        && entity.get("type") instanceof String
                        && isIncomingUser(entity.get("type") as String, entity as Dictionary)) {
                    retained.add(entity.get("uid"));
                }
            }
            if (payload.get("truncated") == true) {
                WatchUi.showToast("Phone map limited to nearest 50 entities", null);
            }
            var ids = userSourceStates.keys();
            for (var index = 0; index < ids.size(); index++) {
                var uid = ids[index] as String;
                if (retained.indexOf(uid) == -1 || phoneUserExcludedUids.indexOf(uid) != -1) {
                    removeIncomingUserSource(uid, "phone-relay");
                }
            }
            return;
        }
        if (!action.equals("reset")) {
            System.println("Phone user lifecycle rejected: unknown action");
            return;
        }
        phoneUserExcludedUids = [];
        phoneUserIdentityReady = false;
        phoneUserSyncRequested = false;
        var ids = userSourceStates.keys();
        for (var index = 0; index < ids.size(); index++) {
            removeIncomingUserSource(ids[index] as String, "phone-relay");
        }
    }

    function updateIncomingUser(uid as String, latitude, longitude, cotType as String,
            callSign as String?, team as String?, role as String?, metadata as Dictionary) as Void {
        var source = incomingPointSource(metadata);
        var revision = incomingPointRevision(metadata);
        var sources = userSourceStates.get(uid);
        var previous = sources instanceof Dictionary ? sources.get(source) : null;
        if (previous instanceof Dictionary
                && compareIncomingRevision(revision, previous.get("revision") as String) < 0) { return; }
        if (source.equals("phone-relay") && metadata.get("isUser") == true && !phoneUserIdentityReady) {
            System.println("Phone user update ignored until identity snapshot is available");
            return;
        }
        var deviceId = System.getDeviceSettings().uniqueIdentifier;
        if ((deviceId != null && uid.equals(deviceId))
                || (source.equals("phone-relay") && phoneUserExcludedUids.indexOf(uid) != -1)) {
            removeIncomingUserSource(uid, source);
            return;
        }
        var stale = incomingPointStaleDeadline(metadata);
        if (stale.length() > 0 && userDeadlineExpired(stale)) {
            removeIncomingUserSource(uid, source);
            return;
        }
        if (!isIncomingCoordinateValue(latitude) || !isIncomingCoordinateValue(longitude)
                || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) { return; }
        var boundedPhoneUser = source.equals("phone-relay") && metadata.get("isUser") == true;
        if (boundedPhoneUser && previous == null && phoneRelayUserCount() >= PHONE_USER_RETAINED_LIMIT) {
            if (!phoneUserSyncRequested) {
                phoneUserSyncRequested = true;
                if (takClient != null) {
                    takClient.transmit("entity_sync_request", {
                        "limit" => PHONE_USER_RETAINED_LIMIT, "protocolVersion" => 1, "routeVersion" => 1
                    });
                    System.println("Phone user map full; requesting a fresh nearest-user snapshot");
                } else {
                    System.println("Phone user map full; relay unavailable for snapshot request");
                }
            }
            return;
        }
        if (!(sources instanceof Dictionary)) {
            if (userSourceStates.size() >= MAP_RETAINED_LIMIT) {
                WatchUi.showToast("User map capacity reached (999); oldest user replaced", null);
                if (!evictOldestIncomingUser()) { return; }
            }
            sources = {};
            userSourceStates.put(uid, sources);
        }
        var copy = {};
        var keys = metadata.keys();
        for (var index = 0; index < keys.size(); index++) { copy.put(keys[index], metadata.get(keys[index])); }
        copy.put("__userRebuild", true);
        sources.put(source, {
            "uid" => uid, "lat" => latitude, "lon" => longitude, "type" => cotType,
            "callSign" => callSign, "team" => team, "role" => role, "metadata" => copy,
            "revision" => revision, "staleDeadline" => stale, "seen" => Time.now().value(),
            "boundedPhoneUser" => boundedPhoneUser
        });
        rebuildIncomingUser(uid);
    }

    function evictOldestIncomingUser() as Boolean {
        for (var index = 0; index < incomingIds.size(); index++) {
            var id = incomingIds[index] as String;
            var details = incomingDetails.get(id);
            if (details instanceof Dictionary && details.get("isUser") == true) {
                removeIncomingPoint(id, false);
                return true;
            }
        }
        var oldestUid = null;
        var oldestSeen = null;
        var ids = userSourceStates.keys();
        for (var index = 0; index < ids.size(); index++) {
            var sources = userSourceStates.get(ids[index]);
            var sourceKeys = sources.keys();
            for (var sourceIndex = 0; sourceIndex < sourceKeys.size(); sourceIndex++) {
                var record = sources.get(sourceKeys[sourceIndex]);
                var seen = record.get("seen");
                if (seen instanceof Number && (oldestSeen == null || seen < oldestSeen)) {
                    oldestUid = ids[index];
                    oldestSeen = seen;
                }
            }
        }
        if (oldestUid == null) { return false; }
        userSourceStates.remove(oldestUid);
        return true;
    }

    function phoneRelayUserCount() as Number {
        var count = 0;
        var ids = userSourceStates.keys();
        for (var index = 0; index < ids.size(); index++) {
            var sources = userSourceStates.get(ids[index]);
            var record = sources instanceof Dictionary ? sources.get("phone-relay") : null;
            if (record instanceof Dictionary && record.get("boundedPhoneUser") == true) { count++; }
        }
        return count;
    }

    function userDeadlineExpired(deadline as String) as Boolean {
        if (deadline.length() < 20) { return true; }
        var digits = "0123456789";
        for (var index = 0; index < 19; index++) {
            var character = deadline.substring(index, index + 1);
            if (index == 4 || index == 7) {
                if (!character.equals("-")) { return true; }
            } else if (index == 10) {
                if (!character.equals("T")) { return true; }
            } else if (index == 13 || index == 16) {
                if (!character.equals(":")) { return true; }
            } else if (digits.find(character) == null) { return true; }
        }
        if (!deadline.substring(deadline.length() - 1, deadline.length()).equals("Z")) { return true; }
        return compareCotTimestamp(deadline, currentCotTimestamp()) <= 0;
    }

    function removeIncomingUserSource(uid as String, source as String) as Void {
        var sources = userSourceStates.get(uid);
        if (!(sources instanceof Dictionary) || !sources.hasKey(source)) { return; }
        sources.remove(source);
        if (sources.size() == 0) { userSourceStates.remove(uid); }
        rebuildIncomingUser(uid);
    }

    function rebuildIncomingUser(uid as String) as Void {
        var sources = userSourceStates.get(uid);
        var selected = null;
        if (sources instanceof Dictionary) {
            var keys = sources.keys();
            for (var index = 0; index < keys.size(); index++) {
                var candidate = sources.get(keys[index]);
                if (selected == null || compareIncomingRevision(candidate.get("revision") as String,
                        selected.get("revision") as String) > 0) { selected = candidate; }
            }
        }
        var markerId = "cot-" + uid;
        var visible = incomingDetails.get(markerId);
        // Removing a user copy must not erase a dropped point or an alert sharing its UID.
        if (visible instanceof Dictionary && visible.get("isPoint") == true) { return; }
        if (selected == null) {
            if (visible instanceof Dictionary && visible.get("isUser") == true) {
                removeIncomingPoint(markerId, false);
            }
            return;
        }
        var selectedRecord = selected as Dictionary;
        updateIncomingCot(uid, selectedRecord.get("lat"), selectedRecord.get("lon"), selectedRecord.get("type") as String,
            selectedRecord.get("callSign") as String?, selectedRecord.get("team") as String?,
            selectedRecord.get("role") as String?, selectedRecord.get("metadata") as Dictionary);
    }

    function updateIncomingAlert(uid as String, latitude, longitude, cotType as String, callSign as String?,
            team as String?, role as String?, metadata as Dictionary) as Void {
        var markerId = "cot-" + uid;
        var source = incomingPointSource(metadata);
        var revision = incomingPointRevision(metadata);
        var cancellation = isIncomingAlertCleared(cotType, metadata);
        var order = alertOrdering.get(markerId);
        if (order instanceof Dictionary) {
            var latestRevision = order.get("revision");
            latestRevision = latestRevision instanceof String ? latestRevision as String : "";
            var comparison = compareIncomingRevision(revision, latestRevision);
            if (comparison < 0 || (!cancellation && order.get("cancelled") == true && comparison <= 0)) {
                System.println("Incoming alert rejected: out of order " + uid);
                return;
            }
        }

        alertOrdering.put(markerId, {"revision" => revision, "cancelled" => cancellation});
        var sources = alertSourceStates.get(markerId);
        if (!(sources instanceof Dictionary)) {
            sources = {};
            alertSourceStates.put(markerId, sources);
        }

        if (cancellation) {
            var sourceKeys = (sources as Dictionary).keys();
            for (var sourceIndex = 0; sourceIndex < sourceKeys.size(); sourceIndex++) {
                var sourceRecord = (sources as Dictionary).get(sourceKeys[sourceIndex]);
                if (!(sourceRecord instanceof Dictionary)) { continue; }
                var sourceRevision = sourceRecord.get("revision");
                sourceRevision = sourceRevision instanceof String ? sourceRevision as String : "";
                if (compareIncomingRevision(sourceRevision, revision) <= 0) {
                    (sources as Dictionary).remove(sourceKeys[sourceIndex]);
                }
            }
            if ((sources as Dictionary).size() == 0) { alertSourceStates.remove(markerId); }
            if (dismissedIncomingPoints.hasKey(markerId)) {
                var dismissal = dismissedIncomingPoints.get(markerId) as Dictionary;
                var dismissalRevision = dismissal.get("latestRevision");
                dismissalRevision = dismissalRevision instanceof String ? dismissalRevision as String : "";
                if (compareIncomingRevision(revision, dismissalRevision) >= 0) {
                    dismissedIncomingPoints.remove(markerId);
                }
            }
            saveIncomingAlertPersistence();
            rebuildVisibleAlert(markerId);
            return;
        }

        var validLocation = isUsableIncomingLocation(latitude, longitude);
        var location = validLocation
            ? new Position.Location({:latitude => latitude as Double, :longitude => longitude as Double, :format => :degrees})
            : null;
        var previousSource = (sources as Dictionary).get(source);
        if (location == null && previousSource instanceof Dictionary) {
            location = previousSource.get("lastKnownLocation");
        }
        var sender = incomingPointSender(metadata);
        var displayCallSign = callSign == null ? "" : trimMapText(callSign);
        if (displayCallSign.length() == 0 && sender.length() > 0) { displayCallSign = sender; }
        (sources as Dictionary).put(source, {
            "uid" => uid, "type" => cotType,
            "callSign" => displayCallSign,
            "team" => team == null ? "" : trimMapText(team),
            "role" => role == null ? "" : trimMapText(role),
            "isPoint" => false, "isAlert" => true,
            "senderUID" => sender,
            "category" => trimMapText(incomingPointCategory(cotType, metadata)),
            "revision" => revision,
            "staleDeadline" => incomingPointStaleDeadline(metadata),
            "lastKnownLocation" => location,
            "source" => source
        });
        saveIncomingAlertPersistence();

        if (dismissedIncomingPoints.hasKey(markerId)) {
            var dismissal = dismissedIncomingPoints.get(markerId) as Dictionary;
            var dismissedRevision = dismissal.get("latestRevision");
            dismissedRevision = dismissedRevision instanceof String ? dismissedRevision as String : "";
            if (compareIncomingRevision(revision, dismissedRevision) > 0) {
                dismissal.put("latestRevision", revision);
                saveIncomingAlertPersistence();
            }
            System.println("Incoming alert accepted but hidden by local dismissal: " + uid);
            return;
        }
        rebuildVisibleAlert(markerId);
    }

    function isUsableIncomingLocation(latitude, longitude) as Boolean {
        if (!isIncomingCoordinateValue(latitude) || !isIncomingCoordinateValue(longitude)) { return false; }
        var lat = latitude;
        var lon = longitude;
        return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
    }

    function rebuildVisibleAlert(markerId as String) as Void {
        var sources = alertSourceStates.get(markerId);
        var selected = null;
        if (sources instanceof Dictionary) {
            var sourceKeys = (sources as Dictionary).keys();
            for (var index = 0; index < sourceKeys.size(); index++) {
                var candidate = (sources as Dictionary).get(sourceKeys[index]);
                if (!(candidate instanceof Dictionary)) { continue; }
                if (!(selected instanceof Dictionary)
                        || compareIncomingRevision(candidate.get("revision") as String,
                            (selected as Dictionary).get("revision") as String) > 0) {
                    selected = candidate;
                }
            }
        }
        if (!(selected instanceof Dictionary) || dismissedIncomingPoints.hasKey(markerId)) {
            removeIncomingPoint(markerId, false);
            return;
        }

        var isNew = !incomingDetails.hasKey(markerId);
        if (isNew) {
            incomingIds.add(markerId);
            if (incomingIds.size() > MAP_RETAINED_LIMIT) { removeIncomingPoint(incomingIds[0], false); }
        }
        var selectedDetails = selected as Dictionary;
        selectedDetails.put("stale", isIncomingAlertStale(selectedDetails));
        incomingDetails.put(markerId, selectedDetails);
        incomingLastSeen.put(markerId, Time.now().value());
        var location = selectedDetails.get("lastKnownLocation");
        if (location != null) { pointLocations.put(markerId, location); }
        else { pointLocations.remove(markerId); }
        if (isNew) {
            pendingIncomingPoints.add(markerId);
            Attention.vibrate([new Attention.VibeProfile(80, 250)]);
            WatchUi.showToast(incomingPointTitle(markerId), null);
        }
        if (application != null) { application.refreshIncomingPointCount(); }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function isIncomingAlertStale(details as Dictionary) as Boolean {
        var deadline = details.get("staleDeadline");
        if (!(deadline instanceof String) || (deadline as String).length() == 0) { return false; }
        return compareCotTimestamp(deadline as String, currentCotTimestamp()) <= 0;
    }

    function currentCotTimestamp() as String {
        var info = Time.Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        return info.year.format("%04d") + "-" + info.month.format("%02d") + "-" + info.day.format("%02d")
            + "T" + info.hour.format("%02d") + ":" + info.min.format("%02d") + ":" + info.sec.format("%02d") + "Z";
    }

    function compareCotTimestamp(left as String, right as String) as Number {
        var starts = [0, 5, 8, 11, 14, 17];
        var lengths = [4, 2, 2, 2, 2, 2];
        for (var index = 0; index < starts.size(); index++) {
            if (left.length() < starts[index] + lengths[index]
                    || right.length() < starts[index] + lengths[index]) {
                if (left.length() < right.length()) { return -1; }
                if (left.length() > right.length()) { return 1; }
                return left.equals(right) ? 0 : -1;
            }
            var leftPart = left.substring(starts[index], starts[index] + lengths[index]).toNumber();
            var rightPart = right.substring(starts[index], starts[index] + lengths[index]).toNumber();
            if (leftPart < rightPart) { return -1; }
            if (leftPart > rightPart) { return 1; }
        }
        return 0;
    }

    function incomingPointTitle(id as String) as String {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary)) { return id; }
        var title = details.get("callSign") as String;
        title = title.length() > 0 ? title : details.get("uid") as String;
        return details.get("isAlert") == true
            ? "(" + WatchUi.loadResource(Rez.Strings.IncomingAlertLabel) + ") " + title : title;
    }

    function incomingPointDetailLabel(id as String) as String {
        var details = incomingDetails.get(id);
        var detailsDict = details instanceof Dictionary ? details as Dictionary : null;
        if (detailsDict != null && detailsDict.get("isAlert") == true) {
            var category = detailsDict.get("category");
            var label = category instanceof String && (category as String).length() > 0
                ? category as String : application.text(Rez.Strings.IncomingAlertUnknownCategory);
            var location = pointLocations.get(id);
            if (detailsDict.get("stale") == true) {
                label = label + " · " + application.text(location == null
                    ? Rez.Strings.IncomingAlertStale : Rez.Strings.IncomingAlertStaleLastKnown);
            }
            if (location == null) {
                label = label + " · " + application.text(Rez.Strings.IncomingAlertNoLocation);
            }
            if (currentPosition == null || location == null) { return label; }
            return label + " · " + application.formatDistance(distanceMeters(currentPosition, location), 0);
        }
        var affiliation = Rez.Strings.TextUnknownPoint;
        if (details instanceof Dictionary) {
            var cotType = details.get("type");
            if (cotType instanceof String && (cotType as String).length() >= 3) {
                var code = (cotType as String).substring(2, 3);
                if (code.equals("f") || code.equals("a")) { affiliation = Rez.Strings.TextFriendlyPoint; }
                else if (code.equals("h") || code.equals("s") || code.equals("j") || code.equals("k")) {
                    affiliation = Rez.Strings.TextHostilePoint;
                } else if (code.equals("n")) { affiliation = Rez.Strings.TextObstaclePoint; }
            }
        }
        var label = application.text(affiliation);
        var location = pointLocations.get(id);
        if (currentPosition == null || location == null) { return label; }
        return label + " · " + application.formatDistance(distanceMeters(currentPosition, location), 0);
    }

    function markIncomingPointsSeen() as Void {
        if (pendingIncomingPoints.size() == 0) { return; }
        pendingIncomingPoints = [];
        application.refreshIncomingPointCount();
    }

    function acknowledgeIncomingPoint(id as String) as Boolean {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary) || details.get("isPoint") != true) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient == null || !takClient.queuePointReply(details.get("senderUID") as String,
                details.get("uid") as String, "Roger, bloodhounding to " + incomingPointTitle(id))) { return false; }
        setBloodhoundPoint(null);
        toggleBloodhound(id);
        pendingIncomingPoints.remove(id);
        application.refreshIncomingPointCount();
        return true;
    }

    function markIncomingPointInPosition(id as String) as Boolean {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary) || bloodhoundPointId == null || !bloodhoundPointId.equals(id)) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient == null || !takClient.queuePointReply(details.get("senderUID") as String,
                details.get("uid") as String, "In Position at " + incomingPointTitle(id))) { return false; }
        removeIncomingPoint(id, true);
        return true;
    }

    function removeAllIncomingPoints() as Void {
        for (var i = incomingIds.size() - 1; i >= 0; i--) {
            var id = incomingIds[i] as String;
            var details = incomingDetails.get(id);
            if (details instanceof Dictionary && details.get("isPoint") == true) {
                removeIncomingPoint(id, true);
            }
        }
        var routes = routeStore.routes.slice(0, routeStore.routes.size());
        for (var r = 0; r < routes.size(); r++) {
            removeLocalRoute(routeStore.routeId(routes[r]));
        }
        refreshBloodhoundPicker();
    }

    function removeIncomingPoint(id as String, dismiss as Boolean) as Void {
        var details = incomingDetails.get(id);
        if (details instanceof Dictionary && details.get("isUser") == true) {
            userSourceStates.remove(details.get("uid"));
        }
        if (dismiss && details instanceof Dictionary) {
            if (dismissedIncomingPoints.size() >= MAP_RETAINED_LIMIT) {
                dismissedIncomingPoints.remove(dismissedIncomingPoints.keys()[0]);
            }
            if (details.get("isAlert") == true) {
                dismissedIncomingPoints.put(id, {
                    "latestRevision" => details.get("revision"),
                    "removedAt" => Time.now().value(),
                    "isAlert" => true
                });
            } else {
                dismissedIncomingPoints.put(id, {
                    "revision" => details.get("revision"),
                    "removedAt" => Time.now().value(),
                    "isAlert" => false
                });
            }
            saveIncomingAlertPersistence();
        }
        markers.remove(id);
        pointLocations.remove(id);
        incomingLastSeen.remove(id);
        incomingDetails.remove(id);
        incomingIds.remove(id);
        pendingIncomingPoints.remove(id);
        if (application != null) { application.refreshIncomingPointCount(); }
        if (bloodhoundPointId != null && bloodhoundPointId.equals(id)) {
            bloodhoundPointId = null;
            bloodhoundProximityNotified = false;
            notifyBloodhoundChanged();
        }
        markersDirty = true;
        refreshBloodhoundPicker();
        WatchUi.requestUpdate();
    }

    function removeIncomingAlertSource(source as String) as Void {
        var users = userSourceStates.keys();
        for (var userIndex = 0; userIndex < users.size(); userIndex++) {
            removeIncomingUserSource(users[userIndex] as String, source);
        }
        var alertIds = alertSourceStates.keys();
        for (var index = 0; index < alertIds.size(); index++) {
            var markerId = alertIds[index] as String;
            var sources = alertSourceStates.get(markerId);
            if (!(sources instanceof Dictionary) || !(sources as Dictionary).hasKey(source)) { continue; }
            (sources as Dictionary).remove(source);
            if ((sources as Dictionary).size() == 0) { alertSourceStates.remove(markerId); }
            rebuildVisibleAlert(markerId);
        }
    }

    function trimMapText(value as String) as String {
        while (value.length() > 0 && isMapWhitespace(value.substring(0, 1))) { value = value.substring(1, value.length()); }
        while (value.length() > 0 && isMapWhitespace(value.substring(value.length() - 1, value.length()))) { value = value.substring(0, value.length() - 1); }
        return value;
    }

    function isMapWhitespace(value as String) as Boolean {
        return value.equals(" ") || value.equals("\t") || value.equals("\r") || value.equals("\n");
    }

    function normalizeMapGroup(value as String) as String {
        return trimMapText(value).toLower();
    }

    function isUserCotType(cotType as String) as Boolean {
        return cotType.find("a-") == 0 && cotType.find("-G-U-C") != null;
    }

    function incomingUserGroups(isTeam as Boolean) as Array<Dictionary> {
        var names = {};
        var counts = {};
        for (var index = 0; index < incomingIds.size(); index++) {
            var markerId = incomingIds[index] as String;
            var details = incomingDetails.get(markerId);
            if (!(details instanceof Dictionary)) { continue; }
            if (details.get("isPoint") == true) { continue; }
            if (details.get("isUser") != true || isSelfIncomingUser(details as Dictionary)) { continue; }
            var value = (details as Dictionary).get(isTeam ? "team" : "role");
            if (!(value instanceof String)) { continue; }
            var displayName = trimMapText(value as String);
            if (displayName.length() == 0) { continue; }
            var key = normalizeMapGroup(displayName);
            names.put(key, names.hasKey(key) ? names.get(key) : displayName);
            counts.put(key, counts.hasKey(key) ? (counts.get(key) as Number) + 1 : 1);
        }
        var groups = [];
        var keys = names.keys();
        for (var keyIndex = 0; keyIndex < keys.size(); keyIndex++) {
            var key = keys[keyIndex] as String;
            var name = names.get(key);
            groups.add({"key" => key, "name" => name == null ? key : name.toString(), "count" => counts.get(key) as Number});
        }
        return groups;
    }

    function isIncomingUserVisible(markerId as String) as Boolean {
        var details = incomingDetails.get(markerId);
        if (!(details instanceof Dictionary)) { return true; }
        if (details.get("isPoint") == true) { return true; }
        if (details.get("isUser") != true) { return true; }
        if (isSelfIncomingUser(details as Dictionary)) { return false; }
        var teamValue = (details as Dictionary).get("team");
        var roleValue = (details as Dictionary).get("role");
        var team = teamValue instanceof String ? teamValue as String : "";
        var role = roleValue instanceof String ? roleValue as String : "";
        return !isMapGroupHidden(hiddenMapTeams, team) && !isMapGroupHidden(hiddenMapRoles, role);
    }

    function sortPointOrderNewestFirst() as Void {
        for (var index = 1; index < pointOrder.size(); index++) {
            var pointId = pointOrder[index] as String;
            var pointTime = (pointDetails.get(pointId) as Dictionary).get("createdAt") as Number;
            var cursor = index;
            while (cursor > 0) {
                var previousId = pointOrder[cursor - 1] as String;
                var previousTime = (pointDetails.get(previousId) as Dictionary).get("createdAt") as Number;
                if (previousTime >= pointTime) { break; }
                pointOrder[cursor] = previousId;
                cursor -= 1;
            }
            pointOrder[cursor] = pointId;
        }
    }

    function isSelfIncomingUser(details as Dictionary) as Boolean {
        if (application == null) { return false; }
        var deviceId = System.getDeviceSettings().uniqueIdentifier;
        var uid = details.get("uid");
        return deviceId != null && uid instanceof String && (uid as String).equals(deviceId);
    }

    function isSelfIncomingAlert(uid as String, metadata as Dictionary) as Boolean {
        if (!(metadata instanceof Dictionary)) { return false; }
        var sender = incomingPointSender(metadata);
        var deviceId = System.getDeviceSettings().uniqueIdentifier;
        if (deviceId != null && sender.length() > 0 && sender.equals(deviceId)) { return true; }
        if (deviceId != null && uid != null && uid.toString().equals(deviceId)) { return true; }
        if (application != null) {
            var callsign = metadata.get("callSign");
            if (callsign == null) { callsign = metadata.get("callsign"); }
            var contact = metadata.get("contact");
            if (callsign == null && contact instanceof Dictionary) {
                callsign = (contact as Dictionary).get("callsign");
            }
            var ownCallsign = application.getCallsign();
            if (callsign instanceof String && ownCallsign.length() > 0
                    && normalizeMapGroup(callsign as String).equals(normalizeMapGroup(ownCallsign))) {
                return true;
            }
        }
        if (takClient != null && takClient.isLocalAlertUid(uid)) { return true; }
        return false;
    }

    function compareIncomingRevision(left as String, right as String) as Number {
        if (left == null || left.length() == 0) {
            return right == null || right.length() == 0 ? 0 : -1;
        }
        if (right == null || right.length() == 0) {
            return 1;
        }
        if (left.equals(right)) { return 0; }
        if (left.length() >= 19 && right.length() >= 19
                && left.substring(4, 5).equals("-") && right.substring(4, 5).equals("-")
                && left.substring(10, 11).equals("T") && right.substring(10, 11).equals("T")) {
            return compareCotTimestamp(left, right);
        }
        var leftNumber = revisionNumericValue(left);
        var rightNumber = revisionNumericValue(right);
        if (leftNumber != null && rightNumber != null) {
            if (leftNumber < rightNumber) { return -1; }
            if (leftNumber > rightNumber) { return 1; }
            return 0;
        }
        if (left.length() < right.length()) { return -1; }
        if (left.length() > right.length()) { return 1; }
        return 0;
    }

    function revisionNumericValue(value as String) as Number? {
        var digits = "";
        for (var i = 0; i < value.length(); i++) {
            var chr = value.substring(i, i + 1);
            if (chr.equals("0") || chr.equals("1") || chr.equals("2") || chr.equals("3")
                    || chr.equals("4") || chr.equals("5") || chr.equals("6")
                    || chr.equals("7") || chr.equals("8") || chr.equals("9")) {
                digits += chr;
            }
        }
        if (digits.length() == 0) { return null; }
        return digits.toNumber();
    }

    function isMapGroupHidden(hiddenGroups as Array<String>, value as String) as Boolean {
        var key = normalizeMapGroup(value);
        if (key.length() == 0) { return false; }
        for (var index = 0; index < hiddenGroups.size(); index++) {
            if ((hiddenGroups[index] as String).equals(key)) { return true; }
        }
        return false;
    }

    function isMapGroupHiddenForKind(isTeam as Boolean, value as String) as Boolean {
        return isMapGroupHidden(isTeam ? hiddenMapTeams : hiddenMapRoles, value);
    }

    function toggleMapGroup(isTeam as Boolean, value as String) as Void {
        var key = normalizeMapGroup(value);
        if (key.length() == 0) { return; }
        var groups = isTeam ? hiddenMapTeams : hiddenMapRoles;
        var found = false;
        for (var index = 0; index < groups.size(); index++) {
            if ((groups[index] as String).equals(key)) {
                found = true;
            }
        }
        if (found) { groups.remove(key); }
        else { groups.add(key); }
        if (isTeam) {
            hiddenMapTeams = groups;
            Application.Storage.setValue("hiddenMapTeams", hiddenMapTeams);
        } else {
            hiddenMapRoles = groups;
            Application.Storage.setValue("hiddenMapRoles", hiddenMapRoles);
        }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function areMapButtonsVisible() as Boolean {
        return mapButtonsVisible;
    }

    function setMapButtonsVisible(visible as Boolean) as Void {
        mapButtonsVisible = visible;
        Application.Storage.setValue("mapButtonsVisible", visible);
        WatchUi.requestUpdate();
    }

    function centerOn(position) {
        var center = [0.0, 0.0];
        hasInitialPosition = position != null;
        if (position != null) {
            center = position.toDegrees();
        }
        var span = 0.05;
        mapTopLeft = new Position.Location({:latitude => center[0] + span, :longitude => center[1] - span, :format => :degrees});
        mapBottomRight = new Position.Location({:latitude => center[0] - span, :longitude => center[1] + span, :format => :degrees});
        applyMapVisibleArea();
    }

    function applyMapVisibleArea() as Void {
        setMapVisibleArea(mapTopLeft, mapBottomRight);
        mapAreaDirty = false;
        if (currentPosition == null) { markersDirty = true; }
    }

    function onUpdate(dc) {
        if (mapAreaDirty) {
            setMapVisibleArea(mapTopLeft, mapBottomRight);
            mapAreaDirty = false;
            if (currentPosition == null) { markersDirty = true; }
        }
        if (markersDirty) {
            var currentMarkers = markerArray();
            clear();
            if (currentMarkers.size() > 0) {
                setMapMarker(currentMarkers);
            }
            markersDirty = false;
        }
        WatchUi.MapView.onUpdate(dc);
        drawRoutes(dc);
        drawIncomingCircles(dc);
        drawTeamOverlay(dc);
        drawIncomingUserOverlays(dc);
        if (mapButtonsVisible) {
            var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
            drawControl(dc, controlMargin, top, "+");
            drawCenterControl(dc, controlMargin, top + controlSize + controlGap);
            drawControl(dc, controlMargin, top + (controlSize + controlGap) * 2, "-");
        }
        drawLayersControl(dc);
        if (mapButtonsVisible) {
            drawChannelsControl(dc);
        }
        drawBackControl(dc, screenWidth - controlSize - controlMargin, (screenHeight - controlSize) / 2);
        drawBloodhound(dc);
    }

    function drawLayersControl(dc) as Void {
        var x = (screenWidth - controlSize) / 2;
        var y = controlMargin;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawLine(x + 9, y + 12, x + 30, y + 12);
        dc.drawLine(x + 9, y + 20, x + 30, y + 20);
        dc.drawLine(x + 9, y + 28, x + 30, y + 28);
    }

    function drawChannelsControl(dc) as Void {
        var x = screenWidth / 2 + controlSize / 2 + controlGap;
        var y = controlMargin + 24;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawLine(x + 13, y + 13, x + 27, y + 13);
        dc.drawLine(x + 13, y + 13, x + 20, y + 27);
        dc.drawLine(x + 27, y + 13, x + 20, y + 27);
        dc.drawCircle(x + 12, y + 12, 3);
        dc.drawCircle(x + 28, y + 12, 3);
        dc.drawCircle(x + 20, y + 28, 3);
    }

    function drawIncomingUserOverlays(dc) as Void {
        for (var index = 0; index < drawnPointIds.size(); index++) {
            var markerId = drawnPointIds[index];
            var details = incomingDetails.get(markerId);
            if (!(details instanceof Dictionary) || details.get("isAlert") == true || !isIncomingUserVisible(markerId)) { continue; }
            var generic = details.get("generic") == true;
            if (!generic && (details.get("isPoint") == true || details.get("isUser") != true)) { continue; }
            var location = pointLocations.get(markerId);
            if (location == null) { continue; }
            var screen = pointScreenPosition(location);
            var markerX = screen[0].toNumber();
            var markerY = screen[1].toNumber();
            if (markerX < 0 || markerX >= screenWidth || markerY < 0 || markerY >= screenHeight) { continue; }
            var team = (details as Dictionary).get("team").toString();
            var color = generic ? incomingAffiliationColor(details.get("type") as String) : teamColorValue(trimMapText(team));
            if (generic && drawIncomingCotSymbol(dc, markerX, markerY, details.get("type") as String, color)) { continue; }
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(markerX, markerY, 7);
            drawTeamDot(dc, markerX, markerY, color);
        }
    }

    function drawIncomingCotSymbol(dc, x, y, cotType as String, color as Number) as Boolean {
        var symbol = incomingCotSymbol(cotType);
        if (symbol.length() == 0) { return false; }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 11);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (symbol.equals("fixed")) {
            dc.drawLine(x, y - 8, x, y + 8);
            dc.drawLine(x - 8, y + 2, x, y - 3);
            dc.drawLine(x, y - 3, x + 8, y + 2);
            dc.drawLine(x - 4, y + 8, x, y + 5);
            dc.drawLine(x, y + 5, x + 4, y + 8);
        } else if (symbol.equals("rotary")) {
            dc.drawLine(x - 8, y - 6, x + 8, y - 6);
            dc.drawLine(x, y - 6, x, y + 1);
            dc.drawLine(x - 4, y + 1, x + 4, y + 1);
            dc.drawLine(x - 4, y + 1, x - 4, y + 5);
            dc.drawLine(x + 4, y + 1, x + 4, y + 5);
            dc.drawLine(x - 6, y + 8, x + 6, y + 8);
        } else if (symbol.equals("uav")) {
            dc.drawLine(x - 6, y - 6, x + 6, y + 6);
            dc.drawLine(x - 6, y + 6, x + 6, y - 6);
            dc.drawCircle(x - 6, y - 6, 3);
            dc.drawCircle(x + 6, y - 6, 3);
            dc.drawCircle(x - 6, y + 6, 3);
            dc.drawCircle(x + 6, y + 6, 3);
        } else if (symbol.equals("sea")) {
            dc.drawLine(x - 8, y + 1, x + 8, y + 1);
            dc.drawLine(x - 8, y + 1, x - 4, y + 7);
            dc.drawLine(x - 4, y + 7, x + 4, y + 7);
            dc.drawLine(x + 4, y + 7, x + 8, y + 1);
            dc.drawLine(x, y + 1, x, y - 8);
            dc.drawLine(x, y - 8, x + 6, y - 2);
            dc.drawLine(x + 6, y - 2, x, y - 2);
        } else if (symbol.equals("vehicle")) {
            dc.drawLine(x - 8, y + 4, x - 8, y - 3);
            dc.drawLine(x - 8, y - 3, x + 8, y - 3);
            dc.drawLine(x + 8, y - 3, x + 8, y + 4);
            dc.drawLine(x - 8, y + 4, x + 8, y + 4);
            dc.fillCircle(x - 5, y + 7, 2);
            dc.fillCircle(x + 5, y + 7, 2);
        } else {
            dc.drawCircle(x, y, 5);
            dc.drawLine(x - 9, y, x + 9, y);
            dc.drawLine(x, y - 9, x, y + 9);
        }
        dc.setPenWidth(1);
        return true;
    }

    function drawIncomingCircles(dc) as Void {
        var count = 0;
        for (var index = 0; index < drawnPointIds.size() && count < 16; index++) {
            var id = drawnPointIds[index];
            var details = incomingDetails.get(id);
            var radius = details instanceof Dictionary ? details.get("circleRadius") : null;
            if (!(radius instanceof Float) || !pointLocations.hasKey(id)) { continue; }
            count++;
            var center = pointLocations.get(id).toDegrees();
            var cosLat = Math.cos(Math.toRadians(center[0]));
            if (cosLat.abs() < 0.01) { continue; }
            var previous = [];
            dc.setColor(incomingAffiliationColor(details.get("type") as String), Graphics.COLOR_TRANSPARENT);
            for (var segment = 0; segment <= 32; segment++) {
                var angle = segment * 2 * Math.PI / 32;
                var lat = center[0] + radius * Math.cos(angle) / 111195.0;
                var lon = center[1] + radius * Math.sin(angle) / (111195.0 * cosLat);
                var screen = routeScreenPoint({"lat" => lat, "lon" => lon});
                if (screen != null && previous.size() > 0) {
                    var line = clippedRouteSegment(previous, screen, screenWidth - 1, screenHeight - 1);
                    if (line != null) {
                        dc.drawLine(line[0].toNumber(), line[1].toNumber(), line[2].toNumber(), line[3].toNumber());
                    }
                }
                previous = screen == null ? [] : screen;
            }
        }
    }

    function drawTeamOverlay(dc) as Void {
        if (application == null || currentPosition == null || mapTopLeft == null || mapBottomRight == null) {
            return;
        }
        var screen = pointScreenPosition(currentPosition);
        var markerX = screen[0].toNumber();
        var markerY = screen[1].toNumber();
        if (markerX < 0 || markerX >= screenWidth || markerY < 0 || markerY >= screenHeight) {
            return;
        }

        var teamColor = teamColorValue(application.getMyTeamColor());
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(markerX, markerY, 8);
        drawTeamDot(dc, markerX, markerY, teamColor);

        if (isBloodhoundActive()) {
            var bearing = Math.toRadians(bearingDegrees(currentPosition, pointLocations.get(bloodhoundPointId)));
            var directionX = Math.sin(bearing);
            var directionY = -Math.cos(bearing);
            var tipX = (markerX + directionX * 28).toNumber();
            var tipY = (markerY + directionY * 28).toNumber();
            var baseX = tipX - directionX * 8;
            var baseY = tipY - directionY * 8;
            var sideX = -directionY * 5;
            var sideY = directionX * 5;
            dc.setColor(teamColor, teamColor);
            dc.drawLine(markerX, markerY, tipX, tipY);
            dc.drawLine(tipX, tipY, (baseX + sideX).toNumber(), (baseY + sideY).toNumber());
            dc.drawLine(tipX, tipY, (baseX - sideX).toNumber(), (baseY - sideY).toNumber());
        }
    }

    function drawTeamDot(dc, x, y, color) as Void {
        dc.setColor(color, color);
        dc.fillCircle(x, y, 5);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 5);
    }

    function drawBloodhound(dc) as Void {
        if (bloodhoundPointId == null || pointLocations.hasKey(bloodhoundPointId) == false) {
            return;
        }
        var title = getBloodhoundTitle();
        var panelHeight = 58;
        var panelTop = screenHeight - panelHeight - 4;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(4, panelTop, screenWidth - 8, panelHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(4, panelTop, screenWidth - 8, panelHeight);
            dc.drawText(screenWidth / 2, panelTop + 4, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        if (followingRouteId != null) {
            dc.drawText(screenWidth / 2, panelTop + 22, Graphics.FONT_XTINY, routeProgress(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenWidth / 2, panelTop + 40, Graphics.FONT_XTINY, routeRemainingLabel(), Graphics.TEXT_JUSTIFY_CENTER);
        } else if (currentPosition == null) {
                dc.drawText(screenWidth / 2, panelTop + 30, Graphics.FONT_XTINY, application.text(Rez.Strings.TextWaitingForLocation), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var target = pointLocations.get(bloodhoundPointId);
            var rangeMeters = distanceMeters(currentPosition, target).toNumber();
            var bearing = bearingDegrees(currentPosition, target).toNumber();
            dc.drawText(screenWidth / 2, panelTop + 22, Graphics.FONT_XTINY,
                application.text(Rez.Strings.TextRange) + " " + application.formatDistance(rangeMeters, 0), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenWidth / 2, panelTop + 40, Graphics.FONT_XTINY, application.text(Rez.Strings.TextBearing) + " " + bearing.toString() + " deg", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function isBloodhoundPanelAt(x, y) as Boolean {
        return isBloodhoundActive() && y >= screenHeight - 62 && y < screenHeight - 4 && x >= 4 && x < screenWidth - 4;
    }

    function showBloodhoundCancelMenu() as Void {
        if (bloodhoundPointId != null && incomingDetails.hasKey(bloodhoundPointId)) {
            showPointTypeMenu(bloodhoundPointId);
            return;
        }
        if (followingRouteId != null) { showRouteFollow(followingRouteId); return; }
        var menu = createMenu(application.text(Rez.Strings.TextBloodhoundCompass));
        addMenuEntry(menu, application.text(Rez.Strings.TextStopBloodhound), null, :cancelBloodhound);
        WatchUi.pushView(menu, new BloodhoundCancelDelegate(self), WatchUi.SLIDE_UP);
    }

    function distanceMeters(fromLocation, toLocation) {
        return RouteNavigation.distance(fromLocation, toLocation);
    }

    function bearingDegrees(fromLocation, toLocation) {
        var fromDegrees = fromLocation.toDegrees();
        var toDegrees = toLocation.toDegrees();
        var fromLat = Math.toRadians(fromDegrees[0]);
        var toLat = Math.toRadians(toDegrees[0]);
        var deltaLon = Math.toRadians(toDegrees[1] - fromDegrees[1]);
        var y = Math.sin(deltaLon) * Math.cos(toLat);
        var x = Math.cos(fromLat) * Math.sin(toLat) - Math.sin(fromLat) * Math.cos(toLat) * Math.cos(deltaLon);
        var bearing = Math.toDegrees(Math.atan2(y, x));
        while (bearing < 0) {
            bearing += 360;
        }
        while (bearing >= 360) {
            bearing -= 360;
        }
        return bearing;
    }

    function isBloodhoundActive() as Boolean {
        return bloodhoundPointId != null && pointLocations.hasKey(bloodhoundPointId);
    }

    function bloodhoundTargetIcon() {
        if (!isBloodhoundActive()) { return null; }
        return bloodhoundPointId instanceof String && bloodhoundPointId.find("route-point:") == 0
            ? Rez.Drawables.PickerRouteIcon : Rez.Drawables.PickerHoundIcon;
    }

    function getBloodhoundTitle() as String {
        if (followingRouteId != null) {
            var route = routeStore.route(followingRouteId);
            if (route != null) { return route.get("name") as String; }
        }
        if (bloodhoundPointId instanceof String) {
            var selected = routeStore.point(bloodhoundPointId);
            if (selected != null) { return routeStore.title(selected); }
        }
        if (bloodhoundPointId != null && incomingDetails.hasKey(bloodhoundPointId)) {
            return incomingPointTitle(bloodhoundPointId);
        }
        if (bloodhoundPointId == null || pointDetails.hasKey(bloodhoundPointId) == false) {
            return "Bloodhound";
        }
        var title = getPointText(bloodhoundPointId, "title");
        return title.equals("") ? "Bloodhound" : title;
    }

    function getBloodhoundRangeMeters() as Number {
        if (!isBloodhoundActive() || currentPosition == null) {
            return 0;
        }
        return distanceMeters(currentPosition, pointLocations.get(bloodhoundPointId)).toNumber();
    }

    function getBloodhoundBearingDegrees() as Number {
        if (!isBloodhoundActive() || currentPosition == null) {
            return 0;
        }
        return bearingDegrees(currentPosition, pointLocations.get(bloodhoundPointId)).toNumber();
    }

    function showCoordinateMenu(title as String, location) as Void {
        var menu = createMenu(title);
        var degrees = location.toDegrees();
        addMenuEntry(menu, "Lat: " + degrees[0].format("%.5f"), null, :coordinates);
        addMenuEntry(menu, "Lon: " + degrees[1].format("%.5f"), null, :coordinates);
        addMenuEntry(menu, mgrsLabel(location), null, :coordinates);
        WatchUi.pushView(menu, new CoordinateMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function latLonLabel(location) as String {
        var degrees = location.toDegrees();
        return degrees[0].format("%.5f") + ", " + degrees[1].format("%.5f");
    }

    function mgrsLabel(location) as String {
        var degrees = location.toDegrees();
        return mgrsFromLatLon(degrees[0], degrees[1]);
    }

    function mgrsFromLatLon(latitude, longitude) as String {
        if (latitude < -80 || latitude > 84) {
            return "MGRS unavailable";
        }
        var zone = clamp(Math.floor((longitude + 180) / 6).toNumber() + 1, 1, 60);
        if (latitude >= 56 && latitude < 64 && longitude >= 3 && longitude < 12) {
            zone = 32;
        }
        if (latitude >= 72 && latitude < 84) {
            if (longitude >= 0 && longitude < 9) {
                zone = 31;
            } else if (longitude >= 9 && longitude < 21) {
                zone = 33;
            } else if (longitude >= 21 && longitude < 33) {
                zone = 35;
            } else if (longitude >= 33 && longitude < 42) {
                zone = 37;
            }
        }
        var band = latitudeBand(latitude);
        var utm = utmFromLatLon(latitude, longitude, zone);
        var easting = utm[0];
        var northing = utm[1];
        var column = clamp(Math.floor(easting / 100000).toNumber(), 1, 8);
        var northingBlock = Math.floor(northing / 100000).toNumber();
        var row = northingBlock - (Math.floor(northingBlock / 20).toNumber() * 20);
        var eastingRemainder = Math.floor(easting - (Math.floor(easting / 100000).toNumber() * 100000)).toNumber();
        var northingRemainder = Math.floor(northing - (Math.floor(northing / 100000).toNumber() * 100000)).toNumber();
        return zone.toString() + band + " " + eastingLetter(zone, column) + northingLetter(zone, row) + " " + pad5(eastingRemainder) + " " + pad5(northingRemainder);
    }

    function utmFromLatLon(latitude, longitude, zone) as Array {
        var a = 6378137.0;
        var eccSquared = 0.00669438;
        var k0 = 0.9996;
        var latRad = Math.toRadians(latitude);
        var lonRad = Math.toRadians(longitude);
        var lonOrigin = (zone - 1) * 6 - 180 + 3;
        var lonOriginRad = Math.toRadians(lonOrigin);
        var eccPrimeSquared = eccSquared / (1 - eccSquared);
        var sinLat = Math.sin(latRad);
        var cosLat = Math.cos(latRad);
        var tanLat = Math.tan(latRad);
        var sin2Lat = Math.sin(2 * latRad);
        var sin4Lat = Math.sin(4 * latRad);
        var sin6Lat = Math.sin(6 * latRad);
        var n = a / Math.sqrt(1 - eccSquared * sinLat * sinLat);
        var t = tanLat * tanLat;
        var c = eccPrimeSquared * cosLat * cosLat;
        var aa = cosLat * (lonRad - lonOriginRad);
        var ecc2 = Math.pow(eccSquared, 2);
        var ecc3 = Math.pow(eccSquared, 3);
        var m = a * ((1 - eccSquared / 4 - 3 * ecc2 / 64 - 5 * ecc3 / 256) * latRad
            - (3 * eccSquared / 8 + 3 * ecc2 / 32 + 45 * ecc3 / 1024) * sin2Lat
            + (15 * ecc2 / 256 + 45 * ecc3 / 1024) * sin4Lat
            - (35 * ecc3 / 3072) * sin6Lat);
        var aa2 = aa * aa;
        var t2 = t * t;
        var c2 = c * c;
        var easting = k0 * n * (aa + (1 - t + c) * Math.pow(aa, 3) / 6 + (5 - 18 * t + t2 + 72 * c - 58 * eccPrimeSquared) * Math.pow(aa, 5) / 120) + 500000;
        var northing = k0 * (m + n * tanLat * (aa2 / 2 + (5 - t + 9 * c + 4 * c2) * Math.pow(aa, 4) / 24 + (61 - 58 * t + t2 + 600 * c - 330 * eccPrimeSquared) * Math.pow(aa, 6) / 720));
        if (latitude < 0) {
            northing += 10000000;
        }
        return [easting, northing];
    }

    function latitudeBand(latitude) as String {
        var index = clamp(Math.floor((latitude + 80) / 8).toNumber(), 0, 19);
        return "CDEFGHJKLMNPQRSTUVWX".substring(index, index + 1);
    }

    function eastingLetter(zone as Number, column as Number) as String {
        var set = (zone - 1) % 3;
        var letters = set == 0 ? "ABCDEFGH" : set == 1 ? "JKLMNPQR" : "STUVWXYZ";
        return letters.substring(column - 1, column);
    }

    function northingLetter(zone as Number, row as Number) as String {
        var letters = (zone % 2) == 1 ? "ABCDEFGHJKLMNPQRSTUV" : "FGHJKLMNPQRSTUVABCDE";
        return letters.substring(row, row + 1);
    }

    function pad5(value as Number) as String {
        var text = value.toString();
        while (text.length() < 5) {
            text = "0" + text;
        }
        return text;
    }

    function clamp(value as Number, minimum as Number, maximum as Number) as Number {
        if (value < minimum) {
            return minimum;
        } else if (value > maximum) {
            return maximum;
        }
        return value;
    }

    function drawControl(dc, x, y, label) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawText(x + controlSize / 2, y + 4, Graphics.FONT_LARGE, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawCenterControl(dc, x, y) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        var centerX = x + controlSize / 2;
        var centerY = y + controlSize / 2;
        dc.drawLine(centerX, centerY - 12, centerX, centerY + 12);
        dc.drawLine(centerX - 12, centerY, centerX + 12, centerY);
        dc.drawCircle(centerX, centerY, 5);
    }

    function drawBackControl(dc, x, y) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        var centerX = x + controlSize / 2;
        var centerY = y + controlSize / 2;
        dc.drawLine(centerX + 10, centerY - 12, centerX - 8, centerY);
        dc.drawLine(centerX - 8, centerY, centerX + 10, centerY + 12);
    }

    function dropAtCurrentLocation() as Boolean {
        return dropAtCurrentLocationAs(defaultPointType);
    }

    function getDefaultPointType() as Symbol {
        return defaultPointType;
    }

    function dropAtCurrentLocationAs(type as Symbol) as Boolean {
        application.requestPositionForAction("self_marker");
        var info = Position.getInfo();
        var droppedAt = utcTimeLabel(Time.now());
        var location = info != null && info.accuracy >= Position.QUALITY_USABLE
            && application.isLocationServicesEnabled() ? info.position : null;
        return queuePoint(location, type, newPointTitle(droppedAt), droppedAt, true);
    }

    function hasPoints() as Boolean {
        if (pointOrder.size() > 0 || pendingSelfPoints.size() > 0) { return true; }
        if (takClient != null) {
            for (var i = 0; i < takClient.pointReplies.replies.size(); i++) {
                var entry = takClient.pointReplies.replies[i];
                if (entry.get("msgType").equals("marker")) { return true; }
            }
        }
        return false;
    }

    function snapToSelf() {
        application.requestPositionForAction("map");
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            centerOn(info.position);
            WatchUi.requestUpdate();
        }
    }

    function dropAtScreen(x, y) {
        if (mapTopLeft == null || mapBottomRight == null) {
            return;
        }
        if (x < 0 || x >= screenWidth || y < 0 || y >= screenHeight || isControlAt(x, y)) {
            return;
        }
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var xRatio = x.toFloat() / screenWidth.toFloat();
        var yRatio = y.toFloat() / screenHeight.toFloat();
        var latitude = topLeft[0] + (bottomRight[0] - topLeft[0]) * yRatio;
        var longitude = topLeft[1] + (bottomRight[1] - topLeft[1]) * xRatio;
        var droppedAt = utcTimeLabel(Time.now());
        addPoint(new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees}), defaultPointType, newPointTitle(droppedAt), droppedAt);
        WatchUi.requestUpdate();
    }

    function isControlAt(x, y) {
        return isLayersControlAt(x, y) || (mapButtonsVisible && (isChannelsControlAt(x, y) || isZoomInControlAt(x, y) || isZoomOutControlAt(x, y) || isCenterControlAt(x, y))) || isBackControlAt(x, y);
    }

    function isLayersControlAt(x, y) as Boolean {
        var left = (screenWidth - controlSize) / 2;
        return x >= left && x < left + controlSize && y >= controlMargin && y < controlMargin + controlSize;
    }

    function isChannelsControlAt(x, y) as Boolean {
        var left = screenWidth / 2 + controlSize / 2 + controlGap;
        var top = controlMargin + 24;
        return x >= left && x < left + controlSize && y >= top && y < top + controlSize;
    }

    function showLayersMenu() as Void {
        var menu = buildMapLayersMenu(self);
        WatchUi.pushView(menu, new MapLayersMenuDelegate(self, menu), WatchUi.SLIDE_DOWN);
    }

    function isZoomInControlAt(x, y) {
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
        return x >= controlMargin && x < controlMargin + controlSize && y >= top && y < top + controlSize;
    }

    function isZoomOutControlAt(x, y) {
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2 + (controlSize + controlGap) * 2;
        return x >= controlMargin && x < controlMargin + controlSize && y >= top && y < top + controlSize;
    }

    function isCenterControlAt(x, y) {
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2 + controlSize + controlGap;
        return x >= controlMargin && x < controlMargin + controlSize && y >= top && y < top + controlSize;
    }

    function isBackControlAt(x, y) {
        var left = screenWidth - controlSize - controlMargin;
        var top = (screenHeight - controlSize) / 2;
        return x >= left && x < left + controlSize && y >= top && y < top + controlSize;
    }

    function addPoint(location, type, label, droppedAt as String) as Boolean {
        return queuePoint(location, type, label, droppedAt, false);
    }

    function queuePoint(location, type, label, droppedAt as String, atSelf as Boolean) as Boolean {
        label = trimNewPointTitle(label as String);
        var id = "point-" + nextPointNumber.toString();
        if (takClient == null) { return false; }
        var phoneOwned = atSelf && takClient.phoneLocationSupported;
        var previousPending = pendingSelfPoints.slice(0, pendingSelfPoints.size());
        if (phoneOwned && location == null) {
            expirePendingSelfPoints();
            if (pendingSelfPoints.size() >= 20) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.PointReplyQueueFull), null);
                return false;
            }
            pendingSelfPoints.add({"id" => id, "type" => typeToString(type), "title" => label,
                "droppedAt" => droppedAt, "createdAt" => Time.now().value()});
            if (!takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints)) {
                pendingSelfPoints = previousPending;
                return false;
            }
        }
        if (!(atSelf ? takClient.sendSelfMarker(id, location, type, label, "")
                : takClient.sendMarker(id, location, type, label, ""))) {
            pendingSelfPoints = previousPending;
            if (phoneOwned && location == null) { takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints); }
            return false;
        }
        nextPointNumber += 1;
        Application.Storage.setValue("nextPointNumber", nextPointNumber);
        defaultPointType = type;
        Application.Storage.setValue("defaultPointType", typeToString(type));
        if (location != null) {
            storeResolvedPoint(id, location, type, label, droppedAt, phoneOwned ? "phone" : "", "");
        }
        return true;
    }

    function saveResolvedPoint(id as String, location, type, label, droppedAt as String) as Void {
        storeResolvedPoint(id, location, type, label, droppedAt, "", "");
    }

    function storeResolvedPoint(id as String, location, type, label, droppedAt as String,
            source as String, revision as String) as Void {
        markers.put(id, createPointMarker(location, type, label));
        pointLocations.put(id, location);
        var localInfo = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var localTime = localInfo.hour.format("%02d") + ":" + localInfo.min.format("%02d");
        pointDetails.put(id, {"type" => type, "title" => label, "remark" => "", "droppedAt" => droppedAt,
            "localTime" => localTime, "createdAt" => Time.now().value(),
            "locationSource" => source, "phoneRevision" => revision});
        var newestFirst = [id];
        for (var orderIndex = 0; orderIndex < pointOrder.size(); orderIndex++) {
            newestFirst.add(pointOrder[orderIndex]);
        }
        pointOrder = newestFirst;
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
    }

    function resolvePendingPoints(location as Position.Location) as Void {
        if (takClient == null) { return; }
        expirePendingSelfPoints();
        for (var pendingIndex = 0; pendingIndex < pendingSelfPoints.size(); pendingIndex++) {
            var pending = pendingSelfPoints[pendingIndex];
            var id = pending.get("id") as String;
            if (!pointLocations.hasKey(id)) {
                storeResolvedPoint(id, location, typeFromString(pending.get("type") as String),
                    pending.get("title"), pending.get("droppedAt") as String, "phone", "");
            }
        }
        if (pendingSelfPoints.size() > 0) {
            pendingSelfPoints = [];
            takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints);
        }
        takClient.expirePointReplies();
        for (var i = 0; i < takClient.pointReplies.replies.size(); i++) {
            var entry = takClient.pointReplies.replies[i];
            var payload = entry.get("payload") as Dictionary;
            if (!entry.get("msgType").equals("marker") || payload.get("lat") != null) { continue; }
            var source = payload.get("locationSource");
            if (source instanceof String && source.equals("phone")) { continue; }
            var degrees = location.toDegrees();
            payload.put("lat", degrees[0]);
            payload.put("lon", degrees[1]);
            var id = payload.get("localId") as String;
            var cotType = payload.get("type").toString();
            var type = cotType.find("a-h-") == 0 ? :hostile : cotType.find("a-f-") == 0 ? :friendly : cotType.find("a-n-") == 0 ? :neutral : :unknown;
            if (!pointLocations.hasKey(id)) {
                saveResolvedPoint(id, location, type, payload.get("title").toString(), utcTimeLabel(Time.now()));
            } else {
                pointLocations.put(id, location);
                markers.put(id, createPointMarker(location, type, payload.get("title").toString()));
                markersDirty = true;
                savePoints();
            }
        }
        takClient.savePointReplies();
        takClient.flushPointReplies();
    }

    function expirePendingSelfPoints() as Void {
        var now = Time.now().value();
        for (var i = pendingSelfPoints.size() - 1; i >= 0; i--) {
            var created = pendingSelfPoints[i].get("createdAt") as Number;
            if (created > now || now - created >= 86400) {
                pendingSelfPoints.remove(pendingSelfPoints[i]);
                System.println("Pending self marker expired before a watch fix");
            }
        }
    }

    function newPointTitle(droppedAt as String) as String {
        var callsign = application.getCallsign();
        return callsign.length() == 0 ? droppedAt : callsign + "_" + droppedAt;
    }

    function trimNewPointTitle(value as String) as String {
        var chars = value.toCharArray();
        var end = chars.size();
        while (end > 0) {
            var code = chars[end - 1].toNumber();
            if (!((code >= 9 && code <= 13) || code == 0x20 || code == 0x85
                    || code == 0xa0 || code == 0x1680 || (code >= 0x2000 && code <= 0x200a)
                    || code == 0x2028 || code == 0x2029 || code == 0x202f
                    || code == 0x205f || code == 0x3000)) { break; }
            end--;
        }
        return value.substring(0, end);
    }

    function utcTimeLabel(moment as Time.Moment) as String {
        var timeInfo = Time.Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return timeInfo.hour.format("%02d") + timeInfo.min.format("%02d") + timeInfo.sec.format("%02d") + "Z";
    }

    function iconForType(type) {
        return WatchUi.loadResource(type == :friendly ? Rez.Drawables.FriendlyIcon
            : type == :hostile ? Rez.Drawables.HostileIcon
            : type == :neutral ? Rez.Drawables.NeutralIcon : Rez.Drawables.UnknownIcon);
    }

    function createPointMarker(location, type, label) {
        var marker = new WatchUi.MapMarker(location);
        var icon = iconForType(type);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(label);
        return marker;
    }

    function markerArray() as Array {
        var origin = currentPosition;
        if (origin == null) {
            var topLeft = mapTopLeft.toDegrees();
            var bottomRight = mapBottomRight.toDegrees();
            origin = new Position.Location({
                :latitude => (topLeft[0] + bottomRight[0]) / 2,
                :longitude => (topLeft[1] + bottomRight[1]) / 2,
                :format => :degrees
            });
        }
        var nearestAlerts = new NearestMapItems();
        var nearestOrdinary = new NearestMapItems();
        var ids = pointLocations.keys();
        for (var i = 0; i < ids.size(); i++) {
            var markerId = ids[i].toString();
            if (markerId.find("route-point:") == 0) { continue; }
            if (!isIncomingUserVisible(markerId)) { continue; }
            var details = incomingDetails.get(markerId);
            if (details instanceof Dictionary && details.get("isAlert") == true) {
                nearestAlerts.add(markerId, distanceMeters(origin, pointLocations.get(markerId)));
            } else {
                nearestOrdinary.add(markerId, distanceMeters(origin, pointLocations.get(markerId)));
            }
        }
        drawnPointIds = nearestAlerts.pointIds.slice(0, nearestAlerts.pointIds.size());
        for (var ordinaryIndex = 0;
                ordinaryIndex < nearestOrdinary.pointIds.size() && drawnPointIds.size() < MAP_DRAWN_LIMIT;
                ordinaryIndex++) {
            drawnPointIds.add(nearestOrdinary.pointIds[ordinaryIndex]);
        }
        var result = [];
        for (var i = 0; i < drawnPointIds.size(); i++) {
            var markerId = drawnPointIds[i];
            if (incomingDetails.hasKey(markerId)) {
                var details = incomingDetails.get(markerId) as Dictionary;
                if (details.get("isAlert") == true) {
                    var alertMarker = new WatchUi.MapMarker(pointLocations.get(markerId));
                    var alertIcon = WatchUi.loadResource(Rez.Drawables.AlertIcon);
                    alertMarker.setIcon(alertIcon, alertIcon.getWidth() / 2, alertIcon.getHeight() / 2);
                    alertMarker.setLabel(incomingPointTitle(markerId));
                    result.add(alertMarker);
                } else {
                    var cotType = details.get("type") as String;
                    if (details.get("generic") == true) {
                        var genericMarker = new WatchUi.MapMarker(pointLocations.get(markerId));
                        var dot = WatchUi.loadResource(Rez.Drawables.GenericDotIcon);
                        genericMarker.setIcon(dot, 7, 7);
                        genericMarker.setLabel(incomingPointTitle(markerId));
                        result.add(genericMarker);
                    } else {
                        var type = cotType.find("a-h-") != null ? :hostile : cotType.find("a-f-") != null ? :friendly : cotType.find("a-n-") != null ? :neutral : :unknown;
                        result.add(createPointMarker(pointLocations.get(markerId), type, incomingPointTitle(markerId)));
                    }
                }
            } else {
                result.add(markers.get(markerId));
            }
        }
        return result;
    }

    function pointScreenPosition(location) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var degrees = location.toDegrees();
        return [(degrees[1] - topLeft[1]) / (bottomRight[1] - topLeft[1]) * screenWidth,
            (topLeft[0] - degrees[0]) / (topLeft[0] - bottomRight[0]) * screenHeight];
    }

    function pointsAtScreen(x, y) as Array<String> {
        var hits = [];
        var keys = drawnPointIds;
        for (var i = 0; i < keys.size(); i++) {
            if (!pointLocations.hasKey(keys[i])) { continue; }
            if (!isIncomingUserVisible(keys[i])) { continue; }
            if (isLocationAtScreen(pointLocations.get(keys[i]), x, y)) {
                hits.add(keys[i]);
            }
        }
        if (routesVisible && mapTopLeft != null && mapBottomRight != null) {
            for (var r = 0; r < routeStore.routes.size(); r++) {
                var route = routeStore.routes[r];
                var points = route.get("points") as Array;
                for (var p = 0; p < points.size(); p++) {
                    var screen = routeScreenPoint(points[p]);
                    if (screen == null) { continue; }
                    var dx = screen[0] - x;
                    var dy = screen[1] - y;
                    if (screen[0] >= 0 && screen[0] < screenWidth && screen[1] >= 0 && screen[1] < screenHeight
                            && dx * dx + dy * dy <= 14 * 14) {
                        hits.add(routeStore.pointId(route, p));
                    }
                }
            }
        }
        return hits;
    }

    function pointAtScreen(x, y) {
        var hits = pointsAtScreen(x, y);
        return hits.size() > 0 ? hits[0] : null;
    }

    function isSelfAtScreen(x, y) as Boolean {
        return currentPosition != null && isLocationAtScreen(currentPosition, x, y);
    }

    function isLocationAtScreen(location, x, y) as Boolean {
        if (mapTopLeft == null || mapBottomRight == null) { return false; }
        var screen = pointScreenPosition(location);
        if (screen[0] < 0 || screen[0] >= screenWidth || screen[1] < 0 || screen[1] >= screenHeight) {
            return false;
        }
        var dx = screen[0] - x;
        var dy = screen[1] - y;
        return dx * dx + dy * dy <= 14 * 14;
    }

    function changePointType(id, type, label) {
        if (pointLocations.hasKey(id) == false || pointDetails.hasKey(id) == false) {
            return;
        }
        var details = copiedPointDetails(id);
        var currentType = details.get("type") as Symbol;
        var currentTitle = safeDetailString(details, "title", "");
        details.put("type", type);
        if (currentTitle.equals("") || currentTitle.equals(defaultPointTitle(currentType))) {
            details.put("title", defaultPointTitle(type));
        }
        if (updatePoint(id, details)) {
            defaultPointType = type;
            Application.Storage.setValue("defaultPointType", typeToString(type));
        }
    }

    function defaultPointTitle(type as Symbol) as String {
        if (type == :friendly) {
            return application.text(Rez.Strings.TextFriendlyPoint);
        } else if (type == :hostile) {
            return application.text(Rez.Strings.TextHostilePoint);
        } else if (type == :neutral) {
            return application.text(Rez.Strings.TextObstaclePoint);
        }
        return application.text(Rez.Strings.TextUnknownPoint);
    }

    function updatePointText(id, field, value) {
        if (pointLocations.hasKey(id) == false || pointDetails.hasKey(id) == false) {
            return;
        }
        var details = copiedPointDetails(id);
        if (field.equals("title") && value.equals("")) {
            value = defaultPointTitle(details.get("type") as Symbol);
        }
        details.put(field, value);
        updatePoint(id, details);
    }

    function getPointText(id, field) as String {
        var selected = routeStore.point(id);
        if (selected != null && field.equals("title")) { return routeStore.title(selected); }
        if (pointDetails.hasKey(id) == false) {
            return "";
        }
        var value = (pointDetails.get(id) as Dictionary).get(field);
        return value == null ? "" : value.toString();
    }

    function getPointLocalTime(id as String) as String {
        if (!pointDetails.hasKey(id)) { return "Unknown"; }
        return safeDetailString(pointDetails.get(id) as Dictionary, "localTime", "Unknown");
    }

    function getOrderedPointIds() as Array<String> {
        return pointOrder;
    }

    function getPointIcon(id as String) {
        if (!pointDetails.hasKey(id)) { return iconForType(:unknown); }
        return iconForType((pointDetails.get(id) as Dictionary).get("type") as Symbol);
    }

    function deleteLastPoint() as Boolean {
        if (pointOrder.size() == 0) {
            if (takClient != null) {
                for (var i = takClient.pointReplies.replies.size() - 1; i >= 0; i--) {
                    var entry = takClient.pointReplies.replies[i];
                    if (entry.get("msgType").equals("marker")) {
                        return takClient.deleteMarker((entry.get("payload") as Dictionary).get("localId").toString());
                    }
                }
            }
            return false;
        }
        return deletePoint(pointOrder[0] as String);
    }

    function getPointTypeLabel(id) as String {
        if (pointDetails.hasKey(id) == false) {
            return application.text(Rez.Strings.TextUnknownPoint);
        }
        var details = pointDetails.get(id) as Dictionary;
        var type = details.get("type");
        if (type == null) {
            return application.text(Rez.Strings.TextUnknownPoint);
        }
        return defaultPointTitle(type as Symbol);
    }

    function getPointTypeShortLabel(id) as String {
        if (pointDetails.hasKey(id) == false) {
            return "Unknown";
        }
        var type = (pointDetails.get(id) as Dictionary).get("type");
        if (type == :friendly) { return "Friendly"; }
        else if (type == :hostile) { return "Hostile"; }
        else if (type == :neutral) { return "Neutral"; }
        return "Unknown";
    }

    function getPointLocation(id) {
        return pointLocations.get(id);
    }

    function getPointDropTime(id) as String {
        if (pointDetails.hasKey(id) == false) {
            return "Unknown";
        }
        return safeDetailString(pointDetails.get(id) as Dictionary, "droppedAt", "Unknown");
    }

    function getPointDistanceLabel(id) as String {
        var location = pointLocations.get(id);
        if (currentPosition == null || location == null) {
            return "--";
        }
        return application.formatDistance(distanceMeters(currentPosition, location), 2);
    }

    function getPointLatitudeLabel(id) as String {
        var location = pointLocations.get(id);
        return location == null ? "--" : location.toDegrees()[0].format("%.5f");
    }

    function getPointLongitudeLabel(id) as String {
        var location = pointLocations.get(id);
        return location == null ? "--" : location.toDegrees()[1].format("%.5f");
    }

    function getPointMGRSLabel(id) as String {
        var location = pointLocations.get(id);
        return location == null ? "Unavailable" : mgrsLabel(location);
    }

    function getPointBearingDegrees(id) as Number {
        var location = pointLocations.get(id);
        if (currentPosition == null || location == null) {
            return 0;
        }
        return bearingDegrees(currentPosition, location).toNumber();
    }

    function getPointCardinalDirection(id) as String {
        var directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var index = Math.floor((getPointBearingDegrees(id) + 22.5) / 45).toNumber() % 8;
        return directions[index];
    }

    function isBloodhoundTarget(id) as Boolean {
        return bloodhoundPointId != null && bloodhoundPointId.equals(id);
    }

    function movePointToCurrentLocation(id) as Boolean {
        application.requestPositionForAction("self_marker");
        var info = Position.getInfo();
        if (pointDetails.hasKey(id) == false || takClient == null) {
            WatchUi.showToast(application.text(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        var location = info != null && info.position != null ? info.position : currentPosition;
        var details = copiedPointDetails(id);
        if (!takClient.sendSelfMarker(id, location, details.get("type") as Symbol,
                safeDetailString(details, "title", ""), safeDetailString(details, "remark", ""))) {
            return false;
        }
        details.put("locationSource", takClient.phoneLocationSupported ? "phone" : "");
        pointDetails.put(id, details);
        savePoints();
        if (location != null) {
            currentPosition = location;
            pointLocations.put(id, location);
            markers.put(id, createPointMarker(location, details.get("type"), details.get("title")));
            markersDirty = true;
            savePoints();
            WatchUi.requestUpdate();
        }
        return true;
    }

    function copiedPointDetails(id) as Dictionary {
        var original = pointDetails.get(id) as Dictionary;
        var copy = {};
        var keys = original.keys();
        for (var i = 0; i < keys.size(); i++) { copy.put(keys[i], original.get(keys[i])); }
        return copy;
    }

    function safeDetailString(details as Dictionary, key as String, fallback as String) as String {
        var value = details.get(key);
        if (value == null) {
            return fallback;
        }
        return value.toString();
    }

    function updatePoint(id, details as Dictionary) as Boolean {
        var location = pointLocations.get(id);
        var type = details.get("type") as Symbol;
        var title = safeDetailString(details, "title", defaultPointTitle(type));
        var remark = safeDetailString(details, "remark", "");
        if (takClient != null) {
            var atSelf = safeDetailString(details, "locationSource", "").equals("phone");
            if (atSelf) { application.requestPositionForAction("self_marker"); }
            if (!(atSelf ? takClient.sendSelfMarker(id, location, type, title, remark)
                    : takClient.sendMarker(id, location, type, title, remark))) { return false; }
        }
        pointDetails.put(id, details);
        markers.put(id, createPointMarker(location, type, title));
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
        return true;
    }

    function deletePoint(id) as Boolean {
        if (id == null || pointLocations == null || pointLocations.hasKey(id) == false
                || !pointDetails.hasKey(id) || pointOrder.indexOf(id) < 0) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient != null && !takClient.deleteMarker(id)) { return false; }
        if (bloodhoundPointId != null && bloodhoundPointId.equals(id)) {
            bloodhoundPointId = null;
            notifyBloodhoundChanged();
        }
        markers.remove(id);
        pointLocations.remove(id);
        pointDetails.remove(id);
        pointOrder.remove(id);
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
        return true;
    }

    function clearDroppedPoints() as Boolean {
        var complete = true;
        var pointIds = pointOrder.slice(0, pointOrder.size());
        for (var i = 0; i < pointIds.size(); i++) {
            if (!deletePoint(pointIds[i])) { complete = false; }
        }
        if (takClient != null) {
            var pending = pendingSelfPoints.slice(0, pendingSelfPoints.size());
            for (var pendingIndex = 0; pendingIndex < pending.size(); pendingIndex++) {
                if (takClient.deleteMarker(pending[pendingIndex].get("id") as String)) {
                    pendingSelfPoints.remove(pending[pendingIndex]);
                } else { complete = false; }
            }
            if (!takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints)) { complete = false; }
            var entries = takClient.pointReplies.replies.slice(0, takClient.pointReplies.replies.size());
            for (var j = 0; j < entries.size(); j++) {
                var entry = entries[j];
                var payload = entry.get("payload") as Dictionary;
                if (entry.get("msgType").equals("marker") && payload.get("lat") == null) {
                    if (!takClient.deleteMarker(payload.get("localId").toString())) { complete = false; }
                }
            }
        }
        if (!complete) { return false; }

        clearPersistedDroppedWaypoints();
        WatchUi.requestUpdate();
        return true;
    }

    function clearPersistedDroppedWaypoints() as Void {
        var waypoints = PersistedContent.getAppWaypoints();
        var waypoint = waypoints.next();
        while (waypoint != null) {
            waypoint.remove();
            waypoint = waypoints.next();
        }
    }

    function incomingEntityNow() as Number { return Time.now().value(); }

    function pruneIncomingEntities() as Boolean {
        var now = incomingEntityNow();
        var pendingCount = pendingSelfPoints.size();
        expirePendingSelfPoints();
        if (pendingSelfPoints.size() != pendingCount && takClient != null) {
            takClient.saveOfflineValue("pendingSelfPoints", pendingSelfPoints);
        }
        var usersChanged = false;
        var users = userSourceStates.keys();
        for (var userIndex = 0; userIndex < users.size(); userIndex++) {
            var uid = users[userIndex] as String;
            var sources = userSourceStates.get(uid);
            var sourceKeys = sources.keys();
            for (var sourceIndex = 0; sourceIndex < sourceKeys.size(); sourceIndex++) {
                var record = sources.get(sourceKeys[sourceIndex]);
                var deadline = record.get("staleDeadline") as String;
                if ((deadline.length() > 0 && userDeadlineExpired(deadline))
                        || (deadline.length() == 0 && (now - record.get("seen") > 300
                            || (incomingLastSeen.get("cot-" + uid) instanceof Number
                                && now - incomingLastSeen.get("cot-" + uid) > 300)))) {
                    removeIncomingUserSource(uid, sourceKeys[sourceIndex] as String);
                    usersChanged = true;
                }
            }
        }
        var staleIds = [];
        var changed = usersChanged;
        var ids = incomingLastSeen.keys();
        for (var i = 0; i < ids.size(); i++) {
            var id = ids[i] as String;
            var details = incomingDetails.get(id);
            if (details instanceof Dictionary && details.get("isAlert") == true) {
                var stale = isIncomingAlertStale(details as Dictionary);
                if (details.get("stale") != stale) {
                    details.put("stale", stale);
                    changed = true;
                }
            } else if (details instanceof Dictionary && details.get("isUser") == true) {
                continue;
            } else if ((details instanceof Dictionary && details.get("staleDeadline") instanceof String
                    && (details.get("staleDeadline") as String).length() > 0
                    && userDeadlineExpired(details.get("staleDeadline") as String))
                    || now - incomingLastSeen.get(id) > 300) {
                staleIds.add(id);
            }
        }
        for (var j = 0; j < staleIds.size(); j++) {
            if (incomingDetails.get(staleIds[j]) instanceof Dictionary && (incomingDetails.get(staleIds[j]) as Dictionary).get("isAlert") == true) {
                continue;
            }
            removeIncomingPoint(staleIds[j], false);
        }
        var dismissedIds = dismissedIncomingPoints.keys();
        for (var k = 0; k < dismissedIds.size(); k++) {
            var dismissal = dismissedIncomingPoints.get(dismissedIds[k]);
            var removedAt = dismissal instanceof Dictionary ? dismissal.get("removedAt") : null;
            if (dismissal instanceof Dictionary && dismissal.get("isAlert") != true
                    && removedAt instanceof Number && now - (removedAt as Number) > 300) {
                dismissedIncomingPoints.remove(dismissedIds[k]);
                changed = true;
            }
        }
        if (staleIds.size() > 0 || changed) {
            markersDirty = true;
        }
        if (changed) { saveIncomingAlertPersistence(); }
        return staleIds.size() > 0 || changed;
    }

    function pruneIncomingEntitiesOnTimer() as Void {
        if (pruneIncomingEntities()) {
            WatchUi.requestUpdate();
        }
    }

    function zoom(scale) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var centerLat = (topLeft[0] + bottomRight[0]) / 2;
        var centerLon = (topLeft[1] + bottomRight[1]) / 2;
        var halfLat = (topLeft[0] - bottomRight[0]) * scale / 2;
        var halfLon = (bottomRight[1] - topLeft[1]) * scale / 2;
        mapTopLeft = new Position.Location({:latitude => centerLat + halfLat, :longitude => centerLon - halfLon, :format => :degrees});
        mapBottomRight = new Position.Location({:latitude => centerLat - halfLat, :longitude => centerLon + halfLon, :format => :degrees});
        applyMapVisibleArea();
        WatchUi.requestUpdate();
    }

    function pan(direction) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var latShift = (topLeft[0] - bottomRight[0]) * 0.25;
        var lonShift = (bottomRight[1] - topLeft[1]) * 0.25;
        var latOffset = 0.0;
        var lonOffset = 0.0;
        if (direction == WatchUi.SWIPE_UP) {
            latOffset = latShift;
        } else if (direction == WatchUi.SWIPE_DOWN) {
            latOffset = -latShift;
        } else if (direction == WatchUi.SWIPE_LEFT) {
            lonOffset = -lonShift;
        } else if (direction == WatchUi.SWIPE_RIGHT) {
            lonOffset = lonShift;
        }
        mapTopLeft = new Position.Location({:latitude => topLeft[0] + latOffset, :longitude => topLeft[1] + lonOffset, :format => :degrees});
        mapBottomRight = new Position.Location({:latitude => bottomRight[0] + latOffset, :longitude => bottomRight[1] + lonOffset, :format => :degrees});
        applyMapVisibleArea();
        WatchUi.requestUpdate();
    }

    function panFlick(direction) {
        if (direction < 45 || direction >= 315) {
            pan(WatchUi.SWIPE_UP);
        } else if (direction < 135) {
            pan(WatchUi.SWIPE_RIGHT);
        } else if (direction < 225) {
            pan(WatchUi.SWIPE_DOWN);
        } else {
            pan(WatchUi.SWIPE_LEFT);
        }
    }

    function panPixels(deltaX, deltaY) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var latOffset = (topLeft[0] - bottomRight[0]) * deltaY / screenHeight;
        var lonOffset = -(bottomRight[1] - topLeft[1]) * deltaX / screenWidth;
        mapTopLeft = new Position.Location({:latitude => topLeft[0] + latOffset, :longitude => topLeft[1] + lonOffset, :format => :degrees});
        mapBottomRight = new Position.Location({:latitude => bottomRight[0] + latOffset, :longitude => bottomRight[1] + lonOffset, :format => :degrees});
        applyMapVisibleArea();
        WatchUi.requestUpdate();
    }
}

function buildMapLayersMenu(mapView as StandaloneMapView) as WatchUi.Menu2 {
    var menu = createMenu("Layers Menu");
    addMenuEntry(menu, "Map Buttons", mapView.areMapButtonsVisible() ? "On" : "Off", :mapButtonsToggle);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesTitle), null, :routes);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesVisible),
        mapView.routesVisible ? "On" : "Off", :routesToggle);
    var teams = mapView.incomingUserGroups(true);
    addMenuEntry(menu, "Team Colors (" + teams.size().toString() + ")", null, :teamColorsHeading);
    for (var teamIndex = 0; teamIndex < teams.size(); teamIndex++) {
        var team = teams[teamIndex] as Dictionary;
        var teamName = team.get("name").toString();
        var teamCount = team.get("count") as Number;
        addMenuEntry(menu, teamName + " (" + teamCount.toString() + ")", mapView.isMapGroupHiddenForKind(true, teamName) ? "Hidden" : "Shown", teamIndex);
    }
    var roles = mapView.incomingUserGroups(false);
    addMenuEntry(menu, "Default Roles (" + roles.size().toString() + ")", null, :defaultRolesHeading);
    for (var roleIndex = 0; roleIndex < roles.size(); roleIndex++) {
        var role = roles[roleIndex] as Dictionary;
        var roleName = role.get("name").toString();
        var roleCount = role.get("count") as Number;
        addMenuEntry(menu, roleName + " (" + roleCount.toString() + ")", mapView.isMapGroupHiddenForKind(false, roleName) ? "Hidden" : "Shown", 1000 + roleIndex);
    }
    addMenuEntry(menu, "Back", null, :layersBack);
    return menu;
}

class MapLayersMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var menu as WatchUi.Menu2;

    function initialize(map as StandaloneMapView, layersMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mapView = map;
        menu = layersMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :layersBack) {
            WatchUi.popView(WatchUi.SLIDE_UP);
        } else if (id == :mapButtonsToggle) {
            mapView.setMapButtonsVisible(!mapView.areMapButtonsVisible());
            item.setSubLabel(mapView.areMapButtonsVisible() ? "On" : "Off");
        } else if (id == :routes) {
            WatchUi.pushView(buildRoutesMenu(mapView), new RoutesMenuDelegate(mapView), WatchUi.SLIDE_LEFT);
        } else if (id == :routesToggle) {
            mapView.routesVisible = !mapView.routesVisible;
            item.setSubLabel(mapView.routesVisible ? "On" : "Off");
            WatchUi.requestUpdate();
        } else if (id instanceof Number) {
            var index = id as Number;
            var teamGroup = index < 1000;
            var groups = mapView.incomingUserGroups(teamGroup);
            if (teamGroup) {
                if (index >= 0 && index < groups.size()) {
                    var group = groups[index] as Dictionary;
                    mapView.toggleMapGroup(true, group.get("name").toString());
                    item.setSubLabel(mapView.isMapGroupHiddenForKind(true, group.get("name").toString()) ? "Hidden" : "Shown");
                }
            } else {
                var roleIndex = index - 1000;
                if (roleIndex >= 0 && roleIndex < groups.size()) {
                    var role = groups[roleIndex] as Dictionary;
                    mapView.toggleMapGroup(false, role.get("name").toString());
                    item.setSubLabel(mapView.isMapGroupHiddenForKind(false, role.get("name").toString()) ? "Hidden" : "Shown");
                }
            }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_UP);
    }
}

function buildMapSelectionMenu(map as StandaloneMapView, ids as Array<String>, includeSelf as Boolean) as WatchUi.Menu2 {
    var menu = createMenu("Select Map Item");
    for (var index = 0; index < ids.size(); index++) {
        var id = ids[index];
        var route = map.routeStore.route(id);
        var routePoint = map.routeStore.point(id);
        if (route != null) {
            addMenuEntry(menu, route.get("name") as String,
                WatchUi.loadResource(Rez.Strings.RoutesWhole) + " | " + route.get("serverId"), id);
        } else if (routePoint != null) {
            addMenuEntry(menu, map.routeStore.title(routePoint),
                (routePoint.get("route") as Dictionary).get("name"), id);
        } else if (map.incomingDetails.hasKey(id)) {
            addMenuEntry(menu, map.incomingPointTitle(id), map.incomingPointDetailLabel(id), id);
        } else {
            addMenuEntry(menu, map.getPointText(id, "title"), map.getPointTypeLabel(id), id);
        }
    }
    if (includeSelf) {
        addMenuEntry(menu, map.application.text(Rez.Strings.TextSelf), null, :self);
    }
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class MapSelectionMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;

    function initialize(map as StandaloneMapView) {
        Menu2InputDelegate.initialize();
        mapView = map;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :cancel) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id instanceof String || id == :self) {
            mapView.showSelectedMapItem(id);
        }
    }
}

class StandaloneMapDelegate extends WatchUi.InputDelegate {
    var view;
    var app as StandaloneApp;
    var openMainMenuOnBack = false;
    var lastDragX;
    var lastDragY;
    var isDragging = false;
    var suppressNextTap as Boolean = false;

    function initialize(mapView, showMainMenuOnBack as Boolean, application as StandaloneApp) {
        WatchUi.InputDelegate.initialize();
        view = mapView;
        openMainMenuOnBack = showMainMenuOnBack;
        app = application;
    }

    function leaveMap() as Void {
        if (openMainMenuOnBack) {
            WatchUi.pushView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function onTap(evt) {
        if (suppressNextTap) {
            suppressNextTap = false;
            return true;
        }
        if (isDragging) {
            isDragging = false;
            lastDragX = null;
            lastDragY = null;
            return true;
        }
        var coordinates = evt.getCoordinates();
        if (view.isBloodhoundPanelAt(coordinates[0], coordinates[1])) {
            view.showBloodhoundCancelMenu();
            return true;
        }
        if (view.isControlAt(coordinates[0], coordinates[1])) {
            if (view.isChannelsControlAt(coordinates[0], coordinates[1])) {
                openTakChannels(app);
            } else if (view.isLayersControlAt(coordinates[0], coordinates[1])) {
                view.showLayersMenu();
            } else if (view.isZoomInControlAt(coordinates[0], coordinates[1])) {
                view.zoom(0.5);
            } else if (view.isZoomOutControlAt(coordinates[0], coordinates[1])) {
                view.zoom(2.0);
            } else if (view.isCenterControlAt(coordinates[0], coordinates[1])) {
                view.snapToSelf();
            } else if (view.isBackControlAt(coordinates[0], coordinates[1])) {
                leaveMap();
            }
            return true;
        }
        view.showMapItemsAtScreen(coordinates[0], coordinates[1]);
        return true;
    }

    function onHold(evt) {
        suppressNextTap = true;
        var coordinates = evt.getCoordinates();
        if (view.isControlAt(coordinates[0], coordinates[1])) {
            return true;
        }
        view.dropAtScreen(coordinates[0], coordinates[1]);
        view.setMapMode(WatchUi.MAP_MODE_PREVIEW);
        return true;
    }

    function onSwipe(evt) {
        isDragging = false;
        lastDragX = null;
        lastDragY = null;
        view.pan(evt.getDirection());
        return true;
    }

    function onFlick(evt) {
        isDragging = false;
        lastDragX = null;
        lastDragY = null;
        view.panFlick(evt.getDirection());
        return true;
    }

    function onDrag(evt) {
        var coordinates = evt.getCoordinates();
        if (evt.getType() == WatchUi.DRAG_TYPE_START) {
            lastDragX = coordinates[0];
            lastDragY = coordinates[1];
        } else if (lastDragX != null && lastDragY != null) {
            isDragging = true;
            view.panPixels(coordinates[0] - lastDragX, coordinates[1] - lastDragY);
            lastDragX = coordinates[0];
            lastDragY = coordinates[1];
        }
        return true;
    }

    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            leaveMap();
            return true;
        }
        return false;
    }
}

function buildPointDetailsMenu(mapView as StandaloneMapView, pointId as String) as WatchUi.Menu2 {
    var title = mapView.getPointText(pointId, "title");
    var menu = createMenu(title);
    addMenuEntry(menu, mapView.getPointTypeShortLabel(pointId), "Dropped " + mapView.getPointDropTime(pointId), :pointSummary);
    addMenuEntry(menu, "Distance", mapView.getPointDistanceLabel(pointId), :pointDistance);
    var bearing = mapView.getPointBearingDegrees(pointId);
    addMenuEntry(menu, "Bearing", bearing.format("%03d") + " deg " + mapView.getPointCardinalDirection(pointId), :pointBearing);
    addMenuEntry(menu, "Coordinates", mapView.getPointLatitudeLabel(pointId) + ", " + mapView.getPointLongitudeLabel(pointId), :pointCoordinates);
    addMenuEntry(menu, "MGRS", mapView.getPointMGRSLabel(pointId), :pointMGRS);
    addMenuEntry(menu, mapView.isBloodhoundTarget(pointId) ? "Stop Bloodhound" : "Bloodhound", null, :pointBloodhound);
    addMenuEntry(menu, "Change Title", null, :pointTitle);
    addMenuEntry(menu, mapView.getPointText(pointId, "remark").equals("") ? "Add Remark" : "Change Remark", null, :pointRemark);
    addMenuEntry(menu, "Change Marker", null, :pointType);
    addMenuEntry(menu, "Move to Current Location", null, :pointMove);
    addMenuEntry(menu, "Delete Marker", null, :pointDelete);
    return menu;
}

class PointDetailsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var pointId as String;
    var menu as WatchUi.Menu2;

    function initialize(map as StandaloneMapView, id as String, detailsMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mapView = map;
        pointId = id;
        menu = detailsMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :pointSummary || id == :pointDistance || id == :pointBearing || id == :pointCoordinates || id == :pointMGRS) {
            return;
        } else if (id == :pointBloodhound) {
            mapView.toggleBloodhound(pointId);
            item.setLabel(mapView.isBloodhoundTarget(pointId) ? "Stop Bloodhound" : "Bloodhound");
            WatchUi.requestUpdate();
        } else if (id == :pointTitle) {
            WatchUi.pushView(new WatchUi.TextPicker(mapView.getPointText(pointId, "title")), new PointTextPickerDelegate(mapView, pointId, "title"), WatchUi.SLIDE_UP);
        } else if (id == :pointRemark) {
            WatchUi.pushView(new WatchUi.TextPicker(mapView.getPointText(pointId, "remark")), new PointTextPickerDelegate(mapView, pointId, "remark"), WatchUi.SLIDE_UP);
        } else if (id == :pointType) {
            var typeMenu = createMenu("Change Marker");
            addMenuEntry(typeMenu, "Unknown", null, :unknown);
            addMenuEntry(typeMenu, "Hostile", null, :hostile);
            addMenuEntry(typeMenu, "Friendly", null, :friendly);
            addMenuEntry(typeMenu, "Neutral", null, :neutral);
            WatchUi.pushView(typeMenu, new PointTypeMenuDelegate(mapView, pointId), WatchUi.SLIDE_LEFT);
        } else if (id == :pointMove) {
            if (!mapView.movePointToCurrentLocation(pointId)) { return; }
            refreshSummary();
        } else if (id == :pointDelete) {
            if (!mapView.deletePoint(pointId)) { return; }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function refreshSummary() as Void {
        var distanceItem = menu.getItem(menu.findItemById(:pointDistance));
        if (distanceItem != null) { distanceItem.setSubLabel(mapView.getPointDistanceLabel(pointId)); }
        var bearingItem = menu.getItem(menu.findItemById(:pointBearing));
        if (bearingItem != null) {
            var bearing = mapView.getPointBearingDegrees(pointId);
            bearingItem.setSubLabel(bearing.format("%03d") + " deg " + mapView.getPointCardinalDirection(pointId));
        }
        var coordinatesItem = menu.getItem(menu.findItemById(:pointCoordinates));
        if (coordinatesItem != null) { coordinatesItem.setSubLabel(mapView.getPointLatitudeLabel(pointId) + ", " + mapView.getPointLongitudeLabel(pointId)); }
        var mgrsItem = menu.getItem(menu.findItemById(:pointMGRS));
        if (mgrsItem != null) { mgrsItem.setSubLabel(mapView.getPointMGRSLabel(pointId)); }
        WatchUi.requestUpdate();
    }
}

class CoordinateMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class BloodhoundCancelDelegate extends WatchUi.Menu2InputDelegate {
    var view;

    function initialize(mapView) {
        Menu2InputDelegate.initialize();
        view = mapView;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :cancelBloodhound) {
            view.toggleBloodhound(null);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class PointTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view;
    var pointId;

    function initialize(mapView, id) {
        Menu2InputDelegate.initialize();
        view = mapView;
        pointId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :friendly) {
            view.changePointType(pointId, :friendly, "Friendly 2525D point");
        } else if (id == :hostile) {
            view.changePointType(pointId, :hostile, "Hostile 2525D point");
        } else if (id == :neutral) {
            view.changePointType(pointId, :neutral, "Neutral 2525D point");
        } else {
            view.changePointType(pointId, :unknown, view.application.text(Rez.Strings.TextUnknownPoint));
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        view.showPointTypeMenu(pointId);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class PointTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var view;
    var pointId;
    var field;

    function initialize(mapView, id, pointField) {
        TextPickerDelegate.initialize();
        view = mapView;
        pointId = id;
        field = pointField;
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        if (changed) {
            view.updatePointText(pointId, field, text);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        view.showPointTypeMenu(pointId);
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

function teamColorValue(team as String) as Number {
    var color = team.toLower();
    if (color.equals("white")) { return Graphics.createColor(255, 255, 255, 255); }
    else if (color.equals("yellow")) { return Graphics.createColor(255, 255, 255, 0); }
    else if (color.equals("orange")) { return Graphics.createColor(255, 255, 165, 0); }
    else if (color.equals("magenta")) { return Graphics.createColor(255, 255, 0, 255); }
    else if (color.equals("red")) { return Graphics.createColor(255, 255, 0, 0); }
    else if (color.equals("maroon")) { return Graphics.createColor(255, 128, 0, 0); }
    else if (color.equals("purple")) { return Graphics.createColor(255, 128, 0, 128); }
    else if (color.equals("dark blue")) { return Graphics.createColor(255, 0, 0, 139); }
    else if (color.equals("cyan")) { return Graphics.createColor(255, 0, 255, 255); }
    else if (color.equals("teal")) { return Graphics.createColor(255, 0, 128, 128); }
    else if (color.equals("green")) { return Graphics.createColor(255, 0, 128, 0); }
    else if (color.equals("dark green")) { return Graphics.createColor(255, 0, 100, 0); }
    else if (color.equals("brown")) { return Graphics.createColor(255, 165, 42, 42); }
    return Graphics.createColor(255, 0, 0, 255);
}
