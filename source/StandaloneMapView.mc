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
    var defaultPointType as Symbol = :unknown;
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
        if (currentInfo != null && currentInfo.position != null) {
            currentPosition = currentInfo.position;
        }
        centerOn(currentInfo != null && currentInfo.position != null ? currentInfo.position : null);
        setMapVisibleArea(mapTopLeft, mapBottomRight);
        mapAreaDirty = false;
        entityPruneTimer = new Timer.Timer();
        entityPruneTimer.start(method(:pruneIncomingEntitiesOnTimer), 60000, true);
        loadPoints();
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
        var ids = pointLocations.keys();
        for (var i = 0; i < ids.size(); i++) {
            var id = ids[i];
            var details = pointDetails.get(id) as Dictionary;
            var degrees = pointLocations.get(id).toDegrees();
            saved.add({
                "id" => id,
                "lat" => degrees[0],
                "lon" => degrees[1],
                "type" => typeToString(details.get("type") as Symbol),
                "title" => safeDetailString(details, "title", ""),
                "remark" => safeDetailString(details, "remark", ""),
                "droppedAt" => safeDetailString(details, "droppedAt", "Unknown")
            });
        }
        Application.Storage.setValue("droppedPoints", saved);
        Application.Storage.setValue("nextPointNumber", nextPointNumber);
    }

    function loadPoints() as Void {
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
            var marker = new StandaloneMapMarker(location);
            var icon = iconForType(type);
            marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
            marker.setLabel(title);
            markers.put(id, marker);
            pointLocations.put(id, location);
            pointDetails.put(id, {"type" => type, "title" => title, "remark" => entry.get("remark") as String, "droppedAt" => droppedAt == null ? "Unknown" : droppedAt.toString()});
        }
        var storedNextPointNumber = Application.Storage.getValue("nextPointNumber");
        if (storedNextPointNumber != null) {
            nextPointNumber = storedNextPointNumber as Number;
        }
        markersDirty = true;
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
        var menu = buildPointDetailsMenu(self, pointId);
        WatchUi.pushView(menu, new PointDetailsMenuDelegate(self, pointId, menu), WatchUi.SLIDE_LEFT);
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
            var currentInfo = Position.getInfo();
            if (currentInfo != null && currentInfo.position != null) {
                currentPosition = currentInfo.position;
            }
        }
        bloodhoundProximityNotified = false;
        evaluateBloodhoundProximity();
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
        applyMapVisibleArea();
    }

    function applyMapVisibleArea() as Void {
        setMapVisibleArea(mapTopLeft, mapBottomRight);
        mapAreaDirty = false;
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
        drawTeamOverlay(dc);
        var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
        drawControl(dc, controlMargin, top, "+");
        drawCenterControl(dc, controlMargin, top + controlSize + controlGap);
        drawControl(dc, controlMargin, top + (controlSize + controlGap) * 2, "-");
        drawBackControl(dc, screenWidth - controlSize - controlMargin, (screenHeight - controlSize) / 2);
        drawBloodhound(dc);
    }

    function drawTeamOverlay(dc) as Void {
        if (application == null || currentPosition == null || mapTopLeft == null || mapBottomRight == null) {
            return;
        }
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var selfDegrees = currentPosition.toDegrees();
        var markerX = ((selfDegrees[1] - topLeft[1]) / (bottomRight[1] - topLeft[1]) * screenWidth).toNumber();
        var markerY = ((topLeft[0] - selfDegrees[0]) / (topLeft[0] - bottomRight[0]) * screenHeight).toNumber();
        if (markerX < 0 || markerX >= screenWidth || markerY < 0 || markerY >= screenHeight) {
            return;
        }

        var teamColor = application.getMyTeamColorValue();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(markerX, markerY, 8);
        dc.setColor(teamColor, teamColor);
        dc.fillCircle(markerX, markerY, 5);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(markerX, markerY, 5);

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

    function drawBloodhound(dc) as Void {
        if (bloodhoundPointId == null || pointLocations.hasKey(bloodhoundPointId) == false) {
            return;
        }
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
        if (currentPosition == null) {
                dc.drawText(screenWidth / 2, panelTop + 30, Graphics.FONT_XTINY, application.text(:waitingForLocation), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var target = pointLocations.get(bloodhoundPointId);
            var rangeMeters = distanceMeters(currentPosition, target).toNumber();
            var bearing = bearingDegrees(currentPosition, target).toNumber();
            dc.drawText(screenWidth / 2, panelTop + 22, Graphics.FONT_XTINY, application.text(:range) + " " + rangeMeters.toString() + " m", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenWidth / 2, panelTop + 40, Graphics.FONT_XTINY, application.text(:bearing) + " " + bearing.toString() + " deg", Graphics.TEXT_JUSTIFY_CENTER);
        }
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
        return bloodhoundPointId != null && pointLocations.hasKey(bloodhoundPointId);
    }

    function getBloodhoundTitle() as String {
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
        var menu = new WatchUi.Menu2({:title => title});
        var degrees = location.toDegrees();
        menu.addItem(new WatchUi.MenuItem("Lat: " + degrees[0].format("%.5f"), null, :coordinates, null));
        menu.addItem(new WatchUi.MenuItem("Lon: " + degrees[1].format("%.5f"), null, :coordinates, null));
        menu.addItem(new WatchUi.MenuItem(mgrsLabel(location), null, :coordinates, null));
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
            var droppedAt = utcTimeLabel(Time.now());
            addPoint(info.position, defaultPointType, newPointTitle(droppedAt), droppedAt);
            return true;
        }
        return false;
    }

    function hasPoints() as Boolean {
        if (pointLocations == null) {
            return false;
        }
        var ids = pointLocations.keys();
        return ids != null && ids.size() > 0;
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
        var droppedAt = utcTimeLabel(Time.now());
        addPoint(new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees}), defaultPointType, newPointTitle(droppedAt), droppedAt);
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

    function addPoint(location, type, label, droppedAt as String) {
        if (location == null) {
            return;
        }
        var id = "point-" + nextPointNumber.toString();
        nextPointNumber += 1;
        var marker = new StandaloneMapMarker(location);
        var icon = iconForType(type);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(label);
        markers.put(id, marker);
        pointLocations.put(id, location);
        pointDetails.put(id, {"type" => type, "title" => label, "remark" => "", "droppedAt" => droppedAt});
        markersDirty = true;
        if (takClient != null) {
            takClient.sendMarker(id, location, type, label, "");
        }
        savePoints();
        WatchUi.requestUpdate();
    }

    function newPointTitle(droppedAt as String) as String {
        return application.getCallsign() + "_" + droppedAt;
    }

    function utcTimeLabel(moment as Time.Moment) as String {
        var timeInfo = Time.Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return timeInfo.hour.format("%02d") + timeInfo.min.format("%02d") + timeInfo.sec.format("%02d") + "Z";
    }

    function iconForType(type) {
        if (type == :friendly) {
            return WatchUi.loadResource(Rez.Drawables.FriendlyIcon);
        } else if (type == :hostile) {
            return WatchUi.loadResource(Rez.Drawables.HostileIcon);
        } else if (type == :neutral) {
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
        defaultPointType = type;
        Application.Storage.setValue("defaultPointType", typeToString(type));
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
            return application.text(:friendlyPoint);
        } else if (type == :hostile) {
            return application.text(:hostilePoint);
        } else if (type == :neutral) {
            return application.text(:neutralPoint);
        }
        return application.text(:unknownPoint);
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
            return application.text(:unknownPoint);
        }
        var details = pointDetails.get(id) as Dictionary;
        var type = details.get("type");
        if (type == null) {
            return application.text(:unknownPoint);
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
            return "-- km";
        }
        return (distanceMeters(currentPosition, location) / 1000.0).format("%.2f") + " km";
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
        var info = Position.getInfo();
        if (info == null || info.position == null || pointDetails.hasKey(id) == false) {
            return false;
        }
        currentPosition = info.position;
        pointLocations.put(id, info.position);
        updatePoint(id, pointDetails.get(id) as Dictionary);
        return true;
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
        savePoints();
        WatchUi.requestUpdate();
    }

    function deletePoint(id) {
        if (id == null || pointLocations == null || pointLocations.hasKey(id) == false) {
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
        savePoints();
        WatchUi.requestUpdate();
    }

    function clearDroppedPoints() {
        if (hasPoints()) {
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
            savePoints();
        }

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

function buildPointDetailsMenu(mapView as StandaloneMapView, pointId as String) as WatchUi.Menu2 {
    var title = mapView.getPointText(pointId, "title");
    var menu = new WatchUi.Menu2({:title => title});
    menu.addItem(new WatchUi.MenuItem(mapView.getPointTypeShortLabel(pointId), "Dropped " + mapView.getPointDropTime(pointId), :pointSummary, null));
    menu.addItem(new WatchUi.MenuItem("Distance", mapView.getPointDistanceLabel(pointId), :pointDistance, null));
    var bearing = mapView.getPointBearingDegrees(pointId);
    menu.addItem(new WatchUi.MenuItem("Bearing", bearing.format("%03d") + " deg " + mapView.getPointCardinalDirection(pointId), :pointBearing, null));
    menu.addItem(new WatchUi.MenuItem("Coordinates", mapView.getPointLatitudeLabel(pointId) + ", " + mapView.getPointLongitudeLabel(pointId), :pointCoordinates, null));
    menu.addItem(new WatchUi.MenuItem("MGRS", mapView.getPointMGRSLabel(pointId), :pointMGRS, null));
    menu.addItem(new WatchUi.MenuItem(mapView.isBloodhoundTarget(pointId) ? "Stop Bloodhound" : "Bloodhound", null, :pointBloodhound, null));
    menu.addItem(new WatchUi.MenuItem("Change Title", null, :pointTitle, null));
    menu.addItem(new WatchUi.MenuItem(mapView.getPointText(pointId, "remark").equals("") ? "Add Remark" : "Change Remark", null, :pointRemark, null));
    menu.addItem(new WatchUi.MenuItem("Change Marker", null, :pointType, null));
    menu.addItem(new WatchUi.MenuItem("Move to Current Location", null, :pointMove, null));
    menu.addItem(new WatchUi.MenuItem("Delete Marker", null, :pointDelete, null));
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
            var typeMenu = new WatchUi.Menu2({:title => "Change Marker"});
            typeMenu.addItem(new WatchUi.MenuItem(mapView.application.text(:unknownPoint), null, :unknown, null));
            typeMenu.addItem(new WatchUi.MenuItem(mapView.application.text(:hostile), null, :hostile, null));
            typeMenu.addItem(new WatchUi.MenuItem(mapView.application.text(:friendly), null, :friendly, null));
            typeMenu.addItem(new WatchUi.MenuItem(mapView.application.text(:neutral), null, :neutral, null));
            WatchUi.pushView(typeMenu, new PointTypeMenuDelegate(mapView, pointId), WatchUi.SLIDE_LEFT);
        } else if (id == :pointMove) {
            if (!mapView.movePointToCurrentLocation(pointId)) {
                WatchUi.showToast(mapView.application.text(:locationUnavailable), null);
            }
            refreshSummary();
        } else if (id == :pointDelete) {
            mapView.deletePoint(pointId);
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
            view.changePointType(pointId, :unknown, view.application.text(:unknownPoint));
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
