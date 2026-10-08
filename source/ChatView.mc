import Toybox.Lang;
import Toybox.WatchUi;

function buildChatMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(WatchUi.loadResource(Rez.Strings.MenuTitleChat));
    var messages = app.getChatMessages();
    addMenuEntry(menu, "Send", null, :send);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.ChatEmpty), null, :empty);
    for (var index = messages.size() - 1; index >= 0; index--) {
        var message = messages[index] as Dictionary;
        var sender = message.get("sender");
        var text = message.get("text");
        addMenuEntry(menu, sender == null ? WatchUi.loadResource(Rez.Strings.ChatUnknownSender) : sender.toString(), text == null ? "" : text.toString(), index);
    }
    return menu;
}

class ChatMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId();
        if (index == :send) {
            WatchUi.pushView(new WatchUi.TextPicker(""), new ChatTextPickerDelegate(app), WatchUi.SLIDE_UP);
            return;
        } else if (index == :empty) {
            openMapForUserSelection();
            return;
        }
        var messages = app.getChatMessages();
        var message = messages[index] as Dictionary;
        var replyMenu = createMenu(WatchUi.loadResource(Rez.Strings.MenuTitleQuickReply));
        addMenuEntry(replyMenu, "Rgr", null, :rgr);
        addMenuEntry(replyMenu, "Neg", null, :neg);
        addMenuEntry(replyMenu, "ObjS", null, :objs);
        addMenuEntry(replyMenu, "nPos", null, :npos);
        WatchUi.pushView(replyMenu, new QuickReplyDelegate(app, message), WatchUi.SLIDE_UP);
    }

    function openMapForUserSelection() as Void {
        app.refreshPliForUserAction();
        var mapView = app.getMapView();
        mapView.setTakClient(app.getTakClient());
        WatchUi.pushView(mapView, new StandaloneMapDelegate(mapView, false, app), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class QuickReplyDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var message as Dictionary;

    function initialize(application as StandaloneApp, chatMessage as Dictionary) {
        Menu2InputDelegate.initialize();
        app = application;
        message = chatMessage;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var replyTo = message.get("uid");
        app.sendChatReply(replyTo == null ? "" : replyTo.toString(), replyText(item.getId()));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function replyText(id) as String {
        if (id == :neg) {
            return "Neg";
        } else if (id == :objs) {
            return "ObjS";
        } else if (id == :npos) {
            return "nPos";
        }
        return "Rgr";
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ChatTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        TextPickerDelegate.initialize();
        app = application;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (changed && value.length() > 0) {
            app.sendChatMessage(value);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}