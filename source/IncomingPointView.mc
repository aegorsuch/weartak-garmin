import Toybox.Lang;
import Toybox.WatchUi;

function buildIncomingPointsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    return new IncomingPointsMenu(app);
}

class IncomingPointsMenu extends WatchUi.Menu2 {
    var app as StandaloneApp;
    var refreshing as Boolean = false;

    function initialize(application as StandaloneApp) {
        Menu2.initialize({:title => application.text(Rez.Strings.TextBloodhound)});
        app = application;
        populate();
    }

    function onShow() as Void {
        app.incomingPointsMenu = self;
        refresh();
    }

    function onHide() as Void {
        if (app.incomingPointsMenu == self) { app.incomingPointsMenu = null; }
    }

    function refresh() as Void {
        if (refreshing) { return; }
        refreshing = true;
        var focusedItem = mFocus == null ? null : getItem(mFocus);
        var focusedId = focusedItem == null ? null : focusedItem.getId();
        while (getItem(0) != null) { deleteItem(0); }
        populate();
        for (var i = 0; getItem(i) != null; i++) {
            var item = getItem(i);
            if (item != null && item.getId() == focusedId) {
                setFocus(i);
                break;
            }
        }
        refreshing = false;
    }

    function populate() as Void {
        var map = app.getMapView();
        map.pruneIncomingEntities();
        map.markIncomingPointsSeen();
        var pointCount = 0;
        addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.IncomingPointsRemoveAll), null, :removeAll, null));
        for (var alertIndex = map.incomingIds.size() - 1; alertIndex >= 0; alertIndex--) {
            var alertId = map.incomingIds[alertIndex] as String;
            var alertDetails = map.incomingDetails.get(alertId) as Dictionary;
            if (alertDetails.get("isAlert") != true) { continue; }
            pointCount += 1;
            addItem(new WatchUi.MenuItem(map.incomingPointTitle(alertId), map.incomingPointDetailLabel(alertId), alertId, null));
        }
        for (var i = map.incomingIds.size() - 1; i >= 0; i--) {
            var id = map.incomingIds[i] as String;
            var details = map.incomingDetails.get(id) as Dictionary;
            if (details.get("isPoint") != true) { continue; }
            pointCount += 1;
            addItem(new WatchUi.MenuItem(map.incomingPointTitle(id), map.incomingPointDetailLabel(id), id, null));
        }
        if (pointCount == 0) {
            addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.IncomingPointsEmpty), null, :empty, null));
        }
    }
}

function buildIncomingPointActions(map as StandaloneMapView, id as String) as WatchUi.Menu2 {
    var menu = createMenu(map.incomingPointTitle(id));
    var details = map.incomingDetails.get(id);
    var isAlert = details instanceof Dictionary && details.get("isAlert") == true;
    var hasLocation = map.pointLocations.hasKey(id);
    if (hasLocation) {
        addMenuEntry(menu, map.application.text(Rez.Strings.TextRange), map.getPointDistanceLabel(id), :range);
    }
    if (details instanceof Dictionary && details.get("isPoint")) {
        addMenuEntry(menu, "RGR", WatchUi.loadResource(Rez.Strings.IncomingPointRgr), :rgr);
        if (map.isBloodhoundTarget(id)) {
            addMenuEntry(menu, "nPos", WatchUi.loadResource(Rez.Strings.IncomingPointNpos), :npos);
        }
    }
    if (hasLocation) {
        addMenuEntry(menu, map.isBloodhoundTarget(id) ? map.application.text(Rez.Strings.TextStopBloodhound)
            : map.application.text(isAlert ? Rez.Strings.IncomingAlertBloodhound : Rez.Strings.TextBloodhound),
            null, :track);
    }
    addMenuEntry(menu, WatchUi.loadResource(isAlert
        ? Rez.Strings.IncomingAlertDismiss : Rez.Strings.IncomingPointRemove), null, :remove);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
    return menu;
}

class IncomingPointsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :removeAll) {
            app.getMapView().removeAllIncomingPoints();
            WatchUi.switchToView(buildIncomingPointsMenu(app), new IncomingPointsDelegate(app), WatchUi.SLIDE_RIGHT);
        } else if (id instanceof String) {
            app.getMapView().pruneIncomingEntities();
            if (!app.getMapView().incomingDetails.hasKey(id)) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
                WatchUi.switchToView(buildIncomingPointsMenu(app), new IncomingPointsDelegate(app), WatchUi.SLIDE_RIGHT);
                return;
            }
            app.getMapView().showPointTypeMenu(id);
        }
    }
}

class IncomingPointActionsDelegate extends WatchUi.Menu2InputDelegate {
    var map as StandaloneMapView;
    var pointId as String;

    function initialize(mapView as StandaloneMapView, id as String) {
        Menu2InputDelegate.initialize();
        map = mapView;
        pointId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        map.pruneIncomingEntities();
        var id = item.getId();
        if (!map.incomingDetails.hasKey(pointId)) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        if (id == :rgr) {
            if (!map.acknowledgeIncomingPoint(pointId)) { return; }
            WatchUi.switchToView(buildIncomingPointActions(map, pointId),
                new IncomingPointActionsDelegate(map, pointId), WatchUi.SLIDE_LEFT);
        } else if (id == :npos) {
            if (map.markIncomingPointInPosition(pointId)) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        } else if (id == :remove) {
            map.removeIncomingPoint(pointId, true);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :track) {
            if (!map.pointLocations.hasKey(pointId)) {
                WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingAlertNoLocation), null);
                return;
            }
            map.toggleBloodhound(pointId);
            map.pendingIncomingPoints.remove(pointId);
            map.application.refreshIncomingPointCount();
            WatchUi.switchToView(buildIncomingPointActions(map, pointId),
                new IncomingPointActionsDelegate(map, pointId), WatchUi.SLIDE_LEFT);
        } else if (id == :cancel) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
