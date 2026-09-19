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
    var hasInitialPosition = false;
    var currentPosition = null;
    var bloodhoundPointId = null;
    var application;
    var bloodhoundProximityNotified = false;
    var entityPruneTimer;
    var mapAreaDirty = true;
    var markersDirty = true;

    function initialize() {
        WatchUi.MapView.initialize();
        screenWidth = System.getDeviceSettings().screenWidth;
        screenHeight = System.getDeviceSettings().screenHeight;
        setScreenVisibleArea(0, 0, screenWidth, screenHeight);
        setMapMode(WatchUi.MAP_MODE_PREVIEW);
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
        currentPosition = info.position;
        evaluateBloodhoundProximity();

        if (!hasInitialPosition) {
            centerOn(info.position);
        }
        WatchUi.requestUpdate();
    }

    function setTakClient(client as TakClient) as Void {
        takClient = client;
    }

    function setApplication(app as StandaloneApp) as Void {
        application = app;
    }

    function evaluateBloodhoundProximity() as Void {
        if (application == null || !isBloodhoundActive()) {
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
        WatchUi.showToast(application.text(:proximity), null);
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
        var menu = new WatchUi.Menu2({:title => application.text(:pointTitle)});
        menu.addItem(new WatchUi.MenuItem(bloodhoundPointId != null && bloodhoundPointId.equals(pointId) ? application.text(:stopBloodhound) : application.text(:bloodhound), null, :bloodhound, null));
        var location = pointLocations.get(pointId);
        menu.addItem(new WatchUi.MenuItem(application.text(:latLon), latLonLabel(location), :coordinates, null));
        menu.addItem(new WatchUi.MenuItem(application.text(:mgrs), mgrsLabel(location), :coordinates, null));
        menu.addItem(new WatchUi.MenuItem(application.text(:setTitle), getPointText(pointId, "title"), :title, null));
        menu.addItem(new WatchUi.MenuItem(application.text(:setRemark), getPointText(pointId, "remark"), :remark, null));
        menu.addItem(new WatchUi.MenuItem(application.text(:setType), getPointTypeLabel(pointId), :type, null));
        menu.addItem(new WatchUi.MenuItem(application.text(:delete), null, :delete, null));
        WatchUi.pushView(menu, new PointMenuDelegate(self, pointId), WatchUi.SLIDE_UP);
    }

    function showSelfMenu() as Void {
        if (currentPosition != null) {
            showCoordinateMenu(application.text(:self), currentPosition);
        }
    }

    function toggleBloodhound(pointId) as Void {
        if (bloodhoundPointId != null && bloodhoundPointId.equals(pointId)) {
            bloodhoundPointId = null;
        } else {
            bloodhoundPointId = pointId;
        }
        bloodhoundProximityNotified = false;
        WatchUi.requestUpdate();
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
        var span = 0.05;
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
            clear();
            if (currentMarkers.size() > 0) {
                setMapMarker(currentMarkers);
            }
            markersDirty = false;
        }
        WatchUi.MapView.onUpdate(dc);
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
        drawControl(dc, controlMargin, top, "+");
        drawCenterControl(dc, controlMargin, top + controlSize + controlGap);
        drawControl(dc, controlMargin, top + (controlSize + controlGap) * 2, "-");
        drawBackControl(dc, screenWidth - controlSize - controlMargin, (screenHeight - controlSize) / 2);
        drawBloodhound(dc);
    }

    function drawBloodhound(dc) as Void {
        if (bloodhoundPointId == null || currentPosition == null || pointLocations.hasKey(bloodhoundPointId) == false) {
            return;
        }
        var target = pointLocations.get(bloodhoundPointId);
        var rangeMeters = distanceMeters(currentPosition, target).toNumber();
        var bearing = bearingDegrees(currentPosition, target).toNumber();
        var title = getPointText(bloodhoundPointId, "title");
        if (title.equals("")) {
            title = "Bloodhound";
        }
        var panelHeight = 58;
        var panelTop = screenHeight - panelHeight - 4;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(4, panelTop, screenWidth - 8, panelHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(4, panelTop, screenWidth - 8, panelHeight);
        dc.drawText(screenWidth / 2, panelTop + 4, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(screenWidth / 2, panelTop + 22, Graphics.FONT_XTINY, "Range " + rangeMeters.toString() + " m", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(screenWidth / 2, panelTop + 40, Graphics.FONT_XTINY, "Bearing " + bearing.toString() + " deg", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function isBloodhoundPanelAt(x, y) as Boolean {
        return isBloodhoundActive() && y >= screenHeight - 62 && y < screenHeight - 4 && x >= 4 && x < screenWidth - 4;
    }

    function showBloodhoundCancelMenu() as Void {
        var menu = new WatchUi.Menu2({:title => application.text(:bloodhoundCompass)});
        menu.addItem(new WatchUi.MenuItem(application.text(:cancelBloodhound), null, :cancelBloodhound, null));
        WatchUi.pushView(menu, new BloodhoundCancelDelegate(self), WatchUi.SLIDE_UP);
    }

    function distanceMeters(fromLocation, toLocation) {
        var fromDegrees = fromLocation.toDegrees();
        var toDegrees = toLocation.toDegrees();
        var fromLat = Math.toRadians(fromDegrees[0]);
        var toLat = Math.toRadians(toDegrees[0]);
        var deltaLat = Math.toRadians(toDegrees[0] - fromDegrees[0]);
        var deltaLon = Math.toRadians(toDegrees[1] - fromDegrees[1]);
        var sinHalfLat = Math.sin(deltaLat / 2);
        var sinHalfLon = Math.sin(deltaLon / 2);
        var a = sinHalfLat * sinHalfLat + Math.cos(fromLat) * Math.cos(toLat) * sinHalfLon * sinHalfLon;
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371000 * c;
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
        return bloodhoundPointId != null && currentPosition != null && pointLocations.hasKey(bloodhoundPointId);
    }

    function getBloodhoundTitle() as String {
        if (bloodhoundPointId == null || pointDetails.hasKey(bloodhoundPointId) == false) {
            return "Bloodhound";
        }
        var title = getPointText(bloodhoundPointId, "title");
        return title.equals("") ? "Bloodhound" : title;
    }

    function getBloodhoundRangeMeters() as Number {
        if (!isBloodhoundActive()) {
            return 0;
        }
        return distanceMeters(currentPosition, pointLocations.get(bloodhoundPointId)).toNumber();
    }

    function getBloodhoundBearingDegrees() as Number {
        if (!isBloodhoundActive()) {
            return 0;
        }
        return bearingDegrees(currentPosition, pointLocations.get(bloodhoundPointId)).toNumber();
    }

    function showCoordinateMenu(title as String, location) as Void {
        var menu = new WatchUi.Menu2({:title => title});
        menu.addItem(new WatchUi.MenuItem("Lat/Lon", latLonLabel(location), :coordinates, null));
        menu.addItem(new WatchUi.MenuItem("MGRS", mgrsLabel(location), :coordinates, null));
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
        var zone = Math.floor((longitude + 180) / 6).toNumber() + 1;
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
        var n = a / Math.sqrt(1 - eccSquared * Math.sin(latRad) * Math.sin(latRad));
        var t = Math.tan(latRad) * Math.tan(latRad);
        var c = eccPrimeSquared * Math.cos(latRad) * Math.cos(latRad);
        var aa = Math.cos(latRad) * (lonRad - lonOriginRad);
        var m = a * ((1 - eccSquared / 4 - 3 * Math.pow(eccSquared, 2) / 64 - 5 * Math.pow(eccSquared, 3) / 256) * latRad
            - (3 * eccSquared / 8 + 3 * Math.pow(eccSquared, 2) / 32 + 45 * Math.pow(eccSquared, 3) / 1024) * Math.sin(2 * latRad)
            + (15 * Math.pow(eccSquared, 2) / 256 + 45 * Math.pow(eccSquared, 3) / 1024) * Math.sin(4 * latRad)
            - (35 * Math.pow(eccSquared, 3) / 3072) * Math.sin(6 * latRad));
        var easting = k0 * n * (aa + (1 - t + c) * Math.pow(aa, 3) / 6 + (5 - 18 * t + t * t + 72 * c - 58 * eccPrimeSquared) * Math.pow(aa, 5) / 120) + 500000;
        var northing = k0 * (m + n * Math.tan(latRad) * (aa * aa / 2 + (5 - t + 9 * c + 4 * c * c) * Math.pow(aa, 4) / 24 + (61 - 58 * t + t * t + 600 * c - 330 * eccPrimeSquared) * Math.pow(aa, 6) / 720));
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
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            addPoint(info.position, :unknown, "Unknown 2525D point");
            return true;
        }
        return false;
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
        WatchUi.showToast(application != null ? application.text(:pointDropped) : "2525D point dropped", null);
        WatchUi.requestUpdate();
    }

    function isControlAt(x, y) {
        return isZoomInControlAt(x, y) || isZoomOutControlAt(x, y) || isCenterControlAt(x, y) || isBackControlAt(x, y);
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

    function isSelfAtScreen(x, y) as Boolean {
        if (currentPosition == null) {
            return false;
        }
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var location = currentPosition.toDegrees();
        var markerX = (location[1] - topLeft[1]) / (bottomRight[1] - topLeft[1]) * screenWidth;
        var markerY = (topLeft[0] - location[0]) / (topLeft[0] - bottomRight[0]) * screenHeight;
        var dx = markerX - x;
        var dy = markerY - y;
        return dx * dx + dy * dy <= 14 * 14;
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
        if (bloodhoundPointId != null && bloodhoundPointId.equals(id)) {
            bloodhoundPointId = null;
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
        bloodhoundPointId = null;
        bloodhoundProximityNotified = false;
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
            WatchUi.pushView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
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
        if (view.isBloodhoundPanelAt(coordinates[0], coordinates[1])) {
            view.showBloodhoundCancelMenu();
            return true;
        }
        if (view.isControlAt(coordinates[0], coordinates[1])) {
            if (view.isZoomInControlAt(coordinates[0], coordinates[1])) {
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
        var pointId = view.pointAtScreen(coordinates[0], coordinates[1]);
        if (pointId != null) {
            view.showPointTypeMenu(pointId);
            return true;
        }
        if (view.isSelfAtScreen(coordinates[0], coordinates[1])) {
            view.showSelfMenu();
            return true;
        }
        return true;
    }

    function onHold(evt) {
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
        } else if (id == :bloodhound) {
            view.toggleBloodhound(pointId);
        } else if (id == :coordinates) {
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
