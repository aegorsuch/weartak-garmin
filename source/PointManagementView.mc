import Toybox.Lang;
import Toybox.WatchUi;

function buildDroppedMarkersMenu(mapView as StandaloneMapView) as WatchUi.Menu2 {
    var menu = createMenu("Dropped Markers");
    var ids = mapView.getOrderedPointIds();
    if (ids.size() == 0) {
        addMenuEntry(menu, "No dropped markers", null, :noDroppedMarkers);
    } else {
        for (var index = 0; index < ids.size(); index++) {
            var id = ids[index] as String;
            var title = mapView.getPointText(id, "title");
            var sublabel = mapView.getPointTypeShortLabel(id) + " | " + mapView.getPointLocalTime(id);
            menu.addItem(new WatchUi.MenuItem(title, sublabel, index, mapView.getPointIcon(id)));
        }
        addMenuEntry(menu, "Clear All Markers", null, :clearAllMarkers);
    }
    addMenuEntry(menu, "Back", null, :backDroppedMarkers);
    return menu;
}

class DroppedMarkersMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var menu as WatchUi.Menu2;

    function initialize(map as StandaloneMapView, markersMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mapView = map;
        menu = markersMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :backDroppedMarkers) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :clearAllMarkers) {
            var confirm = createMenu("Clear All Markers?");
            addMenuEntry(confirm, "Clear All Markers", null, :confirmClearAll);
            addMenuEntry(confirm, "Cancel", null, :cancelClearAll);
            WatchUi.pushView(confirm, new PointDeletionConfirmationDelegate(mapView, :all), WatchUi.SLIDE_UP);
        } else if (id instanceof Number) {
            var ids = mapView.getOrderedPointIds();
            var index = id as Number;
            if (index >= 0 && index < ids.size()) {
                var pointId = ids[index] as String;
                var actionMenu = createMenu(mapView.getPointText(pointId, "title"));
                addMenuEntry(actionMenu, "Edit...", null, :editDroppedMarker);
                addMenuEntry(actionMenu, "Delete Marker", null, :deleteDroppedMarker);
                addMenuEntry(actionMenu, "Back", null, :backDroppedMarkerAction);
                WatchUi.pushView(actionMenu, new DroppedMarkerActionDelegate(mapView, pointId, actionMenu), WatchUi.SLIDE_LEFT);
            }
        }
    }
}

class DroppedMarkerActionDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var pointId as String;
    var menu as WatchUi.Menu2;

    function initialize(map as StandaloneMapView, id as String, actionMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mapView = map;
        pointId = id;
        menu = actionMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :editDroppedMarker) {
            mapView.showPointTypeMenu(pointId);
        } else if (item.getId() == :deleteDroppedMarker) {
            var confirm = createMenu("Delete Marker?");
            addMenuEntry(confirm, "Delete Marker", null, :confirmDeleteDroppedMarker);
            addMenuEntry(confirm, "Cancel", null, :cancelDeleteDroppedMarker);
            WatchUi.pushView(confirm, new PointDeletionConfirmationDelegate(mapView, pointId), WatchUi.SLIDE_UP);
        } else if (item.getId() == :backDroppedMarkerAction) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class PointDeletionConfirmationDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var deletion as Object;

    function initialize(map as StandaloneMapView, deleteTarget as Object) {
        Menu2InputDelegate.initialize();
        mapView = map;
        deletion = deleteTarget;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var confirmed = id == :confirmClearLast || id == :confirmClearAll || id == :confirmDeleteDroppedMarker;
        if (confirmed) {
            if (deletion == :last) {
                if (!mapView.deleteLastPoint()) { return; }
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            } else if (deletion == :all) {
                if (!mapView.clearDroppedPoints()) { return; }
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                var list = buildDroppedMarkersMenu(mapView);
                WatchUi.pushView(list, new DroppedMarkersMenuDelegate(mapView, list), WatchUi.SLIDE_LEFT);
            } else {
                if (!mapView.deletePoint(deletion as String)) { return; }
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                var list = buildDroppedMarkersMenu(mapView);
                WatchUi.switchToView(list, new DroppedMarkersMenuDelegate(mapView, list), WatchUi.SLIDE_LEFT);
            }
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}