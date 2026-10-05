import Toybox.Lang;
import Toybox.WatchUi;

function buildDroppedMarkersMenu(mapView as StandaloneMapView) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Dropped Markers"});
    var ids = mapView.getOrderedPointIds();
    if (ids.size() == 0) {
        menu.addItem(new WatchUi.MenuItem("No dropped markers", null, :noDroppedMarkers, null));
    } else {
        for (var index = 0; index < ids.size(); index++) {
            var id = ids[index] as String;
            var title = mapView.getPointText(id, "title");
            var sublabel = mapView.getPointTypeShortLabel(id) + " | " + mapView.getPointLocalTime(id);
            menu.addItem(new WatchUi.MenuItem(title, sublabel, index, mapView.getPointIcon(id)));
        }
        menu.addItem(new WatchUi.MenuItem("Clear All Markers", null, :clearAllMarkers, null));
    }
    menu.addItem(new WatchUi.MenuItem("Back", null, :backDroppedMarkers, null));
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
            var confirm = new WatchUi.Menu2({:title => "Clear All Markers?"});
            confirm.addItem(new WatchUi.MenuItem("Clear All Markers", null, :confirmClearAll, null));
            confirm.addItem(new WatchUi.MenuItem("Cancel", null, :cancelClearAll, null));
            WatchUi.pushView(confirm, new PointDeletionConfirmationDelegate(mapView, :all), WatchUi.SLIDE_UP);
        } else if (id instanceof Number) {
            var ids = mapView.getOrderedPointIds();
            var index = id as Number;
            if (index >= 0 && index < ids.size()) {
                var pointId = ids[index] as String;
                var actionMenu = new WatchUi.Menu2({:title => mapView.getPointText(pointId, "title")});
                actionMenu.addItem(new WatchUi.MenuItem("Edit...", null, :editDroppedMarker, null));
                actionMenu.addItem(new WatchUi.MenuItem("Delete Marker", null, :deleteDroppedMarker, null));
                actionMenu.addItem(new WatchUi.MenuItem("Back", null, :backDroppedMarkerAction, null));
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
            var confirm = new WatchUi.Menu2({:title => "Delete Marker?"});
            confirm.addItem(new WatchUi.MenuItem("Delete Marker", null, :confirmDeleteDroppedMarker, null));
            confirm.addItem(new WatchUi.MenuItem("Cancel", null, :cancelDeleteDroppedMarker, null));
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