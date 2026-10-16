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
            var menu = createMenu(current.get("name") as String);
            var points = current.get("points") as Array;
            for (var i = 0; i < points.size(); i++) {
                var id = map.routeStore.pointId(current, i);
                var selected = map.routeStore.point(id);
                addMenuEntry(menu, map.routeStore.title(selected), null, id);
            }
            WatchUi.pushView(menu, new RoutePointListDelegate(map), WatchUi.SLIDE_LEFT);
        }
    }
}

class RoutePointListDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    function initialize(view as StandaloneMapView) { Menu2InputDelegate.initialize(); map = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String) { map.showRoutePoint(id); }
    }
}

function buildRoutePointMenu(map as StandaloneMapView, id as String) as WatchUi.Menu2? {
    var selected = map.routeStore.point(id);
    if (selected == null) { return null; }
    var route = selected.get("route") as Dictionary;
    var point = selected.get("point") as Dictionary;
    var menu = createMenu(map.routeStore.title(selected));
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.RoutesTitle), route.get("name"), :detail);
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
        if (item.getId() == :track) {
            map.toggleRouteBloodhound(pointId);
            WatchUi.switchToView(buildRoutePointMenu(map, pointId),
                new RoutePointMenuDelegate(map, pointId), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :chat) {
            var route = selected.get("route") as Dictionary;
            var sender = route.get("senderUid");
            var room = map.application.chats.open(sender, sender, false);
            if (room != null) { openChatConversation(map.application, room); }
        }
    }
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
