import Toybox.Graphics;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class StandaloneMapMarker extends WatchUi.MapMarker {
    function initialize(location) {
        MapMarker.initialize(location);
    }
}

class StandaloneMapView extends WatchUi.MapView {
    var screenWidth;
    var screenHeight;
    var mapTopLeft;
    var mapBottomRight;
    var markers = {};
    var pointLocations = {};
    var pointDetails = {};
    var incomingIds = [];
    var incomingLastSeen = {};
    var nextPointNumber = 1;
    var takClient as TakClient? = null;
    var controlSize = 40;
    var controlGap = 6;
    var controlMargin = 8;
    var mapButtonsVisible = true;
    var hasInitialPosition = false;
    var entityPruneTimer;
    var mapAreaDirty = true;
    var markersDirty = true;

    function initialize() {
        WatchUi.MapView.initialize();
        screenWidth = System.getDeviceSettings().screenWidth;
        screenHeight = System.getDeviceSettings().screenHeight;
        setScreenVisibleArea(0, 0, screenWidth, screenHeight);
        setMapMode(WatchUi.MAP_MODE_BROWSE);
        var currentInfo = Position.getInfo();
        centerOn(currentInfo != null && currentInfo.position != null ? currentInfo.position : null);
        setMapVisibleArea(mapTopLeft, mapBottomRight);
        mapAreaDirty = false;
        entityPruneTimer = new Timer.Timer();
        entityPruneTimer.start(method(:pruneIncomingEntitiesOnTimer), 60000, true);
    }

    function updatePosition(info) {
        if (info == null || info.position == null) {
            return;
        }

        if (!hasInitialPosition) {
            centerOn(info.position);
        }

        var selfMarker = new StandaloneMapMarker(info.position);
        var selfIcon = WatchUi.loadResource(Rez.Drawables.TargetIcon);
        selfMarker.setIcon(selfIcon, selfIcon.getWidth() / 2, selfIcon.getHeight() / 2);
        selfMarker.setLabel("SELF");
        markers.put("self", selfMarker);
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function setTakClient(client as TakClient) as Void {
        takClient = client;
    }

    function showPointTypeMenu(pointId) as Void {
        var menu = new WatchUi.Menu2({:title => "2525D Point"});
        menu.addItem(new WatchUi.MenuItem("Set Title", getPointText(pointId, "title"), :title, null));
        menu.addItem(new WatchUi.MenuItem("Set Remark", getPointText(pointId, "remark"), :remark, null));
        menu.addItem(new WatchUi.MenuItem("Set Type", getPointTypeLabel(pointId), :type, null));
        menu.addItem(new WatchUi.MenuItem("Delete", null, :delete, null));
        WatchUi.pushView(menu, new PointMenuDelegate(self, pointId), WatchUi.SLIDE_UP);
    }

    function updateIncomingCot(uid as String, latitude, longitude, cotType as String) as Void {
        var markerId = "cot-" + uid;
        var location = new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees});
        var marker = new StandaloneMapMarker(location);
        var icon = cotType.find("a-h-") != null ? iconForType(:hostile) : cotType.find("a-f-") != null ? iconForType(:friendly) : iconForType(:unknown);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(uid);
        if (!markers.hasKey(markerId)) {
            incomingIds.add(markerId);
            if (incomingIds.size() > 50) {
                var oldestId = incomingIds.remove(0);
                markers.remove(oldestId);
                incomingLastSeen.remove(oldestId);
            }
        }
        incomingLastSeen.put(markerId, Time.now().value());
        markers.put(markerId, marker);
        pruneIncomingEntities();
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function centerOn(position) {
        var center = [0.0, 0.0];
        hasInitialPosition = position != null;
        if (position != null) {
            center = position.toDegrees();
        }
        var span = 0.005;
        mapTopLeft = new Position.Location({:latitude => center[0] + span, :longitude => center[1] - span, :format => :degrees});
        mapBottomRight = new Position.Location({:latitude => center[0] - span, :longitude => center[1] + span, :format => :degrees});
        mapAreaDirty = true;
    }

    function onUpdate(dc) {
        if (mapAreaDirty) {
            setMapVisibleArea(mapTopLeft, mapBottomRight);
            mapAreaDirty = false;
        }
        if (markersDirty) {
            var currentMarkers = markerArray();
            if (currentMarkers.size() > 0) {
                setMapMarker(currentMarkers);
            }
            markersDirty = false;
        }
        WatchUi.MapView.onUpdate(dc);
    }

    function drawControl(dc, x, y, label) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawText(x + controlSize / 2, y + 4, Graphics.FONT_LARGE, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawTargetControl(dc, x, y) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        var centerX = x + controlSize / 2;
        var centerY = y + controlSize / 2;
        dc.drawCircle(centerX, centerY, 11);
        dc.drawLine(centerX - 16, centerY, centerX - 5, centerY);
        dc.drawLine(centerX + 5, centerY, centerX + 16, centerY);
        dc.drawLine(centerX, centerY - 16, centerX, centerY - 5);
        dc.drawLine(centerX, centerY + 5, centerX, centerY + 16);
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

    function dropAtCurrentLocation() {
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            addPoint(info.position, :unknown, "Unknown 2525D point");
        }
    }

    function snapToSelf() {
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
        addPoint(new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees}), :unknown, "Unknown 2525D point");
        WatchUi.showToast("Point dropped", null);
        WatchUi.requestUpdate();
    }

    function isControlAt(x, y) {
        var left = controlMargin;
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
        var right = screenWidth - controlSize - controlMargin;
        var backTop = (screenHeight - controlSize) / 2;
        var onLeftControls = mapButtonsVisible && x >= left && x < left + controlSize && y >= top && y < top + controlSize * 3 + controlGap * 2;
        var onBackControl = x >= right && x < right + controlSize && y >= backTop && y < backTop + controlSize;
        return onLeftControls || onBackControl;
    }

    function toggleMapButtons() as Void {
        mapButtonsVisible = !mapButtonsVisible;
        WatchUi.requestUpdate();
    }

    function addPoint(location, type, label) {
        var id = "point-" + nextPointNumber.toString();
        nextPointNumber += 1;
        var marker = new StandaloneMapMarker(location);
        var icon = iconForType(type);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(label);
        markers.put(id, marker);
        pointLocations.put(id, location);
        pointDetails.put(id, {"type" => type, "title" => label, "remark" => ""});
        markersDirty = true;
        if (takClient != null) {
            takClient.sendMarker(id, location, type, label, "");
        }
        WatchUi.requestUpdate();
    }

    function iconForType(type) {
        if (type == :friendly) {
            return WatchUi.loadResource(Rez.Drawables.FriendlyIcon);
        } else if (type == :hostile) {
            return WatchUi.loadResource(Rez.Drawables.HostileIcon);
        } else if (type == :obstacle) {
            return WatchUi.loadResource(Rez.Drawables.ObstacleIcon);
        }
        return WatchUi.loadResource(Rez.Drawables.UnknownIcon);
    }

    function markerArray() as Array {
        var result = [];
        var ids = markers.keys();
        for (var i = 0; i < ids.size(); i++) {
            result.add(markers.get(ids[i]));
        }
        return result;
    }

    function pointAtScreen(x, y) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var keys = pointLocations.keys();
        for (var i = 0; i < keys.size(); i++) {
            var location = pointLocations.get(keys[i]).toDegrees();
            var markerX = (location[1] - topLeft[1]) / (bottomRight[1] - topLeft[1]) * screenWidth;
            var markerY = (topLeft[0] - location[0]) / (topLeft[0] - bottomRight[0]) * screenHeight;
            var dx = markerX - x;
            var dy = markerY - y;
            if (dx * dx + dy * dy <= 14 * 14) {
                return keys[i];
            }
        }
        return null;
    }

    function changePointType(id, type, label) {
        if (pointLocations.hasKey(id) == false || pointDetails.hasKey(id) == false) {
            return;
        }
        var details = pointDetails.get(id) as Dictionary;
        var currentType = details.get("type") as Symbol;
        var currentTitle = safeDetailString(details, "title", "");
        details.put("type", type);
        if (currentTitle.equals("") || currentTitle.equals(defaultPointTitle(currentType))) {
            details.put("title", defaultPointTitle(type));
        }
        updatePoint(id, details);
    }

    function defaultPointTitle(type as Symbol) as String {
        if (type == :friendly) {
            return "Friendly 2525D point";
        } else if (type == :hostile) {
            return "Hostile 2525D point";
        } else if (type == :obstacle) {
            return "Obstacle 2525D point";
        }
        return "Unknown 2525D point";
    }

    function updatePointText(id, field, value) {
        if (pointLocations.hasKey(id) == false || pointDetails.hasKey(id) == false) {
            return;
        }
        var details = pointDetails.get(id) as Dictionary;
        if (field.equals("title") && value.equals("")) {
            value = defaultPointTitle(details.get("type") as Symbol);
        }
        details.put(field, value);
        updatePoint(id, details);
    }

    function getPointText(id, field) as String {
        if (pointDetails.hasKey(id) == false) {
            return "";
        }
        var value = (pointDetails.get(id) as Dictionary).get(field);
        return value == null ? "" : value.toString();
    }

    function getPointTypeLabel(id) as String {
        if (pointDetails.hasKey(id) == false) {
            return "Unknown 2525D point";
        }
        var details = pointDetails.get(id) as Dictionary;
        var type = details.get("type");
        if (type == null) {
            return "Unknown 2525D point";
        }
        return defaultPointTitle(type as Symbol);
    }

    function safeDetailString(details as Dictionary, key as String, fallback as String) as String {
        var value = details.get(key);
        if (value == null) {
            return fallback;
        }
        return value.toString();
    }

    function updatePoint(id, details as Dictionary) {
        var location = pointLocations.get(id);
        var type = details.get("type") as Symbol;
        var title = safeDetailString(details, "title", defaultPointTitle(type));
        var remark = safeDetailString(details, "remark", "");
        var marker = new StandaloneMapMarker(location);
        var icon = iconForType(type);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(title);
        markers.put(id, marker);
        markersDirty = true;
        if (takClient != null) {
            takClient.sendMarker(id, location, type, title, remark);
        }
        WatchUi.requestUpdate();
    }

    function deletePoint(id) {
        if (pointLocations.hasKey(id) == false) {
            return;
        }
        markers.remove(id);
        pointLocations.remove(id);
        pointDetails.remove(id);
        if (takClient != null) {
            takClient.deleteMarker(id);
        }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function clearDroppedPoints() {
        var pointIds = pointLocations.keys();
        for (var i = 0; i < pointIds.size(); i++) {
            markers.remove(pointIds[i]);
            if (takClient != null) {
                takClient.deleteMarker(pointIds[i]);
            }
        }
        pointLocations = {};
        pointDetails = {};
        markersDirty = true;

        var waypoints = PersistedContent.getAppWaypoints();
        var waypoint = waypoints.next();
        while (waypoint != null) {
            waypoint.remove();
            waypoint = waypoints.next();
        }
        WatchUi.requestUpdate();
    }

    function pruneIncomingEntities() as Boolean {
        var now = Time.now().value();
        var staleIds = [];
        var ids = incomingLastSeen.keys();
        for (var i = 0; i < ids.size(); i++) {
            if (now - incomingLastSeen.get(ids[i]) > 300) {
                staleIds.add(ids[i]);
            }
        }
        for (var j = 0; j < staleIds.size(); j++) {
            markers.remove(staleIds[j]);
            incomingLastSeen.remove(staleIds[j]);
            incomingIds.remove(staleIds[j]);
        }
        if (staleIds.size() > 0) {
            markersDirty = true;
        }
        return staleIds.size() > 0;
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
        mapAreaDirty = true;
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
        mapAreaDirty = true;
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
        mapAreaDirty = true;
        WatchUi.requestUpdate();
    }
}

class StandaloneMapDelegate extends WatchUi.InputDelegate {
    var view;
    var app as StandaloneApp;
    var openMainMenuOnBack = false;
    var lastDragX;
    var lastDragY;
    var isDragging = false;

    function initialize(mapView, showMainMenuOnBack as Boolean, application as StandaloneApp) {
        WatchUi.InputDelegate.initialize();
        view = mapView;
        openMainMenuOnBack = showMainMenuOnBack;
        app = application;
    }

    function leaveMap() as Void {
        if (openMainMenuOnBack) {
            WatchUi.pushView(buildMainMenu(), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function onTap(evt) {
        if (isDragging) {
            isDragging = false;
            lastDragX = null;
            lastDragY = null;
            return true;
        }
        var coordinates = evt.getCoordinates();
        var pointId = view.pointAtScreen(coordinates[0], coordinates[1]);
        if (pointId != null) {
            view.showPointTypeMenu(pointId);
            return true;
        }
        return true;
    }

    function onHold(evt) {
        var coordinates = evt.getCoordinates();
        if (view.isControlAt(coordinates[0], coordinates[1])) {
            return false;
        }
        view.dropAtScreen(coordinates[0], coordinates[1]);
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

class LayersMenuView extends WatchUi.View {
    var mapView;

    function initialize(mapView) {
        View.initialize();
        self.mapView = mapView;
    }

    function onUpdate(dc) {
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        var rowTop = 45;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 0, width, height);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 10, Graphics.FONT_MEDIUM, "Layers Menu", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(18, rowTop + 8, Graphics.FONT_SMALL, "Map Buttons", Graphics.TEXT_JUSTIFY_LEFT);
        drawEye(dc, width - 30, rowTop + 18, mapView.mapButtonsVisible);
        dc.drawLine(12, rowTop + 40, width - 12, rowTop + 40);
    }

    function drawEye(dc, centerX, centerY, visible) {
        var color = visible ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawEllipse(centerX - 12, centerY - 7, 24, 14);
        dc.drawCircle(centerX, centerY, 4);
        if (!visible) {
            dc.drawLine(centerX - 14, centerY - 12, centerX + 14, centerY + 12);
        }
    }
}

class LayersMenuDelegate extends WatchUi.InputDelegate {
    var mapView;

    function initialize(mapView) {
        InputDelegate.initialize();
        self.mapView = mapView;
    }

    function onTap(evt) {
        var coordinates = evt.getCoordinates();
        if (coordinates[1] >= 45 && coordinates[1] < 85) {
            mapView.toggleMapButtons();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }
}

class PointMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view;
    var pointId;

    function initialize(mapView, id) {
        Menu2InputDelegate.initialize();
        view = mapView;
        pointId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :title) {
            WatchUi.pushView(new WatchUi.TextPicker(view.getPointText(pointId, "title")), new PointTextPickerDelegate(view, pointId, "title"), WatchUi.SLIDE_UP);
            return;
        } else if (id == :remark) {
            WatchUi.pushView(new WatchUi.TextPicker(view.getPointText(pointId, "remark")), new PointTextPickerDelegate(view, pointId, "remark"), WatchUi.SLIDE_UP);
            return;
        } else if (id == :type) {
            var typeMenu = new WatchUi.Menu2({:title => "Set Type"});
            typeMenu.addItem(new WatchUi.MenuItem("Friendly", null, :friendly, null));
            typeMenu.addItem(new WatchUi.MenuItem("Unknown", null, :unknown, null));
            typeMenu.addItem(new WatchUi.MenuItem("Hostile", null, :hostile, null));
            typeMenu.addItem(new WatchUi.MenuItem("Obstacle", null, :obstacle, null));
            WatchUi.pushView(typeMenu, new PointTypeMenuDelegate(view, pointId), WatchUi.SLIDE_LEFT);
            return;
        } else if (id == :delete) {
            view.deletePoint(pointId);
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
        } else if (id == :obstacle) {
            view.changePointType(pointId, :obstacle, "Obstacle 2525D point");
        } else {
            view.changePointType(pointId, :unknown, "Unknown 2525D point");
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
