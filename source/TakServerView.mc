import Toybox.Lang;
import Toybox.WatchUi;

// Builds the phone relay controls. ATAK owns identity and reporting.
function buildTakServerMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleTakServer)});
    menu.addItem(new WatchUi.MenuItem(connectActionLabel(), null, :toggleConnect, null));
    return menu;
}
function connectActionLabel() as String {
    return WatchUi.loadResource(Rez.Strings.LabelConnect);
}
class TakServerMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, takMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = takMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :toggleConnect) {
            toggleConnect();
        }
    }

    function toggleConnect() as Void {
        var client = app.getTakClient();
        if (client.isConnected()) {
            client.disconnect();
        } else {
            client.connect();
        }
        client.statusCallback = method(:onClientStatusChanged);
        updateStatusItem();
    }

    function onClientStatusChanged() as Void {
        updateStatusItem();
    }

    function updateStatusItem() as Void {
        var client = app.getTakClient();
        var item = menu.getItem(menu.findItemById(:toggleConnect));
        if (item == null) {
            return;
        }
        var label = client.isConnected() ? WatchUi.loadResource(Rez.Strings.LabelDisconnect) : WatchUi.loadResource(Rez.Strings.LabelConnect);
        item.setLabel(label);
        item.setSubLabel(client.statusText());
        WatchUi.requestUpdate();
    }

    function getMenu() as WatchUi.Menu2 {
        return menu;
    }
}

