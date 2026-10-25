import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function coordinateTitleNativeFontBoundsProbe(logger) as Boolean {
    var app = new TestTopMetricApp();
    var actual = Application.getApp() as StandaloneApp;
    var previous = actual.getDashboardMetric();
    var buffer;
    var bitmap;
    var size = Toybox.System.getDeviceSettings().screenWidth;
    if (Graphics has :createBufferedBitmap) {
        buffer = Graphics.createBufferedBitmap({:width => size, :height => size});
        bitmap = buffer.get();
    } else { bitmap = new Graphics.BufferedBitmap({:width => size, :height => size}); }
    var dc = bitmap.getDc();
    var height = dc.getFontHeight(Graphics.FONT_XTINY);
    logger.debug("Native XTINY height=" + height);
    var title = new TopMetricTitle(app);
    Test.assert(title.readingOffset >= 4 + height + 4);
    Test.assert(title.readingPitch >= height + 2);
    Test.assert(title.readingOffset + title.readingPitch + height + 4 <= title.height);
    var metrics = ["MGRS", "Lat/Long"];
    var coordinates = [[38.8977, -77.0365], [-79.99999, -179.99999],
        [83.99999, 179.99999], [0.0, 180.0]];
    for (var metric = 0; metric < metrics.size(); metric++) {
        app.setDashboardMetric(metrics[metric]);
        for (var location = 0; location < coordinates.size(); location++) {
            app.location = new Position.Location({:latitude => coordinates[location][0],
                :longitude => coordinates[location][1], :format => :degrees});
            var lines = title.readingLines();
            if (metrics[metric].equals("MGRS")) { Test.assertEqual(lines.size(), 1); }
            for (var i = 0; i < lines.size(); i++) {
                var textWidth = dc.getTextWidthInPixels(lines[i], Graphics.FONT_XTINY);
                // Conservatively use the round-screen chord at the top of each line.
                var y = title.readingTop(dc, lines[i]) + i * title.readingPitch;
                var radius = size / 2;
                var dy = radius - y;
                var available = 2 * Toybox.Math.sqrt(radius * radius - dy * dy) - 8;
                logger.debug(metrics[metric] + " " + lines[i] + ": width=" + textWidth + " available=" + available);
                Test.assert(textWidth <= available);
                Test.assert(y + height + 4 <= title.height);
            }
            title.draw(dc);
        }
    }
    actual.setDashboardMetric(previous);
    return true;
}

(:test)
function coordinateTitleKeepsFullPrecision(logger) as Boolean {
    var app = new TestTopMetricApp();
    var actual = Application.getApp() as StandaloneApp;
    var previous = actual.getDashboardMetric();
    app.location = new Position.Location({:latitude => 38.8977, :longitude => -77.0365, :format => :degrees});
    app.setDashboardMetric("MGRS");
    Test.assertEqual(app.dashboardMetricLines()[0], "18S UJ");
    Test.assertEqual(app.dashboardMetricLines()[1], "23394 07395");
    Test.assertEqual(new TopMetricTitle(app).readingLines()[0], "18S UJ 23394 07395");
    app.setDashboardMetric("Lat/Long");
    Test.assertEqual(app.dashboardMetricLines()[0], "38.89770,");
    Test.assertEqual(app.dashboardMetricLines()[1], "-77.03650");
    actual.setDashboardMetric(previous);
    return true;
}

(:test)
class TestTopMetricApp extends StandaloneApp {
    var location as Position.Location? = null;
    var heartRate as Number? = null;
    var exertionAvailable as Boolean = false;
    var steps as Number? = null;
    var monitoring as Boolean = true;
    function initialize() {}
    function getDashboardLocation() as Position.Location? { return location; }
    function getHeartRate() as Number? { return heartRate; }
    function isExertionAvailable() as Boolean { return exertionAvailable; }
    function getExertionPercent() as Number { return 73; }
    function getDashboardSteps() as Number? { return steps; }
    function isPhysiologicalMonitoringEnabled() as Boolean { return monitoring; }
    function getMapView() as StandaloneMapView { return (Application.getApp() as StandaloneApp).getMapView(); }
}

(:test)
function topMetricChoicesAreExactSortedAndDoNotToggleRuntime(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = app.getDashboardMetric();
    var alerts = app.isPhysiologicalAlertsEnabled();
    var monitors = app.isPhysiologicalMonitoringEnabled();
    var menu = buildTopMetricMenu(app);
    var expected = ["Exertion", "Heart Rate", "Lat/Long", "MGRS", "Skin Temp", "Steps"];
    var entries = [];
    for (var i = 0; i < expected.size(); i++) {
        entries.add({"id" => expected[i], "label" => app.dashboardMetricLabel(expected[i])});
    }
    sortMenuEntriesByLabel(entries);
    var delegate = new TopMetricDelegate(app, menu, null);
    for (var i = 0; i < expected.size(); i++) {
        Test.assertEqual(menu.getItem(i + 4).getId(), entries[i].get("id"));
        Test.assertEqual(menu.getItem(i + 4).getLabel(), entries[i].get("label"));
        delegate.onSelect(menu.getItem(i + 4));
        Test.assertEqual(app.getDashboardMetric(), entries[i].get("id"));
        Test.assertEqual(Application.Storage.getValue("dashboardMetric"), entries[i].get("id"));
        Test.assertEqual(app.isPhysiologicalAlertsEnabled(), alerts);
        Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), monitors);
    }
    Test.assertEqual(menu.getItem(0).getId(), :topEnvironmentalAlerts);
    Test.assertEqual(menu.getItem(1).getId(), :topAlerts);
    Test.assertEqual(menu.getItem(2).getId(), :topMonitors);
    Test.assertEqual(menu.getItem(3).getId(), :topAlertThresholds);
    Test.assert(menu.getItem(10) == null);
    Test.assert((menu.getItem(menu.findItemById("Skin Temp")).getSubLabel() as String)
        .find(app.text(monitors ? Rez.Strings.TextUnavailable : Rez.Strings.LabelDisabled)) != null);
    Test.assert(buildDisplayPreferencesMenu(app).findItemById(:topMetric) >= 0);
    app.setDashboardMetric(previous);
    return true;
}

(:test)
function topMetricStoredSelectionMigratesAndStepsSurvives(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = app.getDashboardMetric();
    var removed = ["Altitude", "Pressure", "", 42];
    for (var i = 0; i < removed.size(); i++) {
        Application.Storage.setValue("dashboardMetric", removed[i]);
        app.loadDashboardMetric();
        Test.assertEqual(app.getDashboardMetric(), "Exertion");
        Test.assertEqual(Application.Storage.getValue("dashboardMetric"), "Exertion");
    }
    app.setDashboardMetric("Steps");
    app.loadDashboardMetric();
    Test.assertEqual(app.getDashboardMetric(), "Steps");
    app.setDashboardMetric("Pressure");
    Test.assertEqual(app.getDashboardMetric(), "Steps");
    app.setDashboardMetric(previous);
    return true;
}

(:test)
function topMetricPreviewsDoNotChangeSelectionAndRefresh(logger) as Boolean {
    var app = new TestTopMetricApp();
    var stored = Application.Storage.getValue("dashboardMetric");
    var selected = app.getDashboardMetric();
    app.heartRate = 90;
    app.steps = 1234;
    var menu = new TopMetricMenu(app);
    Test.assertEqual(menu.getItem(menu.findItemById("Heart Rate")).getSubLabel(), "90 BPM");
    Test.assertEqual(menu.getItem(menu.findItemById("Steps")).getSubLabel(), "1234");
    app.heartRate = 91;
    var bitmap = Graphics.createBufferedBitmap({:width => 280, :height => 280});
    menu.onUpdate((bitmap.get() as Graphics.BufferedBitmap).getDc());
    Test.assertEqual(menu.getItem(menu.findItemById("Heart Rate")).getSubLabel(), "91 BPM");
    app.monitoring = false;
    menu.refreshMetricReadings();
    Test.assertEqual(menu.getItem(menu.findItemById("Steps")).getSubLabel(), app.text(Rez.Strings.LabelDisabled));
    Test.assertEqual(menu.getItem(menu.findItemById("Skin Temp")).getSubLabel(), app.text(Rez.Strings.LabelDisabled));
    Test.assertEqual(menu.getItem(menu.findItemById("Lat/Long")).getSubLabel(), app.text(Rez.Strings.TextWaitingForLocation));
    Test.assertEqual(app.getDashboardMetric(), selected);
    if (stored == null) { Test.assert(Application.Storage.getValue("dashboardMetric") == null); }
    else { Test.assertEqual(Application.Storage.getValue("dashboardMetric"), stored); }
    return true;
}

(:test)
function topMetricReadingsUseRealDataOrUnavailable(logger) as Boolean {
    var actual = Application.getApp() as StandaloneApp;
    var previous = actual.getDashboardMetric();
    var app = new TestTopMetricApp();
    var unavailable = app.text(Rez.Strings.TextUnavailable);
    app.setDashboardMetric("Exertion");
    Test.assertEqual(app.dashboardMetricLines()[0], unavailable);
    app.exertionAvailable = true;
    Test.assertEqual(app.dashboardMetricLines()[0], "73%");
    app.setDashboardMetric("Heart Rate");
    Test.assertEqual(app.dashboardMetricLines()[0], unavailable);
    app.heartRate = 85;
    Test.assertEqual(app.dashboardMetricLines()[0], "85 BPM");
    app.setDashboardMetric("Steps");
    Test.assertEqual(app.dashboardMetricLines()[0], unavailable);
    app.steps = 12345;
    Test.assertEqual(app.dashboardMetricLines()[0], "12345");
    app.setDashboardMetric("Skin Temp");
    Test.assertEqual(app.dashboardMetricLines()[0], unavailable);
    app.monitoring = false;
    var dependent = ["Exertion", "Heart Rate", "Skin Temp", "Steps"];
    for (var i = 0; i < dependent.size(); i++) {
        app.setDashboardMetric(dependent[i]);
        Test.assertEqual(app.dashboardMetricLines()[0], app.text(Rez.Strings.LabelDisabled));
    }
    app.setDashboardMetric("Steps");
    Test.assertEqual(app.dashboardMetricLines()[0], app.text(Rez.Strings.LabelDisabled));
    app.setDashboardMetric("Lat/Long");
    Test.assertEqual(app.dashboardMetricLines()[0], app.text(Rez.Strings.TextWaitingForLocation));
    app.location = new Position.Location({:latitude => 38.8977, :longitude => -77.0365, :format => :degrees});
    Test.assertEqual(app.dashboardMetricLines()[0], "38.89770,");
    Test.assertEqual(app.dashboardMetricLines()[1], "-77.03650");
    app.setDashboardMetric("MGRS");
    Test.assertEqual(app.dashboardMetricLines()[0], "18S UJ");
    Test.assertEqual(app.dashboardMetricLines()[1], "23394 07395");
    Test.assert(!app.isPhysiologicalMonitoringEnabled());
    app.location = new Position.Location({:latitude => 85.0, :longitude => 0.0, :format => :degrees});
    Test.assertEqual(app.dashboardMetricLines()[0], unavailable);
    actual.setDashboardMetric(previous);
    return true;
}

(:test)
function topMetricGpsRequiresUsableFreshEnabledFix(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var location = new Position.Location({:latitude => 0.0, :longitude => 180.0, :format => :degrees});
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_GOOD, 100, 100, true) != null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_USABLE, 100, 160, true) != null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_POOR, 100, 100, true) == null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_GOOD, 100, 161, true) == null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_GOOD, 100, 99, true) == null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_GOOD, 100, 100, false) == null);
    Test.assert(app.dashboardLocationFromFix(null, Position.QUALITY_GOOD, 100, 100, true) == null);
    Test.assert(app.dashboardLocationFromFix(location, Position.QUALITY_GOOD, null, 100, true) == null);
    Test.assert(app.getMapView().mgrsFromLatLon(0.0, 180.0).find("60N") == 0);
    return true;
}

(:test)
function topMetricAlertsAndMonitorsAreIndependentAndThresholdsRemainEditable(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var alerts = app.isPhysiologicalAlertsEnabled();
    var monitors = app.isPhysiologicalMonitoringEnabled();
    var threshold = app.getAlertSetting(:exertionWarningThreshold);
    var menu = buildTopMetricMenu(app);
    var delegate = new TopMetricDelegate(app, menu, null);
    delegate.onSelect(menu.getItem(menu.findItemById(:topAlerts)));
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), !alerts);
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), monitors);
    Test.assertEqual(app.getAlertSetting(:exertionWarningThreshold), threshold);
    delegate.onSelect(menu.getItem(menu.findItemById(:topAlerts)));
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), alerts);
    delegate.onSelect(menu.getItem(menu.findItemById(:topMonitors)));
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), !monitors);
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), alerts);
    delegate.onSelect(menu.getItem(menu.findItemById(:topMonitors)));
    app.setPhysiologicalAlertsEnabled(false);
    delegate.onSelect(menu.getItem(menu.findItemById(:topAlertThresholds)));
    Test.assert(!app.isPhysiologicalAlertsEnabled());
    Test.assertEqual(app.getAlertSetting(:exertionWarningThreshold), threshold);
    Test.assert(buildPhysiologicalAlertsMenu(app).findItemById(:exertionAlerts) >= 0);
    app.setAlertSetting(:exertionWarningThreshold, threshold == 80 ? 81 : 80);
    Test.assert(!app.isPhysiologicalAlertsEnabled());
    Test.assertEqual(app.getAlertSetting(:exertionWarningThreshold), threshold == 80 ? 81 : 80);
    app.setAlertSetting(:exertionWarningThreshold, threshold);
    app.setPhysiologicalAlertsEnabled(alerts);
    (menu as TopMetricMenu).onShow();
    Test.assertEqual(menu.getItem(menu.findItemById(:topAlerts)).getSubLabel(), app.text(alerts ? Rez.Strings.TextOn : Rez.Strings.TextOff));
    Test.assertEqual(menu.getItem(menu.findItemById(:topMonitors)).getSubLabel(), app.text(monitors ? Rez.Strings.TextOn : Rez.Strings.TextOff));
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), monitors);
    return true;
}

(:test)
function nativePhysioControlsAndHeartPreserveMetricBehavior(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var monitors = app.isPhysiologicalMonitoringEnabled();
    var alerts = app.isPhysiologicalAlertsEnabled();
    var metric = app.getDashboardMetric();
    var menu = buildPhysiologicalAlertsMenu(app);
    var monitoringItem = menu.getItem(menu.findItemById(:physiologicalMonitoring));
    var alertsItem = menu.getItem(menu.findItemById(:physiologicalAlertsToggle));
    Test.assertEqual(monitoringItem.getLabel(), buildTopMetricMenu(app).getItem(2).getLabel());
    Test.assertEqual(alertsItem.getLabel(), buildTopMetricMenu(app).getItem(1).getLabel());
    Test.assertEqual(buildReportingStrategyMenu(app).getItem(0).getId(), :physiologicalMonitoring);
    var delegate = new PhysiologicalAlertsDelegate(app);
    delegate.onSelect(monitoringItem);
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), !monitors);
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), alerts);
    delegate.onSelect(monitoringItem);
    delegate.onSelect(alertsItem);
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), monitors);
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), !alerts);
    delegate.onSelect(alertsItem);
    var choices = buildTopMetricMenu(app);
    var hr = choices.getItem(choices.findItemById("Heart Rate")) as WatchUi.IconMenuItem;
    Test.assert(hr.getIcon() instanceof HeartRateGlyph);
    Test.assert(!(choices.getItem(choices.findItemById("MGRS")) instanceof WatchUi.IconMenuItem));
    var bitmap = Graphics.createBufferedBitmap({:width => 280, :height => 280});
    var dc = (bitmap.get() as Graphics.BufferedBitmap).getDc();
    (hr.getIcon() as HeartRateGlyph).draw(dc);
    app.setDashboardMetric("Heart Rate");
    new TopMetricTitle(app).draw(dc);
    app.setDashboardMetric("MGRS");
    new TopMetricTitle(app).draw(dc);
    app.setDashboardMetric(metric);
    return true;
}

(:test)
function alertConfigurationMenusAlphabetizeAndKeepActions(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    Test.assertEqual(compareMenuLabels("Alerts", "alerts"), 0);
    Test.assert(compareMenuLabels("Alert", "Alerts") < 0);
    Test.assert(compareMenuLabels("Monitoring", "Alerts") > 0);
    var menus = [buildEnvironmentalAlertsMenu(app), buildPhysiologicalAlertsMenu(app),
        buildAlertingPreferencesMenu(app)];
    for (var m = 0; m < menus.size(); m++) {
        var menu = menus[m];
        for (var i = 1; menu.getItem(i) != null; i++) {
            Test.assert((menu.getItem(i - 1).getLabel() as String).toLower()
                .compareTo((menu.getItem(i).getLabel() as String).toLower()) <= 0);
        }
    }
    Test.assert(menus[0].findItemById(:immersionAlertsToggle) >= 0);
    Test.assert(menus[0].findItemById(:atmPressureAlerts) >= 0);
    Test.assertEqual(menus[1].getItem(menus[1].findItemById(:physiologicalMonitoring)).getSubLabel(),
        toolToggleLabel(app.isPhysiologicalMonitoringEnabled()));
    Test.assert(menus[1].findItemById(:physiologicalAlertsToggle) >= 0);
    Test.assert(menus[1].findItemById(:restingHeartRateAlerts) >= 0);
    Test.assert(menus[1].findItemById(:exertionAlerts) >= 0);
    var topMenu = buildTopMetricMenu(app);
    var environmental = topMenu.getItem(0);
    Test.assertEqual(environmental.getId(), :topEnvironmentalAlerts);
    Test.assertEqual(environmental.getSubLabel(), ">");
    var immersion = app.isImmersionAlertsEnabled();
    var low = app.isLowPressureAlertsEnabled();
    var high = app.isHighPressureAlertsEnabled();
    new TopMetricDelegate(app, topMenu, null).onSelect(environmental);
    Test.assertEqual(app.isImmersionAlertsEnabled(), immersion);
    Test.assertEqual(app.isLowPressureAlertsEnabled(), low);
    Test.assertEqual(app.isHighPressureAlertsEnabled(), high);
    WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    Test.assert(menus[2].findItemById(:batteryAlertsToggle) >= 0);
    Test.assert(menus[2].findItemById(:environmentalAlerts) >= 0);
    Test.assert(menus[2].findItemById(:physiologicalAlerts) >= 0);
    return true;
}
