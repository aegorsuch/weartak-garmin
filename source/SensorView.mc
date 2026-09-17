import Toybox.Graphics;
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
        dc.drawText(centerX, 16, Graphics.FONT_MEDIUM, "Environment", Graphics.TEXT_JUSTIFY_CENTER);
        var info = app.getSensorInfo();
        drawReading(dc, screenWidth, 58, "Altitude", info != null ? formatValue(info.altitude, " m") : "Unavailable");
        drawReading(dc, screenWidth, 90, "Pressure", info != null ? formatValue(info.pressure, " Pa") : "Unavailable");
        drawReading(dc, screenWidth, 122, "Temperature", info != null ? formatValue(info.temperature, " C") : "Unavailable");
    }

    function drawReading(dc, screenWidth, y, label, value) {
        var margin = 18;
        dc.drawText(margin, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(screenWidth - margin, y, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function formatValue(value, suffix) {
        return value == null ? "Unavailable" : value.toString() + suffix;
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
        dc.drawText(centerX, 8, Graphics.FONT_MEDIUM, "Physiology", Graphics.TEXT_JUSTIFY_CENTER);
        var sensorInfo = app.getSensorInfo();
        drawReading(dc, centerX, 50, "Heart Rate", sensorInfo != null ? formatValue(sensorInfo.heartRate, " BPM") : "Unavailable");
    }

    function drawReading(dc, x, y, label, value) {
        dc.drawText(x, y, Graphics.FONT_SMALL, label + ": " + value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function formatValue(value, suffix) {
        return value == null ? "Unavailable" : value.toString() + suffix;
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