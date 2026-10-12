import Toybox.Lang;
import Toybox.Time;
import Toybox.System;

class ChatConversations {
    const ALL = "All Chat Rooms";
    var rooms as Array<Dictionary> = [];
    var sequence as Number = 0;

    function stringValue(data as Dictionary, key as String) as String {
        var value = data.get(key);
        return value instanceof String ? value as String : "";
    }

    function find(uid as String, group as Boolean) as Dictionary? {
        for (var i = 0; i < rooms.size(); i++) {
            if (rooms[i].get("uid").equals(uid) && rooms[i].get("isGroup") == group) { return rooms[i]; }
        }
        return null;
    }

    function open(uid as String, title as String, group as Boolean) as Dictionary? {
        if (uid.length() == 0 || title.length() == 0) { return null; }
        var room = find(uid, group);
        if (room == null) {
            room = {"uid" => uid, "title" => title, "isGroup" => group,
                "receivedAt" => 0, "sequence" => 0, "messages" => []};
            rooms.add(room);
            if (rooms.size() > 20) {
                var oldest = 0;
                for (var i = 1; i < rooms.size() - 1; i++) {
                    if (newer(rooms[oldest], rooms[i])) { oldest = i; }
                }
                rooms.remove(rooms[oldest]);
            }
        } else {
            room.put("title", title);
        }
        return room;
    }

    function receive(message as Dictionary) as Boolean {
        var senderUid = stringValue(message, "senderUid");
        var sender = stringValue(message, "senderCallsign");
        if (sender.length() == 0) { sender = stringValue(message, "sender"); }
        var text = stringValue(message, "msg");
        if (text.length() == 0) { text = stringValue(message, "text"); }
        var uid = stringValue(message, "conversationUid");
        var title = stringValue(message, "conversationTitle");
        if (title.length() == 0) { title = stringValue(message, "title"); }
        if (message.hasKey("isGroup") && !(message.get("isGroup") instanceof Boolean)) {
            System.println("Chat rejected: invalid group flag");
            return false;
        }
        if (uid.length() > 0 && !message.hasKey("isGroup")) {
            System.println("Chat rejected: missing conversation kind");
            return false;
        }
        var group = message.get("isGroup") == true;
        // iPhone envelopes retain uid as sender and identify the event with messageId.
        if (senderUid.length() == 0 && (uid.length() == 0 && !group
                || stringValue(message, "messageId").length() > 0)) {
            senderUid = stringValue(message, "uid");
        }
        if (!group) { uid = senderUid; title = sender; }
        if (uid.equals(ALL)) {
            if (!group) {
                System.println("Chat rejected: direct sender is broadcast destination");
                return false;
            }
            title = ALL;
        }
        if (uid.length() == 0 || text.length() == 0 || (group && title.length() == 0)) {
            System.println("Chat rejected: missing conversation destination or text");
            return false;
        }
        if (title.length() == 0) { title = uid; }
        var room = open(uid, title, group);
        if (room == null) { return false; }
        var messages = room.get("messages") as Array;
        var messageId = stringValue(message, "messageId");
        if (messageId.length() == 0 && message.hasKey("senderUid")) {
            messageId = stringValue(message, "uid");
        }
        for (var i = 0; i < messages.size(); i++) {
            if (messageId.length() > 0 && messages[i].get("messageId").equals(messageId)) { return true; }
        }
        var receivedAt = message.get("receivedAt");
        var timestamp = Time.now().value().toLong() * 1000;
        if (receivedAt instanceof Number || receivedAt instanceof Long) {
            if (receivedAt > 0) { timestamp = receivedAt; }
        }
        sequence += 1;
        messages.add({"messageId" => messageId, "sender" => sender, "text" => text, "sequence" => sequence});
        limitMessages();
        if (timestamp >= (room.get("receivedAt") as Number or Long)) {
            room.put("receivedAt", timestamp);
            room.put("sequence", sequence);
            room.put("preview", text);
        }
        return true;
    }

    function limitMessages() as Void {
        var count = 0;
        var oldestRoom = null;
        var oldestSequence = sequence + 1;
        for (var i = 0; i < rooms.size(); i++) {
            var messages = rooms[i].get("messages") as Array;
            count += messages.size();
            if (messages.size() > 0 && messages[0].get("sequence") < oldestSequence) {
                oldestRoom = rooms[i];
                oldestSequence = messages[0].get("sequence");
            }
        }
        if (count > 20 && oldestRoom != null) {
            var oldestMessages = oldestRoom.get("messages") as Array;
            oldestMessages.remove(oldestMessages[0]);
        }
    }

    function ordered() as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        for (var i = 0; i < rooms.size(); i++) {
            var room = rooms[i];
            if (room.get("uid").equals(ALL)) { continue; }
            var position = result.size();
            while (position > 0 && newer(room, result[position - 1])) { position--; }
            result.add(room);
            for (var j = result.size() - 1; j > position; j--) { result[j] = result[j - 1]; }
            result[position] = room;
        }
        return result;
    }

    function newer(first as Dictionary, second as Dictionary) as Boolean {
        return (first.get("receivedAt") as Number or Long) > (second.get("receivedAt") as Number or Long)
            || (first.get("receivedAt") == second.get("receivedAt")
                && (first.get("sequence") as Number) > (second.get("sequence") as Number));
    }

    function payload(room as Dictionary, text as String, callsign as String) as Dictionary? {
        var uid = stringValue(room, "uid");
        var title = stringValue(room, "title");
        if (uid.length() == 0 || title.length() == 0 || text.length() == 0
                || !(room.get("isGroup") instanceof Boolean)) { return null; }
        var group = room.get("isGroup") == true;
        if (uid.equals(ALL) && !group) { return null; }
        var result = {"roomUid" => uid, "roomTitle" => title, "isGroup" => group,
            "conversationUid" => uid, "title" => title,
            "msg" => text, "text" => text, "cs" => callsign.length() == 0 ? "Garmin" : callsign};
        if (!group) {
            result.put("recipientUid", uid);
            result.put("replyTo", uid);
        }
        return result;
    }
}
