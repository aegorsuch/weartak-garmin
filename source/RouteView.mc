import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

function buildRoutesMenu(map as StandaloneMapView) as WatchUi.Menu2 {
    var menu = createMenu(WatchUi.loadResource(Rez.Strings.RoutesTitle));
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.DataSyncRefresh), null, :refresh);
    var routes = map.routeStore.routes;
    for (var i = 0; i < routes.size(); i++) {
        var route = routes[i];
        addMenuEntry(menu, route.get("name") as String, route.get("serverId") as String, route);
    }
    if (routes.size() == 0) { addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesEmpty), null, :empty); }
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class RoutesMenuDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    function initialize(view as StandaloneMapView) { Menu2InputDelegate.initialize(); map = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var route = item.getId();
        if (route == :refresh) {
            if (map.takClient == null || !map.takClient.isConnected()) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.DataSyncRelayOff), null);
                return;
            }
            map.takClient.transmit("entity_sync_request", {"limit" => 50, "protocolVersion" => 1, "routeVersion" => 1});
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (route == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        else if (route instanceof Dictionary) {
            var current = map.routeStore.find(route.get("serverId") as String, route.get("uid") as String);
            if (current == null) { map.routeUnavailable(); return; }
            map.showRoute(map.routeStore.routeId(current));
        }
    }
}

function buildRouteMenu(map as StandaloneMapView, id as String) as WatchUi.Menu2? {
    var route = map.routeStore.route(id);
    if (route == null) { return null; }
    var menu = createMenu(route.get("name") as String);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesPoints),
        Lang.format(WatchUi.loadResource(Rez.Strings.RoutesPointCounts),
            [map.routeStore.namedPointIndices(route).size(), (route.get("points") as Array).size()]), :points);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesServer), route.get("serverId"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesMission), route.get("missionName"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesSender), route.get("senderUid"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesRemove), null, :remove);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.TextBloodhound), null, :follow);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class RouteMenuDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var routeId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize(); map = view; routeId = id;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        var route = map.routeStore.route(routeId);
        if (route == null) { map.routeUnavailable(); return; }
        if (item.getId() == :points) {
            WatchUi.pushView(buildRoutePointsMenu(map, route), new RoutePointListDelegate(map), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :follow) {
            map.showRouteFollow(routeId);
        } else if (item.getId() == :remove) {
            WatchUi.pushView(buildRouteRemovalMenu(route),
                new RouteRemovalDelegate(map, routeId), WatchUi.SLIDE_LEFT);
        }
    }
}

function buildRouteRemovalMenu(route as Dictionary) as WatchUi.Menu2 {
    var menu = createMenu(WatchUi.loadResource(Rez.Strings.RoutesRemoveConfirm));
    addMenuEntry(menu, route.get("name") as String, route.get("serverId"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesRemoveScope),
        WatchUi.loadResource(Rez.Strings.RoutesRemoveReplay), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesRemove), null, :confirmRemove);
    menu.setFocus(2);
    return menu;
}

class RouteRemovalDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var routeId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize(); map = view; routeId = id;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :cancel) { close(false); }
        else if (item.getId() == :confirmRemove && map.removeLocalRoute(routeId)) { close(true); }
    }
    function close(removed as Boolean) as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        if (removed) {
            WatchUi.switchToView(buildRoutesMenu(map), new RoutesMenuDelegate(map), WatchUi.SLIDE_RIGHT);
        }
    }
}

function buildRoutePointsMenu(map as StandaloneMapView, route as Dictionary) as WatchUi.Menu2 {
    var menu = createMenu(route.get("name") as String);
    var points = route.get("points") as Array;
    var indices = map.routeStore.namedPointIndices(route);
    for (var row = 0; row < indices.size(); row++) {
        var i = indices[row];
        var id = map.routeStore.pointId(route, i);
        var selected = map.routeStore.point(id);
        var coordinates = map.latLonLabel(map.routeStore.location(points[i]));
        addMenuEntry(menu, map.routeStore.title(selected), "#" + (i + 1).toString() + " " + coordinates, id);
    }
    if (indices.size() == 0) {
        addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesNoNamedPoints), null, :empty);
    }
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class RoutePointListDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    function initialize(view as StandaloneMapView) { Menu2InputDelegate.initialize(); map = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        else if (id instanceof String) { map.showRoutePoint(id); }
    }
}

function buildRoutePointMenu(map as StandaloneMapView, id as String) as WatchUi.Menu2? {
    var selected = map.routeStore.point(id);
    if (selected == null) { return null; }
    var route = selected.get("route") as Dictionary;
    var point = selected.get("point") as Dictionary;
    var menu = createMenu(map.routeStore.title(selected));
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesWhole), route.get("name"), :route);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesServer), route.get("serverId"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesMission), route.get("missionName"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesSender), route.get("senderUid"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesLatitude), (point.get("lat") as Double).format("%.5f"), :detail);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesLongitude), (point.get("lon") as Double).format("%.5f"), :detail);
    addMenuEntry(menu, map.application.text(map.isBloodhoundTarget(id)
        ? Rez.Strings.TextStopBloodhound : Rez.Strings.TextBloodhound), null, :track);
    var sender = route.get("senderUid");
    if (sender instanceof String && sender.length() > 0) {
        addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.MenuTitleChat), null, :chat);
    }
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class RoutePointMenuDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var pointId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize(); map = view; pointId = id;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        var selected = map.routeStore.point(pointId);
        if (selected == null) { map.routeUnavailable(); WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        if (item.getId() == :route) {
            map.showRoute(map.routeStore.routeId(selected.get("route") as Dictionary));
        } else if (item.getId() == :track) {
            map.toggleRouteBloodhound(pointId);
            WatchUi.switchToView(buildRoutePointMenu(map, pointId),
                new RoutePointMenuDelegate(map, pointId), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :chat) {
            var route = selected.get("route") as Dictionary;
            var sender = route.get("senderUid");
            if (!(sender instanceof String) || sender.length() == 0) {
                map.routeUnavailable();
                return;
            }
            var room = map.application.chats.open(sender, sender, false);
            if (room != null) { openChatConversation(map.application, room); }
        }
    }
}

function routeSegmentAtScreen(line as Array, x, y) as Boolean {
    var dx = line[2] - line[0];
    var dy = line[3] - line[1];
    var lengthSquared = dx * dx + dy * dy;
    var t = lengthSquared == 0 ? 0 : ((x - line[0]) * dx + (y - line[1]) * dy) / lengthSquared;
    if (t < 0) { t = 0; }
    if (t > 1) { t = 1; }
    dx = x - (line[0] + t * dx);
    dy = y - (line[1] + t * dy);
    return dx * dx + dy * dy <= 14 * 14;
}

// Clip before converting geographic projections to device-sized integer coordinates.
function clippedRouteSegment(a as Array, b as Array, width as Number, height as Number) as Array? {
    var dx = b[0] - a[0];
    var dy = b[1] - a[1];
    var p = [-dx, dx, -dy, dy];
    var q = [a[0], width - a[0], a[1], height - a[1]];
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 4; i++) {
        if (p[i] == 0) {
            if (q[i] < 0) { return null; }
        } else {
            var t = q[i] / p[i];
            if (p[i] < 0) { if (t > hi) { return null; } if (t > lo) { lo = t; } }
            else { if (t < lo) { return null; } if (t < hi) { hi = t; } }
        }
    }
    return [a[0] + lo * dx, a[1] + lo * dy, a[0] + hi * dx, a[1] + hi * dy];
}

function addBloodhoundRoutes(menu as WatchUi.Menu2, map as StandaloneMapView) as Number {
    var routes = map.routeStore.routes;
    for (var i = 0; i < routes.size(); i++) {
        addPickerTarget(menu, map, map.routeStore.routeId(routes[i]));
    }
    return routes.size();
}

class RouteFollowMenu extends WatchUi.Menu2 {
    var map as StandaloneMapView;
    var routeId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2.initialize({:title => (view.routeStore.route(id) as Dictionary).get("name") as String});
        map = view; routeId = id;
        populate();
    }
    function onShow() as Void { map.routeFollowMenu = self; refresh(); }
    function onHide() as Void {
        if (map.routeFollowMenu == self) { map.routeFollowMenu = null; }
    }
    function refresh() as Void {
        var focused = mFocus == null ? null : getItem(mFocus);
        var id = focused == null ? null : focused.getId();
        while (getItem(0) != null) { deleteItem(0); }
        populate();
        for (var i = 0; getItem(i) != null; i++) {
            if (getItem(i).getId() == id) { setFocus(i); break; }
        }
    }
    function populate() as Void {
        var route = map.routeStore.route(routeId);
        if (route == null) {
            addMenuEntry(self, WatchUi.loadResource(Rez.Strings.RoutesUnavailable), null, :empty);
        } else if (routeId.equals(map.followingRouteId)) {
            addMenuEntry(self, map.routeProgress(), map.routeRemainingLabel(), :progress);
            addPickerAction(self, WatchUi.loadResource(Rez.Strings.RouteStop), null, :stopRoute, Rez.Drawables.PickerStopIcon);
        } else {
            addPickerAction(self, WatchUi.loadResource(Rez.Strings.RouteStartNearest),
                map.currentPosition == null ? WatchUi.loadResource(Rez.Strings.RouteNeedsLocation) : null,
                map.currentPosition == null ? :noLocation : :nearest,
                map.currentPosition == null ? Rez.Drawables.PickerHoundUnavailableIcon : Rez.Drawables.PickerHoundIcon);
            addMenuEntry(self, WatchUi.loadResource(Rez.Strings.RouteStartBeginning), null, :beginning);
        }
        addMenuEntry(self, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    }
}

class RouteFollowDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var routeId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize(); map = view; routeId = id;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        if (map.routeStore.route(routeId) == null) { map.routeUnavailable(); return; }
        if (id == :noLocation) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.RouteNeedsLocation), null);
        } else if (id == :stopRoute) {
            if (routeId.equals(map.followingRouteId)) { map.stopRoute(); }
            WatchUi.switchToView(new RouteFollowMenu(map, routeId), new RouteFollowDelegate(map, routeId), WatchUi.SLIDE_LEFT);
        } else if (id == :nearest || id == :beginning) {
            if (!map.startRoute(routeId, id == :nearest)) { return; }
            WatchUi.switchToView(new BloodhoundCompassView(map.application), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}
