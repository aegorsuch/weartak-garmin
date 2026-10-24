import Toybox.Lang;
import Toybox.WatchUi;

function buildSosMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextManualAlert));
    var client = app.getTakClient();
    if (client.isAlerting()) {
        addMenuEntry(menu, app.text(Rez.Strings.TextClearManualAlert) + " (" + app.alertTypeLabel(client.getAlertType()) + " " + app.text(Rez.Strings.TextActive) + ")", null, :clear);
    }
    var delegate = new SosMenuDelegate(app, false);
    var ids = [:alert911, :gateRunner, :geofenceBreached, :gunshot, :gunshotInjury,
        :inContact, :injury, :ringTheBell, :uas, :vehicle];
    var alerts = [];
    for (var index = 0; index < ids.size(); index++) {
        alerts.add({"id" => ids[index], "label" => app.alertTypeLabel(delegate.alertTypeFor(ids[index]))});
    }
    var customAlerts = app.getCustomManualAlerts();
    for (var index = 0; index < customAlerts.size(); index++) {
        alerts.add({"id" => :customAlert, "label" => customAlerts[index]});
    }
    for (var index = 1; index < alerts.size(); index++) {
        var candidate = alerts[index] as Dictionary;
        var label = (candidate.get("label") as String).toLower();
        var insertion = index;
        while (insertion > 0
                && ((alerts[insertion - 1] as Dictionary).get("label") as String).toLower().compareTo(label) > 0) {
            alerts[insertion] = alerts[insertion - 1];
            insertion--;
        }
        alerts[insertion] = candidate;
    }
    for (var index = 0; index < alerts.size(); index++) {
        var alert = alerts[index] as Dictionary;
        addMenuEntry(menu, alert.get("label") as String, null, alert.get("id"));
    }
    if (customAlerts.size() > 0) {
        addMenuEntry(menu, "Delete Saved Alerts", null, :deleteCustomAlerts);
    }
    addMenuEntry(menu, "+", null, :addCustomAlert);
    return menu;
}

function buildCustomAlertDeletionMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Delete Saved Alerts");
    var customAlerts = app.getCustomManualAlerts();
    for (var index = 0; index < customAlerts.size(); index++) {
        addMenuEntry(menu, customAlerts[index], null, :deleteCustomAlert);
    }
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
        } else if (id == :deleteCustomAlerts) {
            var deleteMenu = buildCustomAlertDeletionMenu(app);
            WatchUi.pushView(deleteMenu, new CustomManualAlertDeleteDelegate(app, returnToMain), WatchUi.SLIDE_LEFT);
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
        } else if (id == :gunshotInjury) {
            return "Gunshot Injury";
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

class CustomManualAlertDeleteDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var returnToMain as Boolean;

    function initialize(application as StandaloneApp, returnToMainMenu as Boolean) {
        Menu2InputDelegate.initialize();
        app = application;
        returnToMain = returnToMainMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() != :deleteCustomAlert) { return; }
        if (!app.removeCustomManualAlert(item.getLabel() as String)) { return; }
        WatchUi.showToast("Deleted", null);
        WatchUi.switchToView(buildSosMenu(app), new SosMenuDelegate(app, returnToMain), WatchUi.SLIDE_RIGHT);
    }
}