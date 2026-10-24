import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function pluginsPlaceholdersStayOff(logger) as Boolean {
    var app = Toybox.Application.getApp() as StandaloneApp;
    var menu = buildPluginsMenu();
    var delegate = new ToolPreferencesDelegate(app);
    Test.assertEqual(menu.getItem(1).getId(), :dataSync);
    Test.assert(!(menu.getItem(1) instanceof WatchUi.ToggleMenuItem));
    Test.assert(menu.getItem(1) instanceof WatchUi.IconMenuItem);
    Test.assertEqual(menu.getItem(1).getSubLabel(), ">");
    Test.assertEqual(menu.getItem(5).getId(), :mopp);
    Test.assert(menu.getItem(5) instanceof WatchUi.IconMenuItem);
    Test.assertEqual(menu.getItem(6).getId(), :sensorManager);
    Test.assert(!(menu.getItem(6) instanceof WatchUi.ToggleMenuItem));
    Test.assertEqual(menu.getItem(6).getLabel(), "Sensor Manager");
    Test.assertEqual(menu.getItem(6).getSubLabel(), "Unfunded Request");
    var labels = ["Commands", "Ditto", "Everywhere Comms", "GoTenna", "Somewear Labs"];
    var ids = [:commands, :ditto, :everywhereComms, :goTenna, :somewearLabs];
    var positions = [0, 2, 3, 4, 7];
    var subtitles = ["Unavailable", "Unavailable", "Unfunded Request", "Unfunded Request", "Unfunded Request"];
    for (var i = 0; i < labels.size(); i++) {
        var item = menu.getItem(positions[i]) as WatchUi.ToggleMenuItem;
        Test.assertEqual(item.getLabel(), labels[i]);
        Test.assertEqual(item.getId(), ids[i]);
        Test.assertEqual(item.getSubLabel(), subtitles[i]);
        Test.assert(!item.isEnabled());
        for (var tap = 0; tap < 3; tap++) {
            delegate.onSelect(item);
            Test.assert(!item.isEnabled());
            // Simulate the native toggle state change before delegate dispatch.
            item.setEnabled(true);
            delegate.onSelect(item);
            Test.assert(!item.isEnabled());
            Test.assertEqual(item.getSubLabel(), subtitles[i]);
        }
    }
    var reopened = buildPluginsMenu();
    for (var index = 0; index < positions.size(); index++) {
        Test.assert(!(reopened.getItem(positions[index]) as WatchUi.ToggleMenuItem).isEnabled());
    }
    return true;
}

(:test)
function pluginsSortAllEntriesCaseInsensitively(logger) as Boolean {
    var extra = [
        new WatchUi.MenuItem("zulu", null, :zulu, null),
        new WatchUi.MenuItem("ALPHA", null, :alpha, null),
        new WatchUi.MenuItem("bravo", null, :bravo, null),
        new WatchUi.MenuItem("eCHO", null, :echo, null),
        new WatchUi.MenuItem("somewear labs", null, :sameLabel, null)
    ];
    var menu = buildPluginsMenuWithItems(extra);
    var expected = [:alpha, :bravo, :commands, :dataSync, :ditto, :echo, :everywhereComms,
        :goTenna, :mopp, :sensorManager, :somewearLabs, :sameLabel, :zulu];
    for (var i = 0; i < expected.size(); i++) {
        Test.assertEqual(menu.getItem(i).getId(), expected[i]);
    }
    Test.assertEqual(extra[0].getId(), :zulu);
    return true;
}

(:test)
function sensorManagerDefaultsOffAndPersistsToggle(logger) as Boolean {
    var app = Toybox.Application.getApp() as StandaloneApp;
    Toybox.Application.Storage.deleteValue("sensorManagerEnabled");
    app.loadAlertSettings();
    Test.assert(!app.isSensorManagerEnabled());
    var config = buildSensorManagerMenu(app);
    Test.assertEqual(config.getItem(0).getId(), :sensorManagerEnabledToggle);
    Test.assertEqual(config.getItem(0).getLabel(), "Enabled");
    Test.assertEqual(config.getItem(0).getSubLabel(), toolToggleLabel(false));
    Test.assertEqual(config.getItem(1).getLabel(), "Unfunded Request");
    Test.assertEqual(config.getItem(2).getLabel(), "Button is Placeholder");
    Test.assertEqual(config.getItem(3).getLabel(), "Scan");

    var delegate = new ToolPreferencesDelegate(app);
    delegate.onSelect(config.getItem(0));
    Test.assert(app.isSensorManagerEnabled());
    Test.assertEqual(Toybox.Application.Storage.getValue("sensorManagerEnabled"), true);
    Test.assertEqual(config.getItem(0).getSubLabel(), toolToggleLabel(true));
    var reopened = buildSensorManagerMenu(app);
    Test.assertEqual(reopened.getItem(0).getSubLabel(), toolToggleLabel(true));

    delegate.onSelect(reopened.getItem(3));
    Test.assert(app.isSensorManagerEnabled());
    Toybox.Application.Storage.deleteValue("sensorManagerEnabled");
    app.loadAlertSettings();
    return true;
}
