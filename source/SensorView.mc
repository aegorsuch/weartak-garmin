import Toybox.Graphics;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.WatchUi;

class EnvironmentalSensorsView extends WatchUi.View {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        View.initialize();
        app = application;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, System.getDeviceSettings().screenWidth, System.getDeviceSettings().screenHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var screenWidth = System.getDeviceSettings().screenWidth;
        var centerX = screenWidth / 2;
        dc.drawText(centerX, 16, Graphics.FONT_MEDIUM, app.text(:environment), Graphics.TEXT_JUSTIFY_CENTER);
        var info = app.getSensorInfo();
        drawReading(dc, screenWidth, 58, app.text(:altitude), info != null ? formatValue(info.altitude, " m") : app.text(:unavailable));
        drawReading(dc, screenWidth, 90, app.text(:pressure), info != null ? formatValue(info.pressure, " Pa") : app.text(:unavailable));
        drawReading(dc, screenWidth, 122, app.text(:temperature), info != null ? formatValue(info.temperature, " C") : app.text(:unavailable));
    }

    function drawReading(dc, screenWidth, y, label, value) {
        var margin = 18;
        dc.drawText(margin, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(screenWidth - margin, y, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function formatValue(value, suffix) {
        return value == null ? "Unavailable" : value.format("%.3f") + suffix;
    }
}

class PhysiologicalSensorsView extends WatchUi.View {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        View.initialize();
        app = application;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, System.getDeviceSettings().screenWidth, System.getDeviceSettings().screenHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var centerX = System.getDeviceSettings().screenWidth / 2;
        dc.drawText(centerX, 8, Graphics.FONT_MEDIUM, app.text(:physiologyView), Graphics.TEXT_JUSTIFY_CENTER);
        var sensorInfo = app.getSensorInfo();
        drawReading(dc, centerX, 50, app.text(:exertion), formatValue(app.getExertionPercent(), "%"));
        drawReading(dc, centerX, 78, app.text(:heartRate), sensorInfo != null ? formatIntegerValue(sensorInfo.heartRate, " BPM") : app.text(:unavailable));
    }

    function drawReading(dc, x, y, label, value) {
        dc.drawText(x, y, Graphics.FONT_SMALL, label + ": " + value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function formatValue(value, suffix) {
        return value == null ? "Unavailable" : value.format("%.3f") + suffix;
    }

    function formatIntegerValue(value, suffix) {
        return value == null ? "Unavailable" : value.toNumber().toString() + suffix;
    }
}

class BloodhoundCompassView extends WatchUi.View {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        View.initialize();
        app = application;
    }

    function onUpdate(dc) {
        var screenWidth = System.getDeviceSettings().screenWidth;
        var screenHeight = System.getDeviceSettings().screenHeight;
        var centerX = screenWidth / 2;
        var centerY = screenHeight / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, screenWidth, screenHeight);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, 8, Graphics.FONT_MEDIUM, app.text(:bloodhound), Graphics.TEXT_JUSTIFY_CENTER);
        drawCompass(dc, centerX, centerY - 4, 54);
        var mapView = app.getMapView();
        if (mapView.isBloodhoundActive()) {
            var bearing = mapView.getBloodhoundBearingDegrees();
            drawArrow(dc, centerX, centerY - 4, bearing, 42);
            dc.drawText(centerX, centerY + 58, Graphics.FONT_XTINY, mapView.getBloodhoundTitle(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, centerY + 76, Graphics.FONT_XTINY, "Range: " + mapView.getBloodhoundRangeMeters().toString() + " m", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, centerY + 94, Graphics.FONT_XTINY, "True bearing: " + bearing.toString() + " deg", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            drawArrow(dc, centerX, centerY - 4, 0, 42);
            dc.drawText(centerX, centerY + 66, Graphics.FONT_XTINY, "No Bloodhound target", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, centerY + 86, Graphics.FONT_XTINY, "Tap a map point to start", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawCompass(dc, centerX, centerY, radius) as Void {
        dc.drawCircle(centerX, centerY, radius);
        dc.drawLine(centerX, centerY - radius, centerX, centerY - radius + 16);
        dc.drawLine(centerX + radius, centerY, centerX + radius - 16, centerY);
        dc.drawLine(centerX, centerY + radius, centerX, centerY + radius - 16);
        dc.drawLine(centerX - radius, centerY, centerX - radius + 16, centerY);
        dc.drawText(centerX, centerY - radius - 24, Graphics.FONT_XTINY, "N", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX + radius + 12, centerY - 8, Graphics.FONT_XTINY, "E", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, centerY + radius + 4, Graphics.FONT_XTINY, "S", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX - radius - 12, centerY - 8, Graphics.FONT_XTINY, "W", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawArrow(dc, centerX, centerY, angleDegrees, length) as Void {
        var angle = Math.toRadians(angleDegrees);
        var tipX = centerX + (Math.sin(angle) * length).toNumber();
        var tipY = centerY - (Math.cos(angle) * length).toNumber();
        var tailX = centerX - (Math.sin(angle) * 16).toNumber();
        var tailY = centerY + (Math.cos(angle) * 16).toNumber();
        dc.drawLine(tailX, tailY, tipX, tipY);
        dc.drawLine(tipX, tipY, centerX + (Math.sin(angle - 0.45) * 24).toNumber(), centerY - (Math.cos(angle - 0.45) * 24).toNumber());
        dc.drawLine(tipX, tipY, centerX + (Math.sin(angle + 0.45) * 24).toNumber(), centerY - (Math.cos(angle + 0.45) * 24).toNumber());
    }

}

class SensorViewDelegate extends WatchUi.InputDelegate {
    function onKey(evt) {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }
}