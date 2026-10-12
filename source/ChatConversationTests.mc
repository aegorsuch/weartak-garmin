import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.WatchUi;

(:test)
function chatPickerPinnedRows(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = app.chats;
    app.chats = new ChatConversations();
    app.chats.open("selected", "Selected User", false);
    app.chats.receive({"uid" => "direct-event", "senderUid" => "sender",
        "senderCallsign" => "Sender", "msg" => "Direct", "receivedAt" => 1000});
    app.chats.receive({"uid" => "group-event", "senderUid" => "sender",
        "senderCallsign" => "Sender", "msg" => "Group", "receivedAt" => 2000,
        "isGroup" => true, "conversationUid" => "team", "conversationTitle" => "Team"});
    var menu = buildChatMenu(app);
    Test.assertEqual(menu.getItem(0).getId(), :all);
    Test.assertEqual(menu.getItem(0).getLabel(), "All Chat Rooms");
    Test.assertEqual(menu.getItem(1).getId(), :selectUser);
    Test.assertEqual(menu.getItem(1).getLabel(), WatchUi.loadResource(Rez.Strings.ChatSelectUser));
    Test.assertEqual((menu.getItem(2).getId() as Dictionary).get("uid"), "team");
    Test.assertEqual((menu.getItem(3).getId() as Dictionary).get("uid"), "sender");
    Test.assertEqual((menu.getItem(4).getId() as Dictionary).get("uid"), "selected");
    var conversation = new ChatConversationMenu(app, app.chats.find("team", true) as Dictionary);
    Test.assertEqual(conversation.getItem(0).getId(), :send);
    Test.assertEqual(conversation.getItem(5).getSubLabel(), "Group");
    app.chats = previous;
    return true;
}

(:test)
function chatConversationOrdering(logger) as Boolean {
    var chats = new ChatConversations();
    var selected = chats.open("selected", "Selected User", false);
    Test.assert(selected != null);
    Test.assert(chats.receive({"uid" => "message-1", "senderUid" => "alice",
        "senderCallsign" => "Alice", "msg" => "Direct", "isGroup" => false, "receivedAt" => 1000}));
    Test.assert(chats.receive({"uid" => "message-2", "senderUid" => "bob",
        "senderCallsign" => "Bob", "msg" => "Group", "isGroup" => true,
        "conversationUid" => "team", "conversationTitle" => "Team", "receivedAt" => 2000}));
    Test.assert(chats.receive({"uid" => "message-3", "senderUid" => "bob",
        "senderCallsign" => "Bob", "msg" => "Broadcast", "isGroup" => true,
        "conversationUid" => "All Chat Rooms", "conversationTitle" => "All Chat Rooms", "receivedAt" => 3000}));
    var ordered = chats.ordered();
    Test.assertEqual(ordered.size(), 3);
    Test.assertEqual(ordered[0].get("uid"), "team");
    Test.assertEqual(ordered[1].get("uid"), "alice");
    Test.assertEqual(ordered[2].get("uid"), "selected");
    Test.assert(chats.receive({"uid" => "message-4", "senderUid" => "alice",
        "senderCallsign" => "Alice", "msg" => "Newest", "receivedAt" => 4000}));
    Test.assertEqual(chats.ordered()[0].get("uid"), "alice");
    Test.assert(chats.receive({"uid" => "message-5", "senderUid" => "bob",
        "senderCallsign" => "Bob", "msg" => "Late", "isGroup" => true,
        "conversationUid" => "team", "conversationTitle" => "Team", "receivedAt" => 500}));
    Test.assertEqual(chats.ordered()[0].get("uid"), "alice");
    Test.assertEqual(chats.ordered()[1].get("preview"), "Group");
    return true;
}

(:test)
function chatDestinationRouting(logger) as Boolean {
    var chats = new ChatConversations();
    Test.assert(chats.receive({"uid" => "event-id", "senderUid" => "sender",
        "senderCallsign" => "Sender", "msg" => "Hello", "receivedAt" => 1000}));
    var room = chats.find("sender", false);
    Test.assert(room != null);
    var direct = chats.payload(room as Dictionary, "Rgr", "Watch") as Dictionary;
    Test.assertEqual(direct.get("roomUid"), "sender");
    Test.assertEqual(direct.get("replyTo"), "sender");
    Test.assertEqual(direct.get("recipientUid"), "sender");
    Test.assert(direct.get("isGroup") == false);
    var group = chats.open("team", "Team", true) as Dictionary;
    var payload = chats.payload(group, "Neg", "") as Dictionary;
    Test.assertEqual(payload.get("roomUid"), "team");
    Test.assertEqual(payload.get("roomTitle"), "Team");
    Test.assert(payload.get("isGroup") == true);
    Test.assert(!payload.hasKey("replyTo"));
    Test.assert(!payload.hasKey("recipientUid"));
    Test.assertEqual(payload.get("msg"), "Neg");
    Test.assertEqual(payload.get("text"), "Neg");
    var broadcast = chats.payload(chats.open("All Chat Rooms", "All Chat Rooms", true) as Dictionary, "All", "Watch") as Dictionary;
    Test.assertEqual(broadcast.get("roomUid"), "All Chat Rooms");
    Test.assert(chats.payload({"uid" => "All Chat Rooms", "title" => "Bad", "isGroup" => false}, "No", "") == null);
    Test.assert(chats.payload({"uid" => "", "title" => "Bad", "isGroup" => false}, "No", "") == null);
    Test.assert(chats.payload(group, "", "") == null);
    Test.assert(!chats.receive({"uid" => "event", "senderUid" => "All Chat Rooms",
        "senderCallsign" => "Bad", "msg" => "Not a broadcast", "isGroup" => false}));
    Test.assert(!chats.receive({"uid" => "event", "senderUid" => "sender", "msg" => "No group ID", "isGroup" => true}));
    Test.assert(!chats.receive({"uid" => "event", "senderUid" => "sender", "msg" => "Bad flag",
        "conversationUid" => "team", "conversationTitle" => "Team", "isGroup" => "true"}));
    Test.assert(!chats.receive({"uid" => "event", "senderUid" => "sender", "msg" => "Missing flag",
        "conversationUid" => "team", "conversationTitle" => "Team"}));
    Test.assert(chats.receive({"uid" => "legacy-sender", "sender" => "Legacy", "text" => "Hi"}));
    Test.assert(chats.find("legacy-sender", false) != null);
    return true;
}

(:test)
function chatDuplicateAndLimits(logger) as Boolean {
    var chats = new ChatConversations();
    var message = {"uid" => "event", "senderUid" => "sender",
        "senderCallsign" => "Sender", "msg" => "Hi", "receivedAt" => 1000};
    Test.assert(chats.receive(message));
    Test.assert(chats.receive(message));
    Test.assertEqual((chats.find("sender", false).get("messages") as Array).size(), 1);
    for (var i = 0; i < 25; i++) {
        Test.assert(chats.receive({"uid" => i.toString(), "senderUid" => "sender",
            "senderCallsign" => "Sender", "msg" => i.toString(), "receivedAt" => 1001 + i}));
    }
    var messages = chats.find("sender", false).get("messages") as Array;
    Test.assertEqual(messages.size(), 20);
    Test.assertEqual(messages[0].get("text"), "5");
    for (var j = 0; j < 25; j++) { chats.open(j.toString(), j.toString(), false); }
    Test.assertEqual(chats.rooms.size(), 20);
    return true;
}

(:test)
function chatCompanionCapabilityAndQueue(logger) as Boolean {
    var relay = new TestReliableRelay();
    var chats = new ChatConversations();
    var group = chats.payload(chats.open("team", "Team", true) as Dictionary, "Rgr", "Watch") as Dictionary;
    Test.assert(!relay.canRouteChat("chat", group));
    relay.applyRelayStatus({"relaySession" => "old", "reliableDelivery" => true, "chatGroups" => true});
    Test.assert(!relay.chatGroupsSupported);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true, "chatGroups" => true});
    Test.assert(relay.canRouteChat("chat", group));
    Test.assert(relay.queueRelay("chat", group, null));
    var queued = relay.pointReplies.replies[1].get("payload") as Dictionary;
    Test.assertEqual(queued.get("roomUid"), "team");
    Test.assert(queued.get("isGroup") == true);
    relay.chatGroupsSupported = false;
    relay.result("test-event", true);
    var before = relay.envelopes.size();
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), before);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assert(relay.canRouteChat("chat", chats.payload(chats.open("All Chat Rooms", "All Chat Rooms", true) as Dictionary, "All", "") as Dictionary));
    return true;
}
