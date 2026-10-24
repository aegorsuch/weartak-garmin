import Toybox.Lang;
import Toybox.WatchUi;

function buildSosMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextManualAlert));
    var client = app.getTakClient();
    if (client.isAlerting()) {
        addMenuEntry(menu, app.text(Rez.Strings.TextClearManualAlert) + " (" + app.alertTypeLabel(client.getAlertType()) + " " + app.text(Rez.Strings.TextActive) + ")", null, :clear);
    }
    var delegate = new SosMenuDelegate(app, false);
    var ids = [:alert911, :gateRunner, :geofenceBreached, :gunshot,
        :inContact, :injury, :ringTheBell, :uas, :vehicle];
    var alerts = [];
    for (var index = 0; index < ids.size(); index++) {
        alerts.add({"id" => ids[index], "label" => app.alertTypeLabel(delegate.alertTypeFor(ids[index]))});
    }
    var customAlerts = app.getCustomManualAlerts();
    for (var index = 0; index < customAlerts.size(); index++) {
        alerts.add({"id" => :customAlert, "label" => customAlerts[index]});
    }
    sortMenuEntriesByLabel(alerts);
    for (var index = 0; index < alerts.size(); index++) {
        var alert = alerts[index] as Dictionary;
        var label = alert.get("label") as String;
        addMenuEntry(menu, label, null, alert.get("id"));
        if (alert.get("id") == :customAlert) {
            addSavedEntryDelete(menu, label, {"deleteAlert" => label});
        }
    }
    addMenuEntry(menu, "+", null, :addCustomAlert);
    return menu;
}

class SosMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var returnToMain as Boolean;

    function initialize(application as StandaloneApp, returnToMainMenu as Boolean) {
        Menu2InputDelegate.initialize();
        app = application;
        returnToMain = returnToMainMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :clear) {
            app.getTakClient().setAlerting(false);
        } else if (id == :addCustomAlert) {
            WatchUi.showToast("Type Custom Alert", null);
            WatchUi.pushView(new WatchUi.TextPicker(""),
                new CustomManualAlertTextPickerDelegate(app, returnToMain), WatchUi.SLIDE_UP);
            return;
        } else if (id instanceof Dictionary) {
            var label = (id as Dictionary).get("deleteAlert");
            if (label instanceof String && app.removeCustomManualAlert(label as String)) {
                WatchUi.switchToView(buildSosMenu(app), new SosMenuDelegate(app, returnToMain), WatchUi.SLIDE_IMMEDIATE);
            }
            return;
        } else {
            var client = app.getTakClient();
            app.refreshPliForUserAction();
            var alertType = id == :customAlert ? item.getLabel() as String : alertTypeFor(id);
            if (!client.activateManualAlert(alertType)) {
                var message = client.isConnected() ? app.text(Rez.Strings.TextLocationUnavailable) : client.statusText();
                WatchUi.showToast(message, null);
            }
        }
        if (returnToMain) {
            WatchUi.switchToView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function alertTypeFor(id) as String {
        if (id == :alert911) {
            return "911 Alert";
        } else if (id == :gateRunner) {
            return "Gate Runner";
        } else if (id == :geofenceBreached) {
            return "Geofence Breached";
        } else if (id == :gunshot) {
            return "Gunshot";
        } else if (id == :inContact) {
            return "In Contact";
        } else if (id == :injury) {
            return "Injury";
        } else if (id == :ringTheBell) {
            return "Ring The Bell";
        } else if (id == :uas) {
            return "UAS";
        } else if (id == :vehicle) {
            return "Vehicle";
        }
        return "Manual Alert";
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class CustomManualAlertTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var returnToMain as Boolean;

    function initialize(application as StandaloneApp, returnToMainMenu as Boolean) {
        TextPickerDelegate.initialize();
        app = application;
        returnToMain = returnToMainMenu;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (!changed) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        var error = app.addCustomManualAlert(value);
        if (error != null) {
            WatchUi.showToast(error as String, null);
            return false;
        }
        WatchUi.switchToView(buildSosMenu(app), new SosMenuDelegate(app, returnToMain), WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}
