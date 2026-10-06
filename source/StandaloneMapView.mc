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

class StandaloneMapView extends WatchUi.MapView {
    var screenWidth;
    var screenHeight;
    var mapTopLeft;
    var mapBottomRight;
    var markers = {};
    var pointLocations = {};
    var pointDetails = {};
    var pointOrder as Array<String> = [];
    var defaultPointType as Symbol = :unknown;
    var incomingIds = [];
    var incomingLastSeen = {};
    var incomingDetails = {};
    var pendingIncomingPoints as Array<String> = [];
    var dismissedIncomingPoints = {};
    var hiddenMapTeams as Array<String> = [];
    var hiddenMapRoles as Array<String> = [];
    var mapButtonsVisible as Boolean = true;
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
    var drawnPointIds as Array<String> = [];

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
        centerOn(currentPosition);
        entityPruneTimer = new Timer.Timer();
        entityPruneTimer.start(method(:pruneIncomingEntitiesOnTimer), 60000, true);
        hiddenMapTeams = loadStoredStringArray("hiddenMapTeams");
        hiddenMapRoles = loadStoredStringArray("hiddenMapRoles");
        var storedButtons = Application.Storage.getValue("mapButtonsVisible");
        if (storedButtons instanceof Boolean) { mapButtonsVisible = storedButtons as Boolean; }
        loadPoints();
    }

    function loadStoredStringArray(key as String) as Array<String> {
        var value = Application.Storage.getValue(key);
        if (!(value instanceof Array)) { return []; }
        var normalized = [];
        var values = value as Array;
        for (var index = 0; index < values.size(); index++) {
            if (values[index] instanceof String) {
                var groupKey = normalizeMapGroup(values[index] as String);
                var exists = false;
                for (var normalizedIndex = 0; normalizedIndex < normalized.size(); normalizedIndex++) {
                    if ((normalized[normalizedIndex] as String).equals(groupKey)) { exists = true; }
                }
                if (groupKey.length() > 0 && !exists) { normalized.add(groupKey); }
            }
        }
        return normalized;
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
        for (var i = 0; i < pointOrder.size(); i++) {
            var id = pointOrder[i] as String;
            if (!pointLocations.hasKey(id) || !pointDetails.hasKey(id)) { continue; }
            var details = pointDetails.get(id) as Dictionary;
            var degrees = pointLocations.get(id).toDegrees();
            saved.add({
                "id" => id,
                "lat" => degrees[0],
                "lon" => degrees[1],
                "type" => typeToString(details.get("type") as Symbol),
                "title" => safeDetailString(details, "title", ""),
                "remark" => safeDetailString(details, "remark", ""),
                "droppedAt" => safeDetailString(details, "droppedAt", "Unknown"),
                "localTime" => safeDetailString(details, "localTime", "Unknown"),
                "createdAt" => details.get("createdAt") == null ? 0 : details.get("createdAt") as Number
            });
        }
        Application.Storage.setValue("droppedPoints", saved);
        Application.Storage.setValue("nextPointNumber", nextPointNumber);
    }

    function loadPoints() as Void {
        var nextNumber = Application.Storage.getValue("nextPointNumber");
        if (nextNumber instanceof Number) { nextPointNumber = nextNumber; }
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
            var localTime = entry.get("localTime");
            var createdAt = entry.get("createdAt");
            markers.put(id, createPointMarker(location, type, title));
            pointLocations.put(id, location);
            pointDetails.put(id, {"type" => type, "title" => title, "remark" => entry.get("remark") as String, "droppedAt" => droppedAt == null ? "Unknown" : droppedAt.toString(), "localTime" => localTime == null ? "Unknown" : localTime.toString(), "createdAt" => createdAt == null ? 0 : createdAt as Number});
            pointOrder.add(id);
        }
        sortPointOrderNewestFirst();
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
        markersDirty = true;
        if (info.accuracy >= Position.QUALITY_USABLE) { resolvePendingPoints(info.position); }
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
        if (application == null || currentPosition == null || !isBloodhoundActive()) {
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
        if (incomingDetails.hasKey(pointId)) {
            WatchUi.pushView(buildIncomingPointActions(self, pointId),
                new IncomingPointActionsDelegate(self, pointId), WatchUi.SLIDE_LEFT);
            return;
        }
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
                markersDirty = true;
            }
        }
        bloodhoundProximityNotified = false;
        evaluateBloodhoundProximity();
        WatchUi.requestUpdate();
    }

    function updateIncomingCot(uid as String, latitude, longitude, cotType as String, callSign as String?, team as String?, role as String?, metadata as Dictionary) as Void {
        var markerId = "cot-" + uid;
        var isPoint = isIncomingMapPoint(cotType, metadata);
        var revision = incomingPointRevision(metadata);
        if (dismissedIncomingPoints.hasKey(markerId)) {
            var dismissed = dismissedIncomingPoints.get(markerId) as Dictionary;
            if (revision.equals(dismissed.get("revision")) || revision.length() == 0) { return; }
            dismissedIncomingPoints.remove(markerId);
        }
        var previous = incomingDetails.get(markerId);
        var notify = isPoint && (previous == null
            || (revision.length() > 0 && !revision.equals(previous.get("revision"))));
        var location = new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees});
        if (!incomingDetails.hasKey(markerId)) {
            incomingIds.add(markerId);
            if (incomingIds.size() > MAP_RETAINED_LIMIT) {
                removeIncomingPoint(incomingIds[0], false);
            }
        }
        incomingLastSeen.put(markerId, Time.now().value());
        incomingDetails.put(markerId, {
            "uid" => uid, "type" => cotType,
            "callSign" => callSign == null ? "" : trimMapText(callSign),
            "team" => team == null ? "" : trimMapText(team),
            "role" => role == null ? "" : trimMapText(role),
            "isPoint" => isPoint, "senderUID" => incomingPointSender(metadata),
            "revision" => revision
        });
        pointLocations.put(markerId, location);
        if (notify) {
            if (pendingIncomingPoints.indexOf(markerId) == -1) { pendingIncomingPoints.add(markerId); }
            Attention.vibrate([new Attention.VibeProfile(80, 250)]);
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointReceived), null);
        }
        application.refreshIncomingPointCount();
        pruneIncomingEntities();
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function incomingPointTitle(id as String) as String {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary)) { return id; }
        var title = details.get("callSign") as String;
        return title.length() > 0 ? title : details.get("uid") as String;
    }

    function incomingPointDetailLabel(id as String) as String {
        var details = incomingDetails.get(id);
        var affiliation = :unknownPoint;
        if (details instanceof Dictionary) {
            var cotType = details.get("type");
            if (cotType instanceof String && (cotType as String).length() >= 3) {
                var code = (cotType as String).substring(2, 3);
                if (code.equals("f") || code.equals("a")) { affiliation = :friendlyPoint; }
                else if (code.equals("h") || code.equals("s") || code.equals("j") || code.equals("k")) {
                    affiliation = :hostilePoint;
                } else if (code.equals("n")) { affiliation = :neutralPoint; }
            }
        }
        var label = application.text(affiliation);
        var location = pointLocations.get(id);
        if (currentPosition == null || location == null) { return label; }
        return label + " · " + distanceMeters(currentPosition, location).format("%.0f") + " m";
    }

    function markIncomingPointsSeen() as Void {
        if (pendingIncomingPoints.size() == 0) { return; }
        pendingIncomingPoints = [];
        application.refreshIncomingPointCount();
    }

    function acknowledgeIncomingPoint(id as String) as Boolean {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary) || details.get("isPoint") != true) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient == null || !takClient.queuePointReply(details.get("senderUID") as String,
                details.get("uid") as String, "Roger, bloodhounding to " + incomingPointTitle(id))) { return false; }
        bloodhoundPointId = null;
        toggleBloodhound(id);
        pendingIncomingPoints.remove(id);
        application.refreshIncomingPointCount();
        return true;
    }

    function markIncomingPointInPosition(id as String) as Boolean {
        var details = incomingDetails.get(id);
        if (!(details instanceof Dictionary) || bloodhoundPointId == null || !bloodhoundPointId.equals(id)) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient == null || !takClient.queuePointReply(details.get("senderUID") as String,
                details.get("uid") as String, "In Position at " + incomingPointTitle(id))) { return false; }
        removeIncomingPoint(id, true);
        return true;
    }

    function removeAllIncomingPoints() as Void {
        for (var i = incomingIds.size() - 1; i >= 0; i--) {
            var id = incomingIds[i] as String;
            var details = incomingDetails.get(id);
            if (details instanceof Dictionary && details.get("isPoint") == true) {
                removeIncomingPoint(id, true);
            }
        }
    }

    function removeIncomingPoint(id as String, dismiss as Boolean) as Void {
        var details = incomingDetails.get(id);
        if (dismiss && details instanceof Dictionary) {
            if (dismissedIncomingPoints.size() >= MAP_RETAINED_LIMIT) {
                dismissedIncomingPoints.remove(dismissedIncomingPoints.keys()[0]);
            }
            dismissedIncomingPoints.put(id, {"revision" => details.get("revision"), "removedAt" => Time.now().value()});
        }
        markers.remove(id);
        pointLocations.remove(id);
        incomingLastSeen.remove(id);
        incomingDetails.remove(id);
        incomingIds.remove(id);
        pendingIncomingPoints.remove(id);
        application.refreshIncomingPointCount();
        if (bloodhoundPointId != null && bloodhoundPointId.equals(id)) {
            bloodhoundPointId = null;
            bloodhoundProximityNotified = false;
        }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function trimMapText(value as String) as String {
        while (value.length() > 0 && isMapWhitespace(value.substring(0, 1))) { value = value.substring(1, value.length()); }
        while (value.length() > 0 && isMapWhitespace(value.substring(value.length() - 1, value.length()))) { value = value.substring(0, value.length() - 1); }
        return value;
    }

    function isMapWhitespace(value as String) as Boolean {
        return value.equals(" ") || value.equals("\t") || value.equals("\r") || value.equals("\n");
    }

    function normalizeMapGroup(value as String) as String {
        return trimMapText(value).toLower();
    }

    function isUserCotType(cotType as String) as Boolean {
        return cotType.find("a-") == 0 && cotType.find("-G-U-C") != null;
    }

    function incomingUserGroups(isTeam as Boolean) as Array<Dictionary> {
        var names = {};
        var counts = {};
        for (var index = 0; index < incomingIds.size(); index++) {
            var markerId = incomingIds[index] as String;
            var details = incomingDetails.get(markerId);
            if (!(details instanceof Dictionary)) { continue; }
            if (details.get("isPoint") == true) { continue; }
            var type = (details as Dictionary).get("type");
            if (!(type instanceof String) || !isUserCotType(type as String) || isSelfIncomingUser(details as Dictionary)) { continue; }
            var value = (details as Dictionary).get(isTeam ? "team" : "role");
            if (!(value instanceof String)) { continue; }
            var displayName = trimMapText(value as String);
            if (displayName.length() == 0) { continue; }
            var key = normalizeMapGroup(displayName);
            names.put(key, names.hasKey(key) ? names.get(key) : displayName);
            counts.put(key, counts.hasKey(key) ? (counts.get(key) as Number) + 1 : 1);
        }
        var groups = [];
        var keys = names.keys();
        for (var keyIndex = 0; keyIndex < keys.size(); keyIndex++) {
            var key = keys[keyIndex] as String;
            var name = names.get(key);
            groups.add({"key" => key, "name" => name == null ? key : name.toString(), "count" => counts.get(key) as Number});
        }
        return groups;
    }

    function isIncomingUserVisible(markerId as String) as Boolean {
        var details = incomingDetails.get(markerId);
        if (!(details instanceof Dictionary)) { return true; }
        if (details.get("isPoint") == true) { return true; }
        var eventType = (details as Dictionary).get("type");
        if (!(eventType instanceof String) || !isUserCotType(eventType as String) || isSelfIncomingUser(details as Dictionary)) { return true; }
        var teamValue = (details as Dictionary).get("team");
        var roleValue = (details as Dictionary).get("role");
        var team = teamValue instanceof String ? teamValue as String : "";
        var role = roleValue instanceof String ? roleValue as String : "";
        return !isMapGroupHidden(hiddenMapTeams, team) && !isMapGroupHidden(hiddenMapRoles, role);
    }

    function sortPointOrderNewestFirst() as Void {
        for (var index = 1; index < pointOrder.size(); index++) {
            var pointId = pointOrder[index] as String;
            var pointTime = (pointDetails.get(pointId) as Dictionary).get("createdAt") as Number;
            var cursor = index;
            while (cursor > 0) {
                var previousId = pointOrder[cursor - 1] as String;
                var previousTime = (pointDetails.get(previousId) as Dictionary).get("createdAt") as Number;
                if (previousTime >= pointTime) { break; }
                pointOrder[cursor] = previousId;
                cursor -= 1;
            }
            pointOrder[cursor] = pointId;
        }
    }

    function isSelfIncomingUser(details as Dictionary) as Boolean {
        if (application == null) { return false; }
        var callSignValue = details.get("callSign");
        var ownCallSign = application.getCallsign();
        if (callSignValue instanceof String && ownCallSign.length() > 0 && normalizeMapGroup(callSignValue as String).equals(normalizeMapGroup(ownCallSign))) { return true; }
        var deviceId = System.getDeviceSettings().uniqueIdentifier;
        var uid = details.get("uid");
        return deviceId != null && uid instanceof String && (uid as String).equals(deviceId);
    }

    function isMapGroupHidden(hiddenGroups as Array<String>, value as String) as Boolean {
        var key = normalizeMapGroup(value);
        if (key.length() == 0) { return false; }
        for (var index = 0; index < hiddenGroups.size(); index++) {
            if ((hiddenGroups[index] as String).equals(key)) { return true; }
        }
        return false;
    }

    function isMapGroupHiddenForKind(isTeam as Boolean, value as String) as Boolean {
        return isMapGroupHidden(isTeam ? hiddenMapTeams : hiddenMapRoles, value);
    }

    function toggleMapGroup(isTeam as Boolean, value as String) as Void {
        var key = normalizeMapGroup(value);
        if (key.length() == 0) { return; }
        var groups = isTeam ? hiddenMapTeams : hiddenMapRoles;
        var found = false;
        for (var index = 0; index < groups.size(); index++) {
            if ((groups[index] as String).equals(key)) {
                found = true;
            }
        }
        if (found) { groups.remove(key); }
        else { groups.add(key); }
        if (isTeam) {
            hiddenMapTeams = groups;
            Application.Storage.setValue("hiddenMapTeams", hiddenMapTeams);
        } else {
            hiddenMapRoles = groups;
            Application.Storage.setValue("hiddenMapRoles", hiddenMapRoles);
        }
        markersDirty = true;
        WatchUi.requestUpdate();
    }

    function areMapButtonsVisible() as Boolean {
        return mapButtonsVisible;
    }

    function setMapButtonsVisible(visible as Boolean) as Void {
        mapButtonsVisible = visible;
        Application.Storage.setValue("mapButtonsVisible", visible);
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
        if (currentPosition == null) { markersDirty = true; }
    }

    function onUpdate(dc) {
        if (mapAreaDirty) {
            setMapVisibleArea(mapTopLeft, mapBottomRight);
            mapAreaDirty = false;
            if (currentPosition == null) { markersDirty = true; }
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
        drawIncomingUserOverlays(dc);
        if (mapButtonsVisible) {
            var top = (screenHeight - (controlSize * 3 + controlGap * 2)) / 2;
            drawControl(dc, controlMargin, top, "+");
            drawCenterControl(dc, controlMargin, top + controlSize + controlGap);
            drawControl(dc, controlMargin, top + (controlSize + controlGap) * 2, "-");
        }
        drawLayersControl(dc);
        if (mapButtonsVisible) {
            drawChannelsControl(dc);
        }
        drawBackControl(dc, screenWidth - controlSize - controlMargin, (screenHeight - controlSize) / 2);
        drawBloodhound(dc);
    }

    function drawLayersControl(dc) as Void {
        var x = (screenWidth - controlSize) / 2;
        var y = controlMargin;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawLine(x + 9, y + 12, x + 30, y + 12);
        dc.drawLine(x + 9, y + 20, x + 30, y + 20);
        dc.drawLine(x + 9, y + 28, x + 30, y + 28);
    }

    function drawChannelsControl(dc) as Void {
        var x = screenWidth / 2 + controlSize / 2 + controlGap;
        var y = controlMargin + 24;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, controlSize, controlSize);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, controlSize, controlSize);
        dc.drawLine(x + 13, y + 13, x + 27, y + 13);
        dc.drawLine(x + 13, y + 13, x + 20, y + 27);
        dc.drawLine(x + 27, y + 13, x + 20, y + 27);
        dc.drawCircle(x + 12, y + 12, 3);
        dc.drawCircle(x + 28, y + 12, 3);
        dc.drawCircle(x + 20, y + 28, 3);
    }

    function drawIncomingUserOverlays(dc) as Void {
        for (var index = 0; index < drawnPointIds.size(); index++) {
            var markerId = drawnPointIds[index];
            var details = incomingDetails.get(markerId);
            if (!(details instanceof Dictionary) || details.get("isPoint") == true || !isUserCotType((details as Dictionary).get("type").toString()) || !isIncomingUserVisible(markerId)) { continue; }
            var location = pointLocations.get(markerId);
            if (location == null) { continue; }
            var screen = pointScreenPosition(location);
            var markerX = screen[0].toNumber();
            var markerY = screen[1].toNumber();
            if (markerX < 0 || markerX >= screenWidth || markerY < 0 || markerY >= screenHeight) { continue; }
            var team = (details as Dictionary).get("team").toString();
            var color = mapColorForTeam(team);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(markerX, markerY, 7);
            drawTeamDot(dc, markerX, markerY, color);
        }
    }

    function mapColorForTeam(team as String) as Number {
        var color = trimMapText(team).toLower();
        if (color.equals("white")) { return Graphics.createColor(255, 255, 255, 255); }
        else if (color.equals("yellow")) { return Graphics.createColor(255, 255, 255, 0); }
        else if (color.equals("orange")) { return Graphics.createColor(255, 255, 165, 0); }
        else if (color.equals("magenta")) { return Graphics.createColor(255, 255, 0, 255); }
        else if (color.equals("red")) { return Graphics.createColor(255, 255, 0, 0); }
        else if (color.equals("maroon")) { return Graphics.createColor(255, 128, 0, 0); }
        else if (color.equals("purple")) { return Graphics.createColor(255, 128, 0, 128); }
        else if (color.equals("dark blue")) { return Graphics.createColor(255, 0, 0, 139); }
        else if (color.equals("cyan")) { return Graphics.createColor(255, 0, 255, 255); }
        else if (color.equals("teal")) { return Graphics.createColor(255, 0, 128, 128); }
        else if (color.equals("green")) { return Graphics.createColor(255, 0, 128, 0); }
        else if (color.equals("dark green")) { return Graphics.createColor(255, 0, 100, 0); }
        else if (color.equals("brown")) { return Graphics.createColor(255, 165, 42, 42); }
        return Graphics.createColor(255, 0, 0, 255);
    }

    function drawTeamOverlay(dc) as Void {
        if (application == null || currentPosition == null || mapTopLeft == null || mapBottomRight == null) {
            return;
        }
        var screen = pointScreenPosition(currentPosition);
        var markerX = screen[0].toNumber();
        var markerY = screen[1].toNumber();
        if (markerX < 0 || markerX >= screenWidth || markerY < 0 || markerY >= screenHeight) {
            return;
        }

        var teamColor = application.getMyTeamColorValue();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(markerX, markerY, 8);
        drawTeamDot(dc, markerX, markerY, teamColor);

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

    function drawTeamDot(dc, x, y, color) as Void {
        dc.setColor(color, color);
        dc.fillCircle(x, y, 5);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 5);
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
        if (bloodhoundPointId != null && incomingDetails.hasKey(bloodhoundPointId)) {
            showPointTypeMenu(bloodhoundPointId);
            return;
        }
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
        if (bloodhoundPointId != null && incomingDetails.hasKey(bloodhoundPointId)) {
            return incomingPointTitle(bloodhoundPointId);
        }
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
        return dropAtCurrentLocationAs(defaultPointType);
    }

    function getDefaultPointType() as Symbol {
        return defaultPointType;
    }

    function dropAtCurrentLocationAs(type as Symbol) as Boolean {
        var info = Position.getInfo();
        var droppedAt = utcTimeLabel(Time.now());
        var location = info != null && info.accuracy >= Position.QUALITY_USABLE
            && application.isLocationServicesEnabled() ? info.position : null;
        return addPoint(location, type, newPointTitle(droppedAt), droppedAt);
    }

    function hasPoints() as Boolean {
        if (pointOrder.size() > 0) { return true; }
        if (takClient != null) {
            for (var i = 0; i < takClient.pointReplies.replies.size(); i++) {
                var entry = takClient.pointReplies.replies[i];
                if (entry.get("msgType").equals("marker")) { return true; }
            }
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
        var droppedAt = utcTimeLabel(Time.now());
        addPoint(new Position.Location({:latitude => latitude, :longitude => longitude, :format => :degrees}), defaultPointType, newPointTitle(droppedAt), droppedAt);
        WatchUi.requestUpdate();
    }

    function isControlAt(x, y) {
        return isLayersControlAt(x, y) || (mapButtonsVisible && (isChannelsControlAt(x, y) || isZoomInControlAt(x, y) || isZoomOutControlAt(x, y) || isCenterControlAt(x, y))) || isBackControlAt(x, y);
    }

    function isLayersControlAt(x, y) as Boolean {
        var left = (screenWidth - controlSize) / 2;
        return x >= left && x < left + controlSize && y >= controlMargin && y < controlMargin + controlSize;
    }

    function isChannelsControlAt(x, y) as Boolean {
        var left = screenWidth / 2 + controlSize / 2 + controlGap;
        var top = controlMargin + 24;
        return x >= left && x < left + controlSize && y >= top && y < top + controlSize;
    }

    function showLayersMenu() as Void {
        var menu = buildMapLayersMenu(self);
        WatchUi.pushView(menu, new MapLayersMenuDelegate(self, menu), WatchUi.SLIDE_DOWN);
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

    function addPoint(location, type, label, droppedAt as String) as Boolean {
        var id = "point-" + nextPointNumber.toString();
        if (takClient == null || !takClient.sendMarker(id, location, type, label, "")) { return false; }
        nextPointNumber += 1;
        Application.Storage.setValue("nextPointNumber", nextPointNumber);
        defaultPointType = type;
        Application.Storage.setValue("defaultPointType", typeToString(type));
        if (location != null) { saveResolvedPoint(id, location, type, label, droppedAt); }
        return true;
    }

    function saveResolvedPoint(id as String, location, type, label, droppedAt as String) as Void {
        markers.put(id, createPointMarker(location, type, label));
        pointLocations.put(id, location);
        var localInfo = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var localTime = localInfo.hour.format("%02d") + ":" + localInfo.min.format("%02d");
        pointDetails.put(id, {"type" => type, "title" => label, "remark" => "", "droppedAt" => droppedAt, "localTime" => localTime, "createdAt" => Time.now().value()});
        var newestFirst = [id];
        for (var orderIndex = 0; orderIndex < pointOrder.size(); orderIndex++) {
            newestFirst.add(pointOrder[orderIndex]);
        }
        pointOrder = newestFirst;
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
    }

    function resolvePendingPoints(location as Position.Location) as Void {
        if (takClient == null) { return; }
        takClient.expirePointReplies();
        for (var i = 0; i < takClient.pointReplies.replies.size(); i++) {
            var entry = takClient.pointReplies.replies[i];
            var payload = entry.get("payload") as Dictionary;
            if (!entry.get("msgType").equals("marker") || payload.get("lat") != null) { continue; }
            var degrees = location.toDegrees();
            payload.put("lat", degrees[0]);
            payload.put("lon", degrees[1]);
            var id = payload.get("localId") as String;
            var cotType = payload.get("type").toString();
            var type = cotType.find("a-h-") == 0 ? :hostile : cotType.find("a-f-") == 0 ? :friendly : cotType.find("a-n-") == 0 ? :neutral : :unknown;
            saveResolvedPoint(id, location, type, payload.get("title").toString(), utcTimeLabel(Time.now()));
        }
        takClient.savePointReplies();
        takClient.flushPointReplies();
    }

    function newPointTitle(droppedAt as String) as String {
        var callsign = application.getCallsign();
        return callsign.length() == 0 ? droppedAt : callsign + "_" + droppedAt;
    }

    function utcTimeLabel(moment as Time.Moment) as String {
        var timeInfo = Time.Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return timeInfo.hour.format("%02d") + timeInfo.min.format("%02d") + timeInfo.sec.format("%02d") + "Z";
    }

    function iconForType(type) {
        return WatchUi.loadResource(type == :friendly ? Rez.Drawables.FriendlyIcon
            : type == :hostile ? Rez.Drawables.HostileIcon
            : type == :neutral ? Rez.Drawables.NeutralIcon : Rez.Drawables.UnknownIcon);
    }

    function createPointMarker(location, type, label) {
        var marker = new WatchUi.MapMarker(location);
        var icon = iconForType(type);
        marker.setIcon(icon, icon.getWidth() / 2, icon.getHeight() / 2);
        marker.setLabel(label);
        return marker;
    }

    function markerArray() as Array {
        var origin = currentPosition;
        if (origin == null) {
            var topLeft = mapTopLeft.toDegrees();
            var bottomRight = mapBottomRight.toDegrees();
            origin = new Position.Location({
                :latitude => (topLeft[0] + bottomRight[0]) / 2,
                :longitude => (topLeft[1] + bottomRight[1]) / 2,
                :format => :degrees
            });
        }
        var nearest = new NearestMapItems();
        var ids = pointLocations.keys();
        for (var i = 0; i < ids.size(); i++) {
            var markerId = ids[i].toString();
            if (!isIncomingUserVisible(markerId)) { continue; }
            nearest.add(markerId, distanceMeters(origin, pointLocations.get(markerId)));
        }
        drawnPointIds = nearest.pointIds;
        var result = [];
        for (var i = 0; i < drawnPointIds.size(); i++) {
            var markerId = drawnPointIds[i];
            if (incomingDetails.hasKey(markerId)) {
                var details = incomingDetails.get(markerId) as Dictionary;
                var cotType = details.get("type") as String;
                var type = cotType.find("a-h-") != null ? :hostile : cotType.find("a-f-") != null ? :friendly : cotType.find("a-n-") != null ? :neutral : :unknown;
                result.add(createPointMarker(pointLocations.get(markerId), type, incomingPointTitle(markerId)));
            } else {
                result.add(markers.get(markerId));
            }
        }
        return result;
    }

    function pointScreenPosition(location) {
        var topLeft = mapTopLeft.toDegrees();
        var bottomRight = mapBottomRight.toDegrees();
        var degrees = location.toDegrees();
        return [(degrees[1] - topLeft[1]) / (bottomRight[1] - topLeft[1]) * screenWidth,
            (topLeft[0] - degrees[0]) / (topLeft[0] - bottomRight[0]) * screenHeight];
    }

    function pointAtScreen(x, y) {
        var keys = drawnPointIds;
        for (var i = 0; i < keys.size(); i++) {
            if (!pointLocations.hasKey(keys[i])) { continue; }
            if (!isIncomingUserVisible(keys[i])) { continue; }
            if (isLocationAtScreen(pointLocations.get(keys[i]), x, y)) {
                return keys[i];
            }
        }
        return null;
    }

    function isSelfAtScreen(x, y) as Boolean {
        return currentPosition != null && isLocationAtScreen(currentPosition, x, y);
    }

    function isLocationAtScreen(location, x, y) as Boolean {
        var screen = pointScreenPosition(location);
        var dx = screen[0] - x;
        var dy = screen[1] - y;
        return dx * dx + dy * dy <= 14 * 14;
    }

    function changePointType(id, type, label) {
        if (pointLocations.hasKey(id) == false || pointDetails.hasKey(id) == false) {
            return;
        }
        var details = copiedPointDetails(id);
        var currentType = details.get("type") as Symbol;
        var currentTitle = safeDetailString(details, "title", "");
        details.put("type", type);
        if (currentTitle.equals("") || currentTitle.equals(defaultPointTitle(currentType))) {
            details.put("title", defaultPointTitle(type));
        }
        if (updatePoint(id, details)) {
            defaultPointType = type;
            Application.Storage.setValue("defaultPointType", typeToString(type));
        }
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
        var details = copiedPointDetails(id);
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

    function getPointLocalTime(id as String) as String {
        if (!pointDetails.hasKey(id)) { return "Unknown"; }
        return safeDetailString(pointDetails.get(id) as Dictionary, "localTime", "Unknown");
    }

    function getOrderedPointIds() as Array<String> {
        return pointOrder;
    }

    function getPointIcon(id as String) {
        if (!pointDetails.hasKey(id)) { return iconForType(:unknown); }
        return iconForType((pointDetails.get(id) as Dictionary).get("type") as Symbol);
    }

    function deleteLastPoint() as Boolean {
        if (pointOrder.size() == 0) {
            if (takClient != null) {
                for (var i = takClient.pointReplies.replies.size() - 1; i >= 0; i--) {
                    var entry = takClient.pointReplies.replies[i];
                    if (entry.get("msgType").equals("marker")) {
                        return takClient.deleteMarker((entry.get("payload") as Dictionary).get("localId").toString());
                    }
                }
            }
            return false;
        }
        return deletePoint(pointOrder[0] as String);
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
            WatchUi.showToast(application.text(:locationUnavailable), null);
            return false;
        }
        currentPosition = info.position;
        markersDirty = true;
        var previous = pointLocations.get(id);
        pointLocations.put(id, info.position);
        if (!updatePoint(id, pointDetails.get(id) as Dictionary)) {
            pointLocations.put(id, previous);
            return false;
        }
        return true;
    }

    function copiedPointDetails(id) as Dictionary {
        var original = pointDetails.get(id) as Dictionary;
        var copy = {};
        var keys = original.keys();
        for (var i = 0; i < keys.size(); i++) { copy.put(keys[i], original.get(keys[i])); }
        return copy;
    }

    function safeDetailString(details as Dictionary, key as String, fallback as String) as String {
        var value = details.get(key);
        if (value == null) {
            return fallback;
        }
        return value.toString();
    }

    function updatePoint(id, details as Dictionary) as Boolean {
        var location = pointLocations.get(id);
        var type = details.get("type") as Symbol;
        var title = safeDetailString(details, "title", defaultPointTitle(type));
        var remark = safeDetailString(details, "remark", "");
        if (takClient != null && !takClient.sendMarker(id, location, type, title, remark)) { return false; }
        pointDetails.put(id, details);
        markers.put(id, createPointMarker(location, type, title));
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
        return true;
    }

    function deletePoint(id) as Boolean {
        if (id == null || pointLocations == null || pointLocations.hasKey(id) == false) {
            WatchUi.showToast(WatchUi.loadResource(Rez.Strings.IncomingPointUnavailable), null);
            return false;
        }
        if (takClient != null && !takClient.deleteMarker(id)) { return false; }
        if (bloodhoundPointId != null && bloodhoundPointId.equals(id)) {
            bloodhoundPointId = null;
        }
        markers.remove(id);
        pointLocations.remove(id);
        pointDetails.remove(id);
        pointOrder.remove(id);
        markersDirty = true;
        savePoints();
        WatchUi.requestUpdate();
        return true;
    }

    function clearDroppedPoints() as Boolean {
        var complete = true;
        var pointIds = pointOrder.slice(0, pointOrder.size());
        for (var i = 0; i < pointIds.size(); i++) {
            if (!deletePoint(pointIds[i])) { complete = false; }
        }
        if (takClient != null) {
            var entries = takClient.pointReplies.replies.slice(0, takClient.pointReplies.replies.size());
            for (var j = 0; j < entries.size(); j++) {
                var entry = entries[j];
                var payload = entry.get("payload") as Dictionary;
                if (entry.get("msgType").equals("marker") && payload.get("lat") == null) {
                    if (!takClient.deleteMarker(payload.get("localId").toString())) { complete = false; }
                }
            }
        }
        if (!complete) { return false; }

        var waypoints = PersistedContent.getAppWaypoints();
        var waypoint = waypoints.next();
        while (waypoint != null) {
            waypoint.remove();
            waypoint = waypoints.next();
        }
        WatchUi.requestUpdate();
        return true;
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
            removeIncomingPoint(staleIds[j], false);
        }
        var dismissedIds = dismissedIncomingPoints.keys();
        for (var k = 0; k < dismissedIds.size(); k++) {
            if (now - dismissedIncomingPoints.get(dismissedIds[k]).get("removedAt") > 300) {
                dismissedIncomingPoints.remove(dismissedIds[k]);
            }
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

function buildMapLayersMenu(mapView as StandaloneMapView) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Layers Menu"});
    addMenuEntry(menu, "Map Buttons", mapView.areMapButtonsVisible() ? "On" : "Off", :mapButtonsToggle);
    var teams = mapView.incomingUserGroups(true);
    menu.addItem(new WatchUi.MenuItem("Team Colors (" + teams.size().toString() + ")", null, :teamColorsHeading, null));
    for (var teamIndex = 0; teamIndex < teams.size(); teamIndex++) {
        var team = teams[teamIndex] as Dictionary;
        var teamName = team.get("name").toString();
        var teamCount = team.get("count") as Number;
        menu.addItem(new WatchUi.MenuItem(teamName + " (" + teamCount.toString() + ")", mapView.isMapGroupHiddenForKind(true, teamName) ? "Hidden" : "Shown", teamIndex, null));
    }
    var roles = mapView.incomingUserGroups(false);
    menu.addItem(new WatchUi.MenuItem("Default Roles (" + roles.size().toString() + ")", null, :defaultRolesHeading, null));
    for (var roleIndex = 0; roleIndex < roles.size(); roleIndex++) {
        var role = roles[roleIndex] as Dictionary;
        var roleName = role.get("name").toString();
        var roleCount = role.get("count") as Number;
        menu.addItem(new WatchUi.MenuItem(roleName + " (" + roleCount.toString() + ")", mapView.isMapGroupHiddenForKind(false, roleName) ? "Hidden" : "Shown", 1000 + roleIndex, null));
    }
    menu.addItem(new WatchUi.MenuItem("Back", null, :layersBack, null));
    return menu;
}

class MapLayersMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mapView as StandaloneMapView;
    var menu as WatchUi.Menu2;

    function initialize(map as StandaloneMapView, layersMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mapView = map;
        menu = layersMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :layersBack) {
            WatchUi.popView(WatchUi.SLIDE_UP);
        } else if (id == :mapButtonsToggle) {
            mapView.setMapButtonsVisible(!mapView.areMapButtonsVisible());
            item.setSubLabel(mapView.areMapButtonsVisible() ? "On" : "Off");
        } else if (id instanceof Number) {
            var index = id as Number;
            var teamGroup = index < 1000;
            var groups = mapView.incomingUserGroups(teamGroup);
            if (teamGroup) {
                if (index >= 0 && index < groups.size()) {
                    var group = groups[index] as Dictionary;
                    mapView.toggleMapGroup(true, group.get("name").toString());
                    item.setSubLabel(mapView.isMapGroupHiddenForKind(true, group.get("name").toString()) ? "Hidden" : "Shown");
                }
            } else {
                var roleIndex = index - 1000;
                if (roleIndex >= 0 && roleIndex < groups.size()) {
                    var role = groups[roleIndex] as Dictionary;
                    mapView.toggleMapGroup(false, role.get("name").toString());
                    item.setSubLabel(mapView.isMapGroupHiddenForKind(false, role.get("name").toString()) ? "Hidden" : "Shown");
                }
            }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_UP);
    }
}

class StandaloneMapDelegate extends WatchUi.InputDelegate {
    var view;
    var app as StandaloneApp;
    var openMainMenuOnBack = false;
    var lastDragX;
    var lastDragY;
    var isDragging = false;
    var suppressNextTap as Boolean = false;

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
        if (suppressNextTap) {
            suppressNextTap = false;
            return true;
        }
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
            if (view.isChannelsControlAt(coordinates[0], coordinates[1])) {
                openTakChannels(app);
            } else if (view.isLayersControlAt(coordinates[0], coordinates[1])) {
                view.showLayersMenu();
            } else if (view.isZoomInControlAt(coordinates[0], coordinates[1])) {
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
        suppressNextTap = true;
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
            typeMenu.addItem(new WatchUi.MenuItem("Unknown", null, :unknown, null));
            typeMenu.addItem(new WatchUi.MenuItem("Hostile", null, :hostile, null));
            typeMenu.addItem(new WatchUi.MenuItem("Friendly", null, :friendly, null));
            typeMenu.addItem(new WatchUi.MenuItem("Neutral", null, :neutral, null));
            WatchUi.pushView(typeMenu, new PointTypeMenuDelegate(mapView, pointId), WatchUi.SLIDE_LEFT);
        } else if (id == :pointMove) {
            if (!mapView.movePointToCurrentLocation(pointId)) { return; }
            refreshSummary();
        } else if (id == :pointDelete) {
            if (!mapView.deletePoint(pointId)) { return; }
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
