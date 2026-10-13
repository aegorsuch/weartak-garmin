import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function pluginsPlaceholdersStayOff(logger) as Boolean {
    var app = Toybox.Application.getApp() as StandaloneApp;
    var menu = buildPluginsMenu();
    var delegate = new ToolPreferencesDelegate(app);
    Test.assertEqual(menu.getItem(0).getId(), :dataSync);
    var labels = ["Everywhere Comms", "Somewear Labs"];
    var ids = [:everywhereComms, :somewearLabs];
    for (var i = 0; i < labels.size(); i++) {
        var item = menu.getItem(i + 1) as WatchUi.ToggleMenuItem;
        Test.assertEqual(item.getLabel(), labels[i]);
        Test.assertEqual(item.getId(), ids[i]);
        Test.assertEqual(item.getSubLabel(), "Unfunded Request");
        Test.assert(!item.isEnabled());
        for (var tap = 0; tap < 3; tap++) {
            delegate.onSelect(item);
            Test.assert(!item.isEnabled());
            // Simulate the native toggle state change before delegate dispatch.
            item.setEnabled(true);
            delegate.onSelect(item);
            Test.assert(!item.isEnabled());
            Test.assertEqual(item.getSubLabel(), "Unfunded Request");
        }
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
    var expected = [:alpha, :bravo, :dataSync, :echo, :everywhereComms, :somewearLabs, :sameLabel, :zulu];
    for (var i = 0; i < expected.size(); i++) {
        Test.assertEqual(menu.getItem(i).getId(), expected[i]);
    }
    Test.assertEqual(extra[0].getId(), :zulu);
    return true;
}
