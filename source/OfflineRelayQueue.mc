import Toybox.Lang;

class OfflineRelayQueue {
    const MAX_REPLIES = 20;
    const MAX_AGE_SECONDS = 86400;
    var replies as Array<Dictionary> = [];
    var expiredOnRestore as Number = 0;
    var restoreFailed as Boolean = false;

    function initialize() {
    }

    function expire(now as Number) as Number {
        var removed = 0;
        for (var i = replies.size() - 1; i >= 0; i--) {
            var created = replies[i].get("createdAt") as Number;
            if (now - created >= MAX_AGE_SECONDS || created > now) {
                replies.remove(replies[i]);
                removed += 1;
            }
        }
        return removed;
    }

    function add(reply as Dictionary, now as Number) as Boolean {
        expire(now);
        var key = reply.get("key");
        if (key instanceof String) {
            for (var i = replies.size() - 1; i >= 0; i--) {
                var oldKey = replies[i].get("key");
                if (oldKey instanceof String && oldKey.equals(key)) { replies.remove(replies[i]); }
            }
        }
        if (replies.size() >= MAX_REPLIES) { return false; }
        replies.add(reply);
        return true;
    }

    function remove(messageId as String) as Void {
        for (var i = replies.size() - 1; i >= 0; i--) {
            if (replies[i].get("messageId").equals(messageId)) {
                replies.remove(replies[i]);
            }
        }
    }

    function restore(saved, now as Number) as Void {
        if (saved == null) { return; }
        if (!(saved instanceof Array)) { restoreFailed = true; return; }
        if (saved.size() > MAX_REPLIES) { restoreFailed = true; }
        for (var i = 0; i < saved.size() && replies.size() < MAX_REPLIES; i++) {
            var entry = saved[i];
            if (!(entry instanceof Dictionary)) { restoreFailed = true; continue; }
            var id = entry.get("messageId");
            if (!(id instanceof String) || !(entry.get("createdAt") instanceof Number)) { restoreFailed = true; continue; }
            if (id.length() == 0) { restoreFailed = true; continue; }
            if (!(entry.get("payload") instanceof Dictionary)) {
                var recipient = entry.get("recipientUid");
                if (!(recipient instanceof String) || !(entry.get("text") instanceof String)) { restoreFailed = true; continue; }
                entry = {"messageId" => id, "createdAt" => entry.get("createdAt"),
                    "msgType" => "chat", "payload" => entry};
            }
            if (!(entry.get("msgType") instanceof String)) { restoreFailed = true; continue; }
            replies.add(entry);
        }
        expiredOnRestore = expire(now);
    }
}
