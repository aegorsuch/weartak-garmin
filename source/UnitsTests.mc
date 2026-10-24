import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
class TestDistanceUnitsReceiver {
    var units as String? = null;

    function receive(value as String?) as Void {
        units = value;
    }
}

(:test)
function distanceFormattingRespectsDisplayUnits(logger) as Boolean {
    Test.assertEqual(formatDistanceInUnits(999.0, "Metric", 0), "999 m");
    Test.assertEqual(formatDistanceInUnits(1000.0, "Metric", 1), "1.0 km");
    Test.assertEqual(formatDistanceInUnits(1000.0, "Imperial", 0), "3281 ft");
    Test.assertEqual(formatDistanceInUnits(1609.344, "Imperial", 1), "1.0 mi");
    Test.assertEqual(formatDistanceInUnits(3218.688, "Imperial", 2), "2.00 mi");
    Test.assertEqual(distanceUnitsForAtakRangePreference("0"), "Imperial");
    Test.assertEqual(distanceUnitsForAtakRangePreference("1"), "Metric");
    Test.assertEqual(distanceUnitsForAtakRangePreference("2"), "Imperial");
    Test.assert(distanceUnitsForAtakRangePreference("3") == null);
    return true;
}

(:test)
function distanceUnitPreferencesAreVisibleAndPersisted(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = app.getDistanceUnitPreference();
    var settings = buildSettingsMenu(app);
    Test.assert(settings.findItemById(:displayPreferences) >= 0);
    var display = buildDisplayPreferencesMenu(app);
    Test.assert(display.findItemById(:distanceUnits) >= 0);
    var choices = buildDistanceUnitsMenu(app);
    Test.assert(choices.findItemById(:metric) >= 0);
    Test.assert(choices.findItemById(:imperial) >= 0);
    Test.assert(app.setDistanceUnitPreference("Imperial"));
    Test.assertEqual(Application.Storage.getValue("distanceUnitPreference"), "Imperial");
    Test.assert(app.setDistanceUnitPreference(previous));
    return true;
}

(:test)
function relayUnitsAreCapabilityAndSessionGated(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    var receiver = new TestDistanceUnitsReceiver();
    receiver.units = "Imperial";
    relay.unitPreferencesCallback = receiver.method(:receive);
    var valid = {"relaySession" => relay.relaySession, "reliableDelivery" => true,
        "unitPrefsVersion" => 1, "unitPrefs" => {"rab_rng_units_pref" => "1"}};
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Metric");

    valid.put("unitPrefs", {"rab_rng_units_pref" => "2"});
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Imperial");

    valid.put("unitPrefs", {"rab_rng_units_pref" => "bad"});
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Imperial");

    valid.put("unitPrefs", {"rab_rng_units_pref" => "0"});
    valid.put("unitPrefsVersion", "1");
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Imperial");

    valid.put("unitPrefsVersion", 1);
    valid.put("relaySession", "stale-session");
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Imperial");

    valid.put("relaySession", relay.relaySession);
    valid.remove("unitPrefsVersion");
    relay.applyRelayStatus(valid);
    Test.assertEqual(receiver.units, "Imperial");
    return true;
}

(:test)
function customManualAlertsPersistAndDelete(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var label = "Garmin Test Alert";
    var alreadyExisted = false;
    var saved = app.getCustomManualAlerts();
    for (var index = 0; index < saved.size(); index++) {
        if (saved[index].equals(label)) { alreadyExisted = true; break; }
    }
    if (alreadyExisted) { Test.assert(app.removeCustomManualAlert(label)); }

    Test.assert(app.addCustomManualAlert("  " + label + "  ") == null);
    Test.assert(app.getCustomManualAlerts().indexOf(label) >= 0);
    app.loadCustomManualAlerts();
    Test.assert(app.getCustomManualAlerts().indexOf(label) >= 0);
    Test.assert(app.addCustomManualAlert(label.toLower()) != null);
    Test.assert(app.addCustomManualAlert("   ") != null);
    var menu = buildSosMenu(app);
    var deletion = null;
    for (var index = 0; menu.getItem(index) != null; index++) {
        var item = menu.getItem(index);
        if (item.getId() == :customAlert && (item.getLabel() as String).equals(label)) {
            deletion = menu.getItem(index + 1);
            break;
        }
    }
    Test.assert(deletion instanceof Toybox.WatchUi.IconMenuItem);
    Test.assertEqual((deletion.getId() as Dictionary).get("deleteAlert"), label);
    Test.assertEqual(deletion.getLabel(), Toybox.WatchUi.loadResource(Rez.Strings.TextDelete) + " " + label);
    Test.assert(deletion.getSubLabel() == null);
    Test.assert(menu.findItemById(:deleteCustomAlerts) < 0);
    var client = app.getTakClient();
    var wasAlerting = client.isAlerting();
    var previousType = client.getAlertType();
    var queuedCount = client.pointReplies.replies.size();
    new SosMenuDelegate(app, false).onSelect(deletion);
    Test.assert(app.getCustomManualAlerts().indexOf(label) < 0);
    app.loadCustomManualAlerts();
    Test.assert(app.getCustomManualAlerts().indexOf(label) < 0);
    Test.assertEqual(client.isAlerting(), wasAlerting);
    Test.assertEqual(client.getAlertType(), previousType);
    Test.assertEqual(client.pointReplies.replies.size(), queuedCount);
    if (alreadyExisted) { Test.assert(app.addCustomManualAlert(label) == null); }
    return true;
}
