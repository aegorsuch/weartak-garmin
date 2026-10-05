import Toybox.Lang;
import Toybox.WatchUi;

function buildIncomingPointsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    return new IncomingPointsMenu(app);
}

class IncomingPointsMenu extends WatchUi.Menu2 {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.IncomingPointsTitle)});
        app = application;
        populate();
    }

    function onShow() as Void {
        while (getItem(0) != null) { deleteItem(0); }
        populate();
    }

    function populate() as Void {
        var map = app.getMapView();
        map.pruneIncomingEntities();
        addItem(new WatchUi.MenuItem(app.text(:bloodhoundCompass), null, :openCompass, null));
        var pointCount = 0;
        for (var i = map.incomingIds.size() - 1; i >= 0; i--) {
            var id = map.incomingIds[i] as String;
            var details = map.incomingDetails.get(id) as Dictionary;
            if (details.get("isPoint") != true) { continue; }
            pointCount += 1;
            var status = map.pendingIncomingPoints.indexOf(id) != -1
                ? WatchUi.loadResource(Rez.Strings.IncomingPointNew) : null;
            addItem(new WatchUi.MenuItem(map.incomingPointTitle(id), status, id, null));
        }
        if (pointCount == 0) {
            addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.IncomingPointsEmpty), null, :empty, null));
        }
    }
}

function buildIncomingPointActions(map as StandaloneMapView, id as String) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => map.incomingPointTitle(id)});
    addMenuEntry(menu, map.application.text(:range), map.getPointDistanceLabel(id), :range);
    var details = map.incomingDetails.get(id);
    if (details instanceof Dictionary && details.get("isPoint")) {
        addMenuEntry(menu, "RGR", WatchUi.loadResource(Rez.Strings.IncomingPointRgr), :rgr);
        if (map.isBloodhoundTarget(id)) {
            addMenuEntry(menu, "nPos", WatchUi.loadResource(Rez.Strings.IncomingPointNpos), :npos);
        }
    }
    addMenuEntry(menu, map.isBloodhoundTarget(id) ? map.application.text(:stopBloodhound)
        : map.application.text(:bloodhound), null, :track);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.IncomingPointRemove), null, :remove);
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
        if (id == :openCompass) {
            WatchUi.pushView(new BloodhoundCompassView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
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
