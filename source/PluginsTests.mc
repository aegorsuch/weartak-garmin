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
    var labels = ["Commands", "Ditto", "Everywhere Comms", "GoTenna", "Somewear Labs"];
    var ids = [:commands, :ditto, :everywhereComms, :goTenna, :somewearLabs];
    var positions = [0, 2, 3, 4, 5];
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
        :goTenna, :somewearLabs, :sameLabel, :zulu];
    for (var i = 0; i < expected.size(); i++) {
        Test.assertEqual(menu.getItem(i).getId(), expected[i]);
    }
    Test.assertEqual(extra[0].getId(), :zulu);
    return true;
}
