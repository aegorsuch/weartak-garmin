import Toybox.Lang;
import Toybox.WatchUi;

function buildSosMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextManualAlert));
    var client = app.getTakClient();
    if (client.isAlerting()) {
        addMenuEntry(menu, app.text(Rez.Strings.TextClearManualAlert) + " (" + app.alertTypeLabel(client.getAlertType()) + " " + app.text(Rez.Strings.TextActive) + ")", null, :clear);
    } else {
        addMenuEntry(menu, app.text(Rez.Strings.TextAlert911), null, :alert911);
        addMenuEntry(menu, app.text(Rez.Strings.TextGateRunner), null, :gateRunner);
        addMenuEntry(menu, app.text(Rez.Strings.TextGeofenceBreached), null, :geofenceBreached);
        addMenuEntry(menu, app.text(Rez.Strings.TextGunshot), null, :gunshot);
        addMenuEntry(menu, app.text(Rez.Strings.TextGunshotInjury), null, :gunshotInjury);
        addMenuEntry(menu, app.text(Rez.Strings.TextInContact), null, :inContact);
        addMenuEntry(menu, app.text(Rez.Strings.TextInjury), null, :injury);
        addMenuEntry(menu, app.text(Rez.Strings.TextRingTheBell), null, :ringTheBell);
        addMenuEntry(menu, app.text(Rez.Strings.TextUas), null, :uas);
        addMenuEntry(menu, app.text(Rez.Strings.TextVehicle), null, :vehicle);
        addMenuEntry(menu, app.text(Rez.Strings.TextCancel), null, :cancel);
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
        } else if (id != :cancel) {
            var client = app.getTakClient();
            app.refreshPliForUserAction();
            if (!client.activateManualAlert(alertTypeFor(id))) {
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