import Toybox.Lang;
import Toybox.WatchUi;

function buildChatMenu(app as StandaloneApp) as WatchUi.Menu2 {
    return new ChatRoomsMenu(app);
}

class ChatRoomsMenu extends WatchUi.Menu2 {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.MenuTitleChat)});
        app = application;
        populate();
    }

    function onShow() as Void { app.chatRoomsMenu = self; refresh(); }
    function onHide() as Void { if (app.chatRoomsMenu == self) { app.chatRoomsMenu = null; } }

    function refresh() as Void {
        var focused = mFocus == null ? null : getItem(mFocus);
        var id = focused == null ? null : focused.getId();
        while (getItem(0) != null) { deleteItem(0); }
        populate();
        for (var i = 0; getItem(i) != null; i++) {
            if (getItem(i).getId() == id) { setFocus(i); break; }
        }
    }

    function populate() as Void {
        addItem(new WatchUi.MenuItem("All Chat Rooms", null, :all, null));
        addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ChatSelectUser), null, :selectUser, null));
        var rooms = app.chats.ordered();
        for (var i = 0; i < rooms.size(); i++) {
            var room = rooms[i];
            addItem(new WatchUi.MenuItem(room.get("title") as String, room.get("preview") as String?, room, null));
        }
    }
}

function openChatConversation(app as StandaloneApp, room as Dictionary) as Void {
    WatchUi.pushView(new ChatConversationMenu(app, room),
        new ChatConversationDelegate(app, room), WatchUi.SLIDE_LEFT);
}

function chatQuickReplyMenuLabel(value as String) as String {
    return value.length() <= 20 ? value : value.substring(0, 17) + "...";
}

function buildCustomChatQuickReplyDeletionMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Delete Saved Messages");
    var replies = app.getCustomChatQuickReplies();
    for (var index = 0; index < replies.size(); index++) {
        menu.addItem(new WatchUi.MenuItem(chatQuickReplyMenuLabel(replies[index]),
            null, replies[index], null));
    }
    return menu;
}

class ChatMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    function initialize(application as StandaloneApp) { Menu2InputDelegate.initialize(); app = application; }
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_RIGHT); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :all) {
            var room = app.chats.open("All Chat Rooms", "All Chat Rooms", true);
            if (room != null) { openChatConversation(app, room); }
        } else if (id == :selectUser) {
            app.refreshPliForUserAction();
            var map = app.getMapView();
            map.pruneIncomingEntities();
            var menu = createMenu(WatchUi.loadResource(Rez.Strings.ChatSelectUser));
            var count = 0;
            for (var i = 0; i < map.incomingIds.size(); i++) {
                var details = map.incomingDetails.get(map.incomingIds[i]) as Dictionary;
                if (details.get("isPoint") == true || details.get("isAlert") == true) { continue; }
                var uid = app.chats.stringValue(details, "uid");
                if (uid.length() == 0 || uid.equals("All Chat Rooms")) { continue; }
                addMenuEntry(menu, map.incomingPointTitle(map.incomingIds[i]), null, details);
                count++;
            }
            if (count == 0) { addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.ChatNoUsers), null, :empty); }
            WatchUi.pushView(menu, new ChatUserSelectionDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id instanceof Dictionary) {
            openChatConversation(app, id as Dictionary);
        }
    }
}

class ChatUserSelectionDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    function initialize(application as StandaloneApp) { Menu2InputDelegate.initialize(); app = application; }
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var details = item.getId();
        if (!(details instanceof Dictionary)) { return; }
        var uid = app.chats.stringValue(details, "uid");
        var title = app.chats.stringValue(details, "callSign");
        var room = app.chats.open(uid, title.length() == 0 ? uid : title, false);
        if (room != null) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            openChatConversation(app, room);
        }
    }
}

class ChatConversationMenu extends WatchUi.Menu2 {
    var app as StandaloneApp;
    var room as Dictionary;
    function initialize(application as StandaloneApp, conversation as Dictionary) {
        Menu2.initialize({:title => conversation.get("title") as String});
        app = application;
        room = conversation;
        populate();
    }
    function onShow() as Void { app.chatConversationMenu = self; refresh(); }
    function onHide() as Void { if (app.chatConversationMenu == self) { app.chatConversationMenu = null; } }
    function refresh() as Void {
        var focus = mFocus;
        while (getItem(0) != null) { deleteItem(0); }
        populate();
        if (focus != null && getItem(focus) != null) { setFocus(focus); }
    }
    function populate() as Void {
        addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ChatSend), null, :send, null));
        addItem(new WatchUi.MenuItem("Rgr", null, :rgr, null));
        addItem(new WatchUi.MenuItem("Neg", null, :neg, null));
        addItem(new WatchUi.MenuItem("ObjS", null, :objs, null));
        addItem(new WatchUi.MenuItem("nPos", null, :npos, null));
        var quickReplies = app.getCustomChatQuickReplies();
        for (var quickReply = 0; quickReply < quickReplies.size(); quickReply++) {
            addItem(new WatchUi.MenuItem(chatQuickReplyMenuLabel(quickReplies[quickReply]),
                null, quickReplies[quickReply], null));
        }
        if (quickReplies.size() > 0) {
            addItem(new WatchUi.MenuItem("Delete Saved Messages", null, :deleteCustomQuickReplies, null));
        }
        addItem(new WatchUi.MenuItem("+", null, :addCustomQuickReply, null));
        var messages = room.get("messages") as Array;
        for (var i = messages.size() - 1; i >= 0; i--) {
            var message = messages[i] as Dictionary;
            addItem(new WatchUi.MenuItem(message.get("sender") as String, message.get("text") as String, :message, null));
        }
    }
}

class ChatConversationDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var room as Dictionary;
    function initialize(application as StandaloneApp, conversation as Dictionary) {
        Menu2InputDelegate.initialize(); app = application; room = conversation;
    }
    function onBack() as Void { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :send) {
            WatchUi.pushView(new WatchUi.TextPicker(""), new ChatTextPickerDelegate(app, room), WatchUi.SLIDE_UP);
        } else if (id == :rgr || id == :neg || id == :objs || id == :npos) {
            app.sendConversationChat(room, id == :neg ? "Neg" : id == :objs ? "ObjS" : id == :npos ? "nPos" : "Rgr");
        } else if (id == :addCustomQuickReply) {
            WatchUi.showToast("Type Custom Message", null);
            WatchUi.pushView(new WatchUi.TextPicker(""),
                new ChatQuickReplyTextPickerDelegate(app, room), WatchUi.SLIDE_UP);
        } else if (id == :deleteCustomQuickReplies) {
            WatchUi.pushView(buildCustomChatQuickReplyDeletionMenu(app),
                new ChatQuickReplyDeleteDelegate(app, room), WatchUi.SLIDE_LEFT);
        } else if (id instanceof String) {
            app.sendConversationChat(room, id as String);
        }
    }
}

class ChatQuickReplyTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var room as Dictionary;

    function initialize(application as StandaloneApp, conversation as Dictionary) {
        TextPickerDelegate.initialize(); app = application; room = conversation;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (!changed) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        var error = app.addCustomChatQuickReply(value);
        if (error != null) {
            WatchUi.showToast(error as String, null);
            return false;
        }
        WatchUi.switchToView(new ChatConversationMenu(app, room),
            new ChatConversationDelegate(app, room), WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean { return true; }
}

class ChatQuickReplyDeleteDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var room as Dictionary;

    function initialize(application as StandaloneApp, conversation as Dictionary) {
        Menu2InputDelegate.initialize(); app = application; room = conversation;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof String) || !app.removeCustomChatQuickReply(id as String)) { return; }
        WatchUi.switchToView(new ChatConversationMenu(app, room),
            new ChatConversationDelegate(app, room), WatchUi.SLIDE_RIGHT);
    }
}

class ChatTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var room as Dictionary;
    function initialize(application as StandaloneApp, conversation as Dictionary) {
        TextPickerDelegate.initialize(); app = application; room = conversation;
    }
    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (changed && value.length() > 0 && !app.sendConversationChat(room, value)) { return false; }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
    function onCancel() as Boolean { return true; }
}
