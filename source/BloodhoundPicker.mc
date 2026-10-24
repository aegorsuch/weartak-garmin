import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

function pickerTargetExists(map as StandaloneMapView, id as String) as Boolean {
    return map.routeStore.route(id) != null || map.pointLocations.hasKey(id) || map.incomingDetails.hasKey(id);
}

function pickerTargetActive(map as StandaloneMapView, id as String) as Boolean {
    return id.equals(map.followingRouteId) || map.isBloodhoundTarget(id);
}

function pickerDistance(map as StandaloneMapView, meters) as String {
    return map.application.formatDistance(meters, 1);
}

function pickerTargetTitle(map as StandaloneMapView, id as String) as String {
    var route = map.routeStore.route(id);
    if (route != null) { return route.get("name") as String; }
    return map.incomingDetails.hasKey(id) ? map.incomingPointTitle(id) : map.getPointText(id, "title");
}

function pickerTargetKind(map as StandaloneMapView, id as String) as Symbol {
    if (map.routeStore.route(id) != null) { return :route; }
    var details = map.incomingDetails.get(id);
    if (!(details instanceof Dictionary)) { return :marker; }
    if (details.get("isAlert") == true) { return :alert; }
    if (details.get("isCamera") == true) { return :camera; }
    return details.get("isPoint") == true ? :point : :contact;
}

function pickerTargetSubtitle(map as StandaloneMapView, id as String) as String {
    var route = map.routeStore.route(id);
    if (route != null) {
        var points = route.get("points") as Array;
        if (id.equals(map.followingRouteId)) {
            var remaining = map.currentPosition == null ? WatchUi.loadResource(Rez.Strings.RouteNeedsLocation)
                : Lang.format(WatchUi.loadResource(Rez.Strings.PickerRemaining),
                    [pickerDistance(map, RouteNavigation.remaining(points, map.followingRouteIndex, map.currentPosition))]);
            return map.routeProgress() + " \u00b7 " + remaining;
        }
        var label = WatchUi.loadResource(Rez.Strings.PickerRoute) + " \u00b7 "
            + Lang.format(WatchUi.loadResource(Rez.Strings.RoutePointCount), [points.size()]);
        var nearest = RouteNavigation.nearest(points, map.currentPosition);
        return nearest == null ? label : label + " \u00b7 "
            + pickerDistance(map, RouteNavigation.distance(map.currentPosition, RouteNavigation.location(points[nearest])));
    }
    var kind = pickerTargetKind(map, id);
    if (kind == :camera) {
        kind = map.incomingDetails.get(id).get("isPoint") == true ? :point : :contact;
    }
    var label = WatchUi.loadResource(kind == :marker ? Rez.Strings.PickerMarker
        : kind == :contact ? Rez.Strings.PickerContact : kind == :alert ? Rez.Strings.IncomingAlertLabel : Rez.Strings.PickerPoint);
    var location = map.pointLocations.get(id);
    return map.currentPosition == null || location == null ? label : label + " \u00b7 "
        + pickerDistance(map, RouteNavigation.distance(map.currentPosition, location));
}

class PickerTypeGlyph extends WatchUi.Drawable {
    var kind as Symbol;
    var active as Boolean;
    function initialize(type as Symbol, selected as Boolean) {
        Drawable.initialize({:locX => 0, :locY => 0, :width => 24, :height => 24}); kind = type; active = selected;
    }
    function draw(dc as Graphics.Dc) as Void {
        if (!isVisible) { return; }
        dc.setColor(active ? 0x3b2a00 : Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(locX + 12, locY + 12, 11);
        if (active) {
            dc.setColor(0xffbf00, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(locX + 12, locY + 12, 11);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (kind == :route) {
            dc.drawLine(locX + 4, locY + 16, locX + 9, locY + 6);
            dc.drawLine(locX + 9, locY + 6, locX + 15, locY + 18);
            dc.drawLine(locX + 15, locY + 18, locX + 20, locY + 8);
        } else if (kind == :camera) {
            dc.drawRectangle(locX + 4, locY + 7, 12, 10);
            dc.drawLine(locX + 16, locY + 10, locX + 20, locY + 7);
            dc.drawLine(locX + 20, locY + 7, locX + 20, locY + 17);
            dc.drawLine(locX + 20, locY + 17, locX + 16, locY + 14);
        } else if (kind == :contact) {
            dc.fillCircle(locX + 12, locY + 7, 4); dc.fillRectangle(locX + 7, locY + 14, 10, 6);
        } else { dc.fillCircle(locX + 12, locY + 12, 5); }

    }
}

class BloodhoundTargetIcon extends WatchUi.Drawable {
    var map as StandaloneMapView;
    function initialize(view as StandaloneMapView) {
        Drawable.initialize({:locX => 0, :locY => 0, :width => 24, :height => 24});
        map = view;
    }
    function draw(dc as Graphics.Dc) as Void {
        var icon = map.bloodhoundTargetIcon();
        if (isVisible && icon != null) { dc.drawBitmap(locX, locY, WatchUi.loadResource(icon)); }
    }
}

class PickerDeleteGlyph extends WatchUi.Drawable {
    function initialize() {
        Drawable.initialize({:locX => 0, :locY => 0, :width => 24, :height => 24});
    }
    function draw(dc as Graphics.Dc) as Void {
        if (!isVisible) { return; }
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(locX + 5, locY + 6, locX + 19, locY + 6);
        dc.drawRectangle(locX + 9, locY + 3, 6, 3);
        dc.drawRectangle(locX + 7, locY + 8, 10, 13);
        dc.drawLine(locX + 10, locY + 11, locX + 10, locY + 18);
        dc.drawLine(locX + 14, locY + 11, locX + 14, locY + 18);
    }
}

function addPickerTarget(menu as WatchUi.Menu2, map as StandaloneMapView, id as String) as Void {
    menu.addItem(new WatchUi.IconMenuItem(pickerTargetTitle(map, id), pickerTargetSubtitle(map, id), id,
        new PickerTypeGlyph(pickerTargetKind(map, id), pickerTargetActive(map, id)), null));
}

function addPickerAction(menu as WatchUi.Menu2, label as String, subLabel, id as Symbol, icon) as Void {
    menu.addItem(new WatchUi.IconMenuItem(label, subLabel, id, WatchUi.loadResource(icon), null));
}

function buildPickerTargetActions(map as StandaloneMapView, id as String) as WatchUi.Menu2 {
    var menu = createMenu(pickerTargetTitle(map, id));
    var located = map.routeStore.route(id) != null || map.pointLocations.hasKey(id);
    var reason = located ? null : WatchUi.loadResource(Rez.Strings.TextLocationUnavailable);
    addPickerAction(menu, WatchUi.loadResource(Rez.Strings.PickerShowOnMap), reason, :showOnMap, Rez.Drawables.PickerCrosshairIcon);
    addPickerAction(menu, WatchUi.loadResource(pickerTargetActive(map, id) ? Rez.Strings.TextStopBloodhound : Rez.Strings.TextBloodhound),
        reason, :track, pickerTargetActive(map, id) ? Rez.Drawables.PickerStopIcon : Rez.Drawables.PickerHoundIcon);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.PickerDetails), pickerTargetSubtitle(map, id), :details);
    menu.addItem(new WatchUi.IconMenuItem(WatchUi.loadResource(map.routeStore.route(id) != null
        ? Rez.Strings.RoutesRemove : Rez.Strings.IncomingPointRemove), null, :remove, new PickerDeleteGlyph(), null));
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

// Keep action effects testable without pushing simulator views.
function applyPickerTargetAction(map as StandaloneMapView, id as String, action as Symbol) as Boolean {
    if (!pickerTargetExists(map, id)) { map.routeUnavailable(); return false; }
    if (action == :remove && map.routeStore.route(id) == null) {
        if (map.incomingDetails.hasKey(id)) { map.removeIncomingPoint(id, true); return true; }
        return map.deletePoint(id);
    }
    if (action == :showOnMap) { return map.focusBloodhoundItem(id); }
    if (action == :track) {
        if (map.routeStore.route(id) != null) {
            if (!id.equals(map.followingRouteId)) { return false; }
            map.stopRoute();
        } else {
            if (!map.pointLocations.hasKey(id)) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.TextLocationUnavailable), null); return false;
            }
            map.toggleBloodhound(id);
        }
        return true;
    }
    return false;
}

class PickerTargetActionsDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var targetId as String;
    function initialize(view as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize(); map = view; targetId = id;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var action = item.getId();
        if (action == :cancel) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        if (!pickerTargetExists(map, targetId)) { map.routeUnavailable(); WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        if (action == :details) {
            if (map.routeStore.route(targetId) != null) { map.showRoute(targetId); }
            else { map.showPointTypeMenu(targetId); }
        } else if (action == :remove && map.routeStore.route(targetId) != null) {
            WatchUi.pushView(buildRouteRemovalMenu(map.routeStore.route(targetId)),
                new RouteRemovalDelegate(map, targetId), WatchUi.SLIDE_LEFT);
        } else if (action == :track && map.routeStore.route(targetId) != null && !targetId.equals(map.followingRouteId)) {
            map.showRouteFollow(targetId);
        } else if (action instanceof Symbol && applyPickerTargetAction(map, targetId, action)) {
            if (action == :remove) {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            } else if (action == :showOnMap) {
                WatchUi.pushView(map, new StandaloneMapDelegate(map, false, map.application), WatchUi.SLIDE_LEFT);
            } else if (pickerTargetActive(map, targetId)) {
                WatchUi.switchToView(new BloodhoundCompassView(map.application), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
            } else {
                WatchUi.switchToView(buildPickerTargetActions(map, targetId), new PickerTargetActionsDelegate(map, targetId), WatchUi.SLIDE_LEFT);
            }
        }
    }
}
