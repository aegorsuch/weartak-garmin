import Toybox.Lang;
import Toybox.WatchUi;

// Builds the app's main menu: choose the map view or manage the ATAK relay.
function buildMainMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleMain)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemTakServer), null, :takServer, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemChat), null, :chat, null));
    menu.addItem(new WatchUi.MenuItem("Clear 2525D", null, :clearPoints, null));
    menu.addItem(new WatchUi.MenuItem("Environment", null, :environmentalSensors, null));
    menu.addItem(new WatchUi.MenuItem(manualAlertMenuLabel(app), null, :sos, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemMap), null, :map, null));
    menu.addItem(new WatchUi.MenuItem("Physiology", null, :physiologicalSensors, null));
    return menu;
}

function manualAlertMenuLabel(app as StandaloneApp) as String {
    var client = app.getTakClient();
    return client.isAlerting() ? "Manual Alert (" + client.getAlertType() + " Active)" : "Manual Alert";
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :map) {
            var mapView = app.getMapView();
            mapView.setTakClient(app.getTakClient());
            WatchUi.pushView(mapView, new StandaloneMapDelegate(mapView, false, app), WatchUi.SLIDE_LEFT);
        } else if (id == :chat) {
            var chatMenu = buildChatMenu(app);
            WatchUi.pushView(chatMenu, new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :environmentalSensors) {
            WatchUi.switchToView(new EnvironmentalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :physiologicalSensors) {
            WatchUi.switchToView(new PhysiologicalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var sosMenu = buildSosMenu(app);
            WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
        } else if (id == :takServer) {
            var takMenu = buildTakServerMenu();
            WatchUi.pushView(takMenu, new TakServerMenuDelegate(app, takMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :clearPoints) {
            var confirmation = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.ConfirmClearPointsTitle)});
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelClearPoints), null, :clear, null));
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel, null));
            WatchUi.pushView(confirmation, new ClearPointsDelegate(app), WatchUi.SLIDE_UP);
        }
    }
}

class ClearPointsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :clear) {
            app.getMapView().clearDroppedPoints();
            WatchUi.showToast("Old points cleared", null);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
