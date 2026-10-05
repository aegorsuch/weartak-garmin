import Toybox.Lang;
import Toybox.WatchUi;

function openDataSync(app as StandaloneApp) as Void {
    var client = app.getTakClient().dataSync;
    client.cancel();
    client.serverID = null;
    client.feeds = [];
    var delegate = new DataSyncDelegate(client);
    WatchUi.pushView(new DataSyncMenu(client), delegate, WatchUi.SLIDE_LEFT);
    client.refresh();
}

class DataSyncMenu extends WatchUi.Menu2 {
    var client as DataSyncClient;

    function initialize(owner as DataSyncClient) {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.DataSyncTitle)});
        client = owner;
    }

    function onShow() as Void {
        client.callback = method(:populate);
        populate();
    }

    function onHide() as Void {
        client.callback = null;
    }

    function populate() as Void {
        while (getItem(0) != null) { deleteItem(0); }
        setTitle(WatchUi.loadResource(client.serverID == null ? Rez.Strings.DataSyncTitle : Rez.Strings.DataSyncFeeds));
        var rows = client.serverID == null ? client.servers : client.feeds;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            var detail = row.get("state");
            if (client.serverID != null) {
                detail = WatchUi.loadResource(row.get("subscribed") == true
                    ? Rez.Strings.DataSyncSubscribed : row.get("passwordProtected") == true
                    ? Rez.Strings.DataSyncPassword : Rez.Strings.DataSyncNotSubscribed);
                if (row.get("itemCount") != null) { detail += " | " + row.get("itemCount").toString(); }
            }
            if (row.get("error") != null) { detail = row.get("error"); }
            addItem(new WatchUi.MenuItem(row.get("name") as String, detail as String?, i, null));
        }
        if (client.requestId != null || client.error != null || rows.size() == 0) {
            var text = client.error != null ? client.error : WatchUi.loadResource(client.requestId != null
                ? Rez.Strings.DataSyncLoading : Rez.Strings.DataSyncEmpty);
            addItem(new WatchUi.MenuItem(text, null, :status, null));
        }
        addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.DataSyncRefresh), null, :refresh, null));
    }
}

class DataSyncDelegate extends WatchUi.Menu2InputDelegate {
    var client as DataSyncClient;

    function initialize(owner as DataSyncClient) {
        Menu2InputDelegate.initialize();
        client = owner;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (client.requestId != null) { return; }
        var id = item.getId();
        if (id == :refresh) { client.refresh(); }
        else if (id instanceof Number) {
            var rows = client.serverID == null ? client.servers : client.feeds;
            if (id < 0 || id >= rows.size()) { return; }
            if (client.serverID == null) { client.selectServer(rows[id].get("id") as String); }
            else { client.subscribe(rows[id]); }
        }
    }

    function onBack() as Void {
        client.cancel();
        if (client.serverID != null) {
            client.serverID = null;
            client.changed();
        } else {
            client.callback = null;
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
