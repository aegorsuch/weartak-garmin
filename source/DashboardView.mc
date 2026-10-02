import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class DashboardView extends WatchUi.View {
    var app as StandaloneApp;
    var screenWidth as Number = 0;
    var screenHeight as Number = 0;
    var refreshTimer as Timer.Timer? = null;

    function initialize(application as StandaloneApp) {
        View.initialize();
        app = application;
        var settings = System.getDeviceSettings();
        screenWidth = settings.screenWidth;
        screenHeight = settings.screenHeight;
    }

    function onShow() as Void {
        refreshTimer = new Timer.Timer();
        refreshTimer.start(method(:refreshDashboard), 30000, true);
    }

    function onHide() as Void {
        if (refreshTimer != null) { refreshTimer.stop(); refreshTimer = null; }
    }

    function refreshDashboard() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        screenWidth = dc.getWidth();
        screenHeight = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, screenWidth, screenHeight);
        drawStatusHeader(dc);
        drawMetric(dc);
        drawMainActions(dc);
        drawShortcuts(dc);
        drawCompassPanel(dc);
    }

    function drawStatusHeader(dc as Graphics.Dc) as Void {
        var relay = app.getTakClient();
        var phoneConnected = System.getDeviceSettings().phoneConnected;
        var sitx = app.getSitxClient();
        var sitxEnabled = sitx.isTakEnabled();
        var transportLabel = relay.isConnected() && phoneConnected
            ? (sitxEnabled ? "BLE OUT / SITX NO LINK" : "BLE WRITE ONLY")
            : sitxEnabled ? "SITX NO DATA LINK"
            : relay.status == :connecting ? "BLE CONNECTING" : "NO TAK LINK";
        var networkLabel = networkLabel();
        var transportY = 20;
        var networkY = 34;
        var leftInset = safeHorizontalInset(transportY) + 4;
        var rightInset = safeHorizontalInset(transportY) + 4;
        var relayReady = relay.isConnected() && phoneConnected;
        dc.setColor(relayReady ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        drawTransportGlyph(dc, leftInset, transportY + 5, relayReady);
        dc.drawText(leftInset + 10, transportY, Graphics.FONT_XTINY, transportLabel, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        drawNetworkGlyph(dc, leftInset, networkY + 5);
        dc.drawText(leftInset + 10, networkY, Graphics.FONT_XTINY, networkLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var timeInfo = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var clockText = timeInfo.hour.format("%02d") + ":" + timeInfo.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenWidth - rightInset, transportY, Graphics.FONT_XTINY, clockText, Graphics.TEXT_JUSTIFY_RIGHT);
        drawLocationArrow(dc, screenWidth - rightInset - 30, networkY + 5);
        var battery = System.getSystemStats().battery.toNumber();
        dc.drawText(screenWidth - rightInset, networkY, Graphics.FONT_XTINY, battery.format("%.0f") + "%", Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function safeHorizontalInset(y as Number) as Number {
        var radius = (screenWidth < screenHeight ? screenWidth : screenHeight) / 2;
        var verticalOffset = y - screenHeight / 2;
        var remaining = radius * radius - verticalOffset * verticalOffset;
        if (remaining <= 0) { return screenWidth / 2; }
        var halfWidth = Math.sqrt(remaining).toNumber();
        var inset = ((screenWidth - halfWidth * 2) / 2).toNumber();
        return inset < 4 ? 4 : inset;
    }

    function drawTransportGlyph(dc as Graphics.Dc, centerX as Number, centerY as Number, ready as Boolean) as Void {
        if (ready) { dc.drawCircle(centerX, centerY, 6); }
        else {
            dc.drawLine(centerX - 5, centerY - 5, centerX + 5, centerY + 5);
            dc.drawLine(centerX - 5, centerY + 5, centerX + 5, centerY - 5);
        }
    }

    function drawNetworkGlyph(dc as Graphics.Dc, centerX as Number, centerY as Number) as Void {
        var connections = System.getDeviceSettings().connectionInfo;
        var wifi = connections == null ? null : connections.get(:wifi);
        var lte = connections == null ? null : connections.get(:lte);
        var bluetooth = connections == null ? null : connections.get(:bluetooth);
        if (wifi != null && wifi.state == System.CONNECTION_STATE_CONNECTED) {
            dc.drawLine(centerX - 7, centerY, centerX, centerY - 6);
            dc.drawLine(centerX, centerY - 6, centerX + 7, centerY);
            dc.drawLine(centerX - 4, centerY + 2, centerX, centerY - 1);
            dc.drawLine(centerX, centerY - 1, centerX + 4, centerY + 2);
            dc.drawCircle(centerX, centerY + 4, 1);
        } else if (lte != null && lte.state == System.CONNECTION_STATE_CONNECTED) {
            dc.drawLine(centerX - 5, centerY + 5, centerX - 5, centerY + 2);
            dc.drawLine(centerX - 1, centerY + 5, centerX - 1, centerY - 2);
            dc.drawLine(centerX + 3, centerY + 5, centerX + 3, centerY - 6);
        } else if (bluetooth != null && bluetooth.state == System.CONNECTION_STATE_CONNECTED) {
            dc.drawLine(centerX, centerY - 7, centerX, centerY + 7);
            dc.drawLine(centerX, centerY - 7, centerX + 5, centerY - 2);
            dc.drawLine(centerX + 5, centerY - 2, centerX - 4, centerY + 4);
            dc.drawLine(centerX - 4, centerY - 4, centerX + 5, centerY + 2);
            dc.drawLine(centerX + 5, centerY + 2, centerX, centerY + 7);
        } else {
            dc.drawLine(centerX - 5, centerY - 5, centerX + 5, centerY + 5);
            dc.drawLine(centerX - 5, centerY + 5, centerX + 5, centerY - 5);
        }
    }

    function networkLabel() as String {
        var settings = System.getDeviceSettings();
        var connections = settings.connectionInfo;
        if (connections != null) {
            var wifi = connections.get(:wifi);
            if (wifi != null && wifi.state == System.CONNECTION_STATE_CONNECTED) { return "WIFI"; }
            var lte = connections.get(:lte);
            if (lte != null && lte.state == System.CONNECTION_STATE_CONNECTED) { return "CELLULAR"; }
            var bluetooth = connections.get(:bluetooth);
            if (bluetooth != null && bluetooth.state == System.CONNECTION_STATE_CONNECTED) { return "PHONE"; }
        }
        return settings.connectionAvailable ? "NETWORK AVAILABLE" : "OFFLINE";
    }

    function drawLocationArrow(dc as Graphics.Dc, centerX as Number, centerY as Number) as Void {
        var positionInfo = Position.getInfo();
        var hasPosition = positionInfo != null && positionInfo.position != null;
        var color = app.isLocationServicesEnabled() && hasPosition ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX, centerY - 6, centerX - 4, centerY + 5);
        dc.drawLine(centerX, centerY - 6, centerX + 4, centerY + 5);
        dc.drawLine(centerX - 4, centerY + 5, centerX, centerY + 2);
        dc.drawLine(centerX + 4, centerY + 5, centerX, centerY + 2);
    }

    function drawMetric(dc as Graphics.Dc) as Void {
        var centerX = screenWidth / 2;
        var top = (screenHeight * 0.205).toNumber();
        var metric = app.getDashboardMetric();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, top, Graphics.FONT_XTINY, metric.toUpper(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (metric.equals("Heart Rate")) {
            drawHeartbeat(dc, centerX - 35, top + 24);
            var heartRate = app.getHeartRate();
            if (heartRate == null) {
                dc.drawText(centerX + 10, top + 27, Graphics.FONT_XTINY, "N/A", Graphics.TEXT_JUSTIFY_LEFT);
            } else {
                dc.drawText(centerX + 12, top + 20, Graphics.FONT_LARGE, heartRate.toNumber().toString(), Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(centerX + 13, top + 42, Graphics.FONT_XTINY, "BPM", Graphics.TEXT_JUSTIFY_LEFT);
            }
        } else {
            var exertion = app.getExertionPercent();
            dc.drawText(centerX, top + 19, Graphics.FONT_LARGE, app.isExertionAvailable() ? exertion.toNumber().format("%.0f") + "%" : "N/A", Graphics.TEXT_JUSTIFY_CENTER);
            drawStrengthGlyph(dc, centerX, top + 50);
        }
    }

    function drawHeartbeat(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y + 7, x + 9, y + 7);
        dc.drawLine(x + 9, y + 7, x + 14, y - 1);
        dc.drawLine(x + 14, y - 1, x + 19, y + 16);
        dc.drawLine(x + 19, y + 16, x + 25, y + 4);
        dc.drawLine(x + 25, y + 4, x + 31, y + 7);
        dc.drawLine(x + 31, y + 7, x + 40, y + 7);
    }

    function drawStrengthGlyph(dc as Graphics.Dc, centerX as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - 17, y, centerX + 17, y);
        dc.drawLine(centerX - 14, y - 6, centerX - 14, y + 6);
        dc.drawLine(centerX - 10, y - 6, centerX - 10, y + 6);
        dc.drawLine(centerX + 10, y - 6, centerX + 10, y + 6);
        dc.drawLine(centerX + 14, y - 6, centerX + 14, y + 6);
    }

    function drawMainActions(dc as Graphics.Dc) as Void {
        var centerY = (screenHeight * 0.51).toNumber();
        var buttonWidth = (screenWidth * 0.39).toNumber();
        var buttonHeight = (screenHeight * 0.16).toNumber();
        var left = 8;
        var right = screenWidth - buttonWidth - 8;
        var alerting = app.getTakClient().isAlerting();
        dc.setColor(Graphics.COLOR_RED, alerting ? Graphics.COLOR_RED : Graphics.COLOR_TRANSPARENT);
        if (alerting) { dc.fillRectangle(left, centerY - buttonHeight / 2, buttonWidth, buttonHeight); }
        dc.drawRectangle(left, centerY - buttonHeight / 2, buttonWidth, buttonHeight);
        dc.setColor(alerting ? Graphics.COLOR_WHITE : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + buttonWidth / 2, centerY - 8, Graphics.FONT_SMALL, "ALERT", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(right, centerY - buttonHeight / 2, buttonWidth, buttonHeight);
        var pinX = right + buttonWidth / 2;
        var pinY = centerY - 2;
        dc.drawCircle(pinX, pinY - 5, 8);
        dc.drawLine(pinX - 6, pinY + 1, pinX, pinY + 12);
        dc.drawLine(pinX + 6, pinY + 1, pinX, pinY + 12);
        dc.drawCircle(pinX, pinY - 5, 3);
        dc.drawLine(pinX + 12, pinY - 3, pinX + 20, pinY - 3);
        dc.drawLine(pinX + 16, pinY - 7, pinX + 16, pinY + 1);
    }

    function drawShortcuts(dc as Graphics.Dc) as Void {
        var y = (screenHeight * 0.68).toNumber();
        var centerX = screenWidth / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centerX - 72, y, 15);
        dc.drawText(centerX - 72, y - 7, Graphics.FONT_XTINY, "CHAT", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawCircle(centerX + 72, y, 15);
        dc.drawText(centerX + 72, y - 7, Graphics.FONT_XTINY, "MAP", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawCircle(centerX, y - 3, 7);
        dc.drawCircle(centerX, y - 3, 3);
        for (var tooth = 0; tooth < 8; tooth++) {
            var angle = Math.toRadians(tooth * 45);
            var innerX = centerX + (Math.sin(angle) * 7).toNumber();
            var innerY = y - 3 - (Math.cos(angle) * 7).toNumber();
            var outerX = centerX + (Math.sin(angle) * 10).toNumber();
            var outerY = y - 3 - (Math.cos(angle) * 10).toNumber();
            dc.drawLine(innerX, innerY, outerX, outerY);
        }
        var callsign = app.getCallsign();
        if (callsign.length() > 0) { dc.drawText(centerX, y + 9, Graphics.FONT_XTINY, callsign, Graphics.TEXT_JUSTIFY_CENTER); }
    }

    function drawCompassPanel(dc as Graphics.Dc) as Void {
        var mapView = app.getMapView();
        var hasTarget = mapView.isBloodhoundActive();
        var info = Position.getInfo();
        var heading = info == null ? null : info.heading;
        var hasPosition = info != null && info.position != null;
        var compassAvailable = heading != null;
        var label = hasTarget ? mapView.getBloodhoundTitle() : "Compass";
        var value = hasTarget ? (hasPosition ? mapView.getBloodhoundRangeMeters().toString() + " m" : "___") : "___";
        var centerY = screenHeight - 44;
        var panelInset = safeHorizontalInset(centerY) + 4;
        var centerX = panelInset + 9;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(panelInset + 26, screenHeight - 62, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(panelInset + 26, screenHeight - 45, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_LEFT);
        if (!compassAvailable) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        }
        var bearing = hasTarget ? mapView.getBloodhoundBearingDegrees() : 0;
        var headingDegrees = heading == null ? 0 : Math.toDegrees(heading as Float);
        var relative = bearing - headingDegrees;
        while (relative < 0) { relative += 360; }
        while (relative >= 360) { relative -= 360; }
        drawCompassArrow(dc, centerX, centerY, relative.toFloat());
        if (!compassAvailable || (hasTarget && !hasPosition)) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenWidth - panelInset - 4, screenHeight - 45, Graphics.FONT_XTINY, "N/A", Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    function drawCompassArrow(dc as Graphics.Dc, centerX as Number, centerY as Number, degrees as Float) as Void {
        var angle = Math.toRadians(degrees);
        var tipX = centerX + (Math.sin(angle) * 14).toNumber();
        var tipY = centerY - (Math.cos(angle) * 14).toNumber();
        dc.drawLine(centerX, centerY + 9, tipX, tipY);
        dc.drawLine(tipX, tipY, centerX + (Math.sin(angle - 0.5) * 7).toNumber(), centerY - (Math.cos(angle - 0.5) * 7).toNumber());
        dc.drawLine(tipX, tipY, centerX + (Math.sin(angle + 0.5) * 7).toNumber(), centerY - (Math.cos(angle + 0.5) * 7).toNumber());
    }
}

class DashboardDelegate extends WatchUi.InputDelegate {
    var app as StandaloneApp;
    var view as DashboardView;

    function initialize(application as StandaloneApp, dashboard as DashboardView) {
        InputDelegate.initialize();
        app = application;
        view = dashboard;
    }

    function onTap(evt) as Boolean {
        var coordinates = evt.getCoordinates();
        var x = coordinates[0];
        var y = coordinates[1];
        var width = System.getDeviceSettings().screenWidth;
        var height = System.getDeviceSettings().screenHeight;
        if (y < 48 && x < 110) {
            openNetworkPreferences();
        } else if (y >= height * 0.13 && y < height * 0.40 && x > width * 0.24 && x < width * 0.76) {
            openMetricMenu();
        } else if (y >= height * 0.40 && y < height * 0.60) {
            if (x < width / 2) { openManualAlert(); }
            else { openPointTypePicker(); }
        } else if (y >= height * 0.62 && y < height * 0.78) {
            if (x < width * 0.34) { openChat(); }
            else if (x > width * 0.66) { openMap(); }
            else { openSettings(); }
        } else if (y >= height * 0.78) {
            WatchUi.pushView(new BloodhoundCompassView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    function onKey(evt) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_MENU) {
            WatchUi.pushView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_LEFT);
            return true;
        }
        return false;
    }

    function openNetworkPreferences() as Void {
        var menu = buildNetworkPreferencesMenu(app);
        WatchUi.pushView(menu, new NetworkPreferencesDelegate(app, menu), WatchUi.SLIDE_LEFT);
    }

    function openMetricMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Display Metric"});
        var alertsOn = app.isPhysiologicalAlertsEnabled();
        menu.addItem(new WatchUi.MenuItem("Physiological Alerts", alertsOn ? "On" : "Off", :dashboardPhysiologyAlerts, null));
        var exertion = app.getExertionPercent();
        var heartRate = app.getHeartRate();
        menu.addItem(new WatchUi.MenuItem("Exertion", app.isExertionAvailable() ? exertion.toNumber().format("%.0f") + "%" : "N/A", :dashboardExertion, null));
        menu.addItem(new WatchUi.MenuItem("Heart Rate", heartRate == null ? "N/A" : heartRate.toNumber().toString() + " BPM", :dashboardHeartRate, null));
        WatchUi.pushView(menu, new DashboardMetricDelegate(app), WatchUi.SLIDE_UP);
    }

    function openManualAlert() as Void {
        WatchUi.pushView(buildSosMenu(app), new SosMenuDelegate(app, false), WatchUi.SLIDE_UP);
    }

    function openPointTypePicker() as Void {
        var view = new PointDropTypePickerView(app);
        WatchUi.pushView(view, new PointDropTypePickerDelegate(app, view), WatchUi.SLIDE_UP);
    }

    function openChat() as Void {
        WatchUi.pushView(buildChatMenu(app), new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
    }

    function openSettings() as Void {
        WatchUi.pushView(buildSettingsMenu(app), new SettingsMenuDelegate(app), WatchUi.SLIDE_LEFT);
    }

    function openMap() as Void {
        var mapView = app.getMapView();
        mapView.setTakClient(app.getTakClient());
        WatchUi.pushView(mapView, new StandaloneMapDelegate(mapView, false, app), WatchUi.SLIDE_LEFT);
    }
}

class DashboardMetricDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :dashboardPhysiologyAlerts) {
            app.setPhysiologicalAlertsEnabled(!app.isPhysiologicalAlertsEnabled());
            item.setSubLabel(app.isPhysiologicalAlertsEnabled() ? "On" : "Off");
        } else if (id == :dashboardExertion) {
            app.setDashboardMetric("Exertion");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :dashboardHeartRate) {
            app.setDashboardMetric("Heart Rate");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class PointDropTypePickerView extends WatchUi.View {
    var app as StandaloneApp;
    var selectedIndex as Number = 3;
    var screenWidth as Number = 0;
    var screenHeight as Number = 0;

    function initialize(application as StandaloneApp) {
        View.initialize();
        app = application;
        screenWidth = System.getDeviceSettings().screenWidth;
        screenHeight = System.getDeviceSettings().screenHeight;
        var defaultType = app.getMapView().getDefaultPointType();
        selectedIndex = defaultType == :hostile ? 0 : defaultType == :neutral ? 1 : defaultType == :friendly ? 2 : 3;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        screenWidth = dc.getWidth();
        screenHeight = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, screenWidth, screenHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var centerX = screenWidth / 2;
        var centerY = screenHeight / 2;
        dc.drawCircle(centerX, centerY, 70);
        drawType(dc, centerX, centerY - 55, 0, "HOSTILE", Graphics.COLOR_RED, :hostile);
        drawType(dc, centerX - 55, centerY, 1, "NEUTRAL", Graphics.COLOR_GREEN, :neutral);
        drawType(dc, centerX + 55, centerY, 2, "FRIENDLY", Graphics.createColor(255, 0, 255, 255), :friendly);
        drawType(dc, centerX, centerY + 55, 3, "UNKNOWN", Graphics.COLOR_YELLOW, :unknown);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
        dc.fillCircle(centerX, centerY, 24);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, centerY - 8, Graphics.FONT_MEDIUM, "X", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, screenHeight - 20, Graphics.FONT_XTINY, "Tap X to cancel; hold X for marker tools", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawType(dc as Graphics.Dc, x as Number, y as Number, index as Number, label as String, color as Number, kind as Symbol) as Void {
        var radius = index == selectedIndex ? 24 : 20;
        var drawable = kind == :hostile ? Rez.Drawables.HostileIcon : kind == :neutral ? Rez.Drawables.NeutralIcon : kind == :friendly ? Rez.Drawables.FriendlyIcon : Rez.Drawables.UnknownIcon;
        var icon = WatchUi.loadResource(drawable) as WatchUi.BitmapResource;
        dc.drawBitmap(x - icon.getWidth() / 2, y - icon.getHeight() / 2, icon);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 25, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
        if (index == selectedIndex) { dc.drawCircle(x, y, radius); }
        dc.drawText(x, y - 6, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class PointDropTypePickerDelegate extends WatchUi.InputDelegate {
    var app as StandaloneApp;
    var picker as PointDropTypePickerView;
    var suppressTap as Boolean = false;

    function initialize(application as StandaloneApp, pointPicker as PointDropTypePickerView) {
        InputDelegate.initialize();
        app = application;
        picker = pointPicker;
    }

    function onTap(evt) as Boolean {
        if (suppressTap) {
            suppressTap = false;
            return true;
        }
        var coordinates = evt.getCoordinates();
        var x = coordinates[0];
        var y = coordinates[1];
        var centerX = picker.screenWidth / 2;
        var centerY = picker.screenHeight / 2;
        var deltaX = x - centerX;
        var deltaY = y - centerY;
        if (deltaX * deltaX + deltaY * deltaY <= 24 * 24) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (deltaY < -deltaX.abs() * 0.65) {
            drop(:hostile);
        } else if (deltaX < -deltaY.abs() * 0.65) {
            drop(:neutral);
        } else if (deltaX > deltaY.abs() * 0.65) {
            drop(:friendly);
        } else {
            drop(:unknown);
        }
        return true;
    }

    function onHold(evt) as Boolean {
        var coordinates = evt.getCoordinates();
        var centerX = picker.screenWidth / 2;
        var centerY = picker.screenHeight / 2;
        var deltaX = coordinates[0] - centerX;
        var deltaY = coordinates[1] - centerY;
        if (deltaX * deltaX + deltaY * deltaY <= 30 * 30) {
            suppressTap = true;
            var menu = new WatchUi.Menu2({:title => "Marker Tools"});
            menu.addItem(new WatchUi.MenuItem("Dropped Markers", null, :droppedMarkers, null));
            menu.addItem(new WatchUi.MenuItem("Back", null, :markerToolsBack, null));
            menu.addItem(new WatchUi.MenuItem("Clear Last Marker", null, :clearLastMarker, null));
            WatchUi.pushView(menu, new PointToolsMenuDelegate(app), WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    function onKey(evt) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (key == WatchUi.KEY_UP) {
            picker.selectedIndex = 0;
            WatchUi.requestUpdate();
        } else if (key == WatchUi.KEY_LEFT) {
            picker.selectedIndex = 1;
            WatchUi.requestUpdate();
        } else if (key == WatchUi.KEY_RIGHT) {
            picker.selectedIndex = 2;
            WatchUi.requestUpdate();
        } else if (key == WatchUi.KEY_DOWN) {
            picker.selectedIndex = 3;
            WatchUi.requestUpdate();
        } else if (key == WatchUi.KEY_ENTER) {
            drop(kindForIndex(picker.selectedIndex));
        } else if (key == WatchUi.KEY_MENU) {
            var menu = new WatchUi.Menu2({:title => "Marker Tools"});
            menu.addItem(new WatchUi.MenuItem("Dropped Markers", null, :droppedMarkers, null));
            menu.addItem(new WatchUi.MenuItem("Back", null, :markerToolsBack, null));
            menu.addItem(new WatchUi.MenuItem("Clear Last Marker", null, :clearLastMarker, null));
            WatchUi.pushView(menu, new PointToolsMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else {
            return false;
        }
        return true;
    }

    function drop(kind as Symbol) as Void {
        var mapView = app.getMapView();
        if (mapView.dropAtCurrentLocationAs(kind)) {
            WatchUi.showToast(app.text(:pointDropped), null);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.showToast(app.text(:locationUnavailable), null);
        }
    }

    function kindForIndex(index as Number) as Symbol {
        if (index == 0) { return :hostile; }
        else if (index == 1) { return :neutral; }
        else if (index == 2) { return :friendly; }
        return :unknown;
    }
}

class PointToolsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mapView = app.getMapView();
        if (item.getId() == :droppedMarkers) {
            var menu = buildDroppedMarkersMenu(mapView);
            WatchUi.pushView(menu, new DroppedMarkersMenuDelegate(mapView, menu), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :clearLastMarker) {
            if (!mapView.hasPoints()) {
                WatchUi.showToast("No markers to clear", null);
                return;
            }
            var confirm = new WatchUi.Menu2({:title => "Clear Last Marker?"});
            confirm.addItem(new WatchUi.MenuItem("Clear Last Marker", null, :confirmClearLast, null));
            confirm.addItem(new WatchUi.MenuItem("Cancel", null, :cancelClearLast, null));
            WatchUi.pushView(confirm, new PointDeletionConfirmationDelegate(mapView, :last), WatchUi.SLIDE_UP);
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

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
                mapView.deleteLastPoint();
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            } else if (deletion == :all) {
                mapView.clearDroppedPoints();
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                var list = buildDroppedMarkersMenu(mapView);
                WatchUi.pushView(list, new DroppedMarkersMenuDelegate(mapView, list), WatchUi.SLIDE_LEFT);
            } else {
                mapView.deletePoint(deletion as String);
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