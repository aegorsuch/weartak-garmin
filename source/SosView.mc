import Toybox.Lang;
import Toybox.WatchUi;

function buildSosMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Manual Alert"});
    var client = app.getTakClient();
    if (client.isAlerting()) {
        menu.addItem(new WatchUi.MenuItem("Clear Manual Alert (" + client.getAlertType() + " Active)", null, :clear, null));
    } else {
        menu.addItem(new WatchUi.MenuItem("Gate Runner", null, :gateRunner, null));
        menu.addItem(new WatchUi.MenuItem("Gunshot", null, :gunshot, null));
        menu.addItem(new WatchUi.MenuItem("Gunshot Injury", null, :gunshotInjury, null));
        menu.addItem(new WatchUi.MenuItem("Injury", null, :injury, null));
        menu.addItem(new WatchUi.MenuItem("UAS", null, :uas, null));
        menu.addItem(new WatchUi.MenuItem("Vehicle", null, :vehicle, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel, null));
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
            app.getTakClient().activateManualAlert(alertTypeFor(id));
        }
        if (returnToMain) {
            WatchUi.switchToView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function alertTypeFor(id) as String {
        if (id == :gateRunner) {
            return "Gate Runner";
        } else if (id == :gunshot) {
            return "Gunshot";
        } else if (id == :gunshotInjury) {
            return "Gunshot Injury";
        } else if (id == :injury) {
            return "Injury";
        } else if (id == :uas) {
            return "UAS";
        } else {
            return "Vehicle";
        }
        return "Manual Alert";
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}