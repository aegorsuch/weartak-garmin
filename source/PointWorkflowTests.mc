import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Time;

(:test)
class TestPointRelay extends TakClient {
    var accept as Boolean = true;
    var lastReply as String = "";
    var lastRecipient as String = "";

    function initialize() {
        TakClient.initialize();
    }

    function queuePointReply(recipientUid as String, pointUid as String, text as String) as Boolean {
        lastReply = text;
        lastRecipient = recipientUid;
        return accept;
    }
}

(:test)
function pointReplyCapacity(logger) as Boolean {
    var queue = new OfflineRelayQueue();
    for (var i = 0; i < 20; i++) {
        Test.assert(queue.add({"messageId" => i.toString(), "recipientUid" => "sender",
            "text" => "Roger", "createdAt" => 100}, 100));
    }
    Test.assert(!queue.add({"messageId" => "overflow", "createdAt" => 100}, 100));
    Test.assertEqual(queue.replies.size(), 20);
    queue.remove("10");
    Test.assertEqual(queue.replies.size(), 19);
    Test.assertEqual(queue.replies[10].get("messageId"), "11");
    return true;
}

(:test)
function pointReplyExpiry(logger) as Boolean {
    var queue = new OfflineRelayQueue();
    queue.add({"messageId" => "old", "createdAt" => 100}, 100);
    queue.add({"messageId" => "recent", "createdAt" => 101}, 101);
    Test.assertEqual(queue.expire(86499), 0);
    Test.assertEqual(queue.expire(86500), 1);
    Test.assertEqual(queue.replies[0].get("messageId"), "recent");
    Test.assertEqual(queue.expire(86501), 1);
    Test.assertEqual(queue.replies.size(), 0);
    return true;
}

(:test)
function pointReplyRestore(logger) as Boolean {
    var queue = new OfflineRelayQueue();
    queue.restore([null, {"messageId" => 42},
        {"messageId" => "stable-id", "recipientUid" => "sender",
            "replyTo" => "sender", "pointUid" => "point", "text" => "In Position",
            "createdAt" => 100},
        {"messageId" => "future", "recipientUid" => "sender", "text" => "Roger", "createdAt" => 300}], 200);
    Test.assertEqual(queue.replies.size(), 1);
    Test.assert(queue.restoreFailed);
    Test.assertEqual(queue.replies[0].get("messageId"), "stable-id");
    var payload = queue.replies[0].get("payload") as Dictionary;
    Test.assertEqual(payload.get("recipientUid"), "sender");
    Test.assertEqual(payload.get("pointUid"), "point");
    queue.remove("not-present");
    Test.assertEqual(queue.replies.size(), 1);
    return true;
}

(:test)
function offlineRelayCoalescing(logger) as Boolean {
    var queue = new OfflineRelayQueue();
    queue.add({"messageId" => "active", "createdAt" => 100, "key" => "alert",
        "msgType" => "emergency", "payload" => {"state" => "ALERT"}}, 100);
    queue.add({"messageId" => "cancel", "createdAt" => 101, "key" => "alert",
        "msgType" => "emergency", "payload" => {"state" => "CANCEL"}}, 101);
    queue.remove("active");
    Test.assertEqual(queue.replies.size(), 1);
    Test.assertEqual(queue.replies[0].get("messageId"), "cancel");
    queue.add({"messageId" => "marker", "createdAt" => 101, "key" => "point",
        "msgType" => "marker", "payload" => {"uid" => "point"}}, 101);
    queue.add({"messageId" => "delete", "createdAt" => 102, "key" => "point",
        "msgType" => "marker_delete", "payload" => {"uid" => "point"}}, 102);
    Test.assertEqual(queue.replies.size(), 2);
    var restored = new OfflineRelayQueue();
    restored.restore(queue.replies, 200);
    Test.assertEqual(restored.replies.size(), 2);
    Test.assertEqual(restored.replies[1].get("messageId"), "delete");
    return true;
}

(:test)
function offlineLocationPendingPoint(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var map = app.getMapView();
    var original = map.takClient;
    var relay = new TestPointRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    map.setTakClient(relay);
    Test.assert(map.addPoint(null, :neutral, "Pending point", "120000Z"));
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    var entry = relay.pointReplies.replies[0];
    var payload = entry.get("payload") as Dictionary;
    var id = payload.get("localId") as String;
    Test.assert(payload.get("lat") == null);
    var messageId = entry.get("messageId") as String;
    map.resolvePendingPoints(new Toybox.Position.Location({:latitude => 38.0, :longitude => -77.0, :format => :degrees}));
    Test.assert(map.pointLocations.hasKey(id));
    var resolvedLatitude = payload.get("lat") as Double;
    Test.assert(resolvedLatitude > 37.99999 && resolvedLatitude < 38.00001);
    Test.assertEqual(relay.pointReplies.replies[0].get("messageId"), messageId);
    map.deletePoint(id);
    Test.assert(!map.pointLocations.hasKey(id));
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplies.replies[0].get("msgType"), "marker_delete");
    relay.pointReplies.replies = [];
    relay.savePointReplies();
    map.takClient = original;
    return true;
}

(:test)
function offlineAlertAndChatHandoff(logger) as Boolean {
    var relay = new TestPointRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    Test.assert(relay.activateManualAlert("Gunshot"));
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.setAlerting(false);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    var cancellation = relay.pointReplies.replies[0];
    var payload = cancellation.get("payload") as Dictionary;
    Test.assertEqual(payload.get("state"), "CANCEL");
    Test.assertEqual(payload.get("alertType"), "Gunshot");
    relay.pointReplyInFlight = cancellation.get("messageId") as String;
    Test.assert(relay.activateManualAlert("Injury"));
    var newerId = relay.pointReplies.replies[0].get("messageId") as String;
    relay.onPointReplyComplete(cancellation.get("messageId") as String);
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplies.replies[0].get("messageId"), newerId);
    relay.sendChatReply("original-recipient", "Rgr");
    Test.assertEqual(relay.pointReplies.replies.size(), 2);
    var chat = relay.pointReplies.replies[1].get("payload") as Dictionary;
    Test.assertEqual(chat.get("replyTo"), "original-recipient");
    var restored = new OfflineRelayQueue();
    restored.restore(Application.Storage.getValue("pointReplies"), Time.now().value());
    Test.assertEqual(restored.replies.size(), 2);
    Test.assertEqual(restored.replies[1].get("messageId"), chat.get("messageId"));
    relay.pointReplies.replies = [];
    relay.savePointReplies();
    relay.alerting = false;
    relay.saveOfflineValue("manualAlertState", {"active" => false, "type" => "Manual Alert"});
    return true;
}

(:test)
function incomingPointClassification(logger) as Boolean {
    Test.assert(isIncomingMapPoint("a-n-G", {"how" => "h-g-i-g-o"}));
    Test.assert(!isIncomingMapPoint("a-f-G-U-C", {"how" => "h-e"}));
    Test.assert(!isIncomingMapPoint("a-f-G", {}));
    Test.assert(isIncomingMapPoint("a-f-G", {"isPoint" => true}));
    Test.assert(!isIncomingMapPoint("a-f-G", {"isPoint" => false, "how" => "h-e"}));
    Test.assert(isIncomingMapPoint("a-f-G-U-C", {"takv" => {"device" => "Map Marker"}}));
    Test.assert(!isIncomingMapPoint("b-t-f", {"how" => "h-e"}));
    Test.assertEqual(incomingPointSender({"senderUID" => "sender"}), "sender");
    Test.assertEqual(incomingPointSender({"link" => {"relation" => "p-p", "uid" => "creator"}}), "creator");
    Test.assertEqual(incomingPointSender({"link" => {"relation" => "other", "uid" => "not-sender"}}), "");
    Test.assertEqual(incomingPointRevision({"tStart" => "revision"}), "revision");
    return true;
}

(:test)
function incomingPointWorkflow(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var map = app.getMapView();
    var originalClient = map.takClient;
    var relay = new TestPointRelay();
    map.setTakClient(relay);
    var localPointCount = map.pointOrder.size();
    var metadata = {"isPoint" => true, "senderUID" => "sender", "time" => "revision-1"};
    map.updateIncomingCot("test-point", 38.0, -77.0, "a-n-G", "Checkpoint", null, null, metadata);
    Test.assert(map.pointLocations.hasKey("cot-test-point"));
    Test.assertEqual(map.pendingIncomingPoints.size(), 1);
    Test.assertEqual(map.pointOrder.size(), localPointCount);
    Test.assert(map.acknowledgeIncomingPoint("cot-test-point"));
    Test.assert(map.isBloodhoundTarget("cot-test-point"));
    Test.assertEqual(map.getBloodhoundTitle(), "Checkpoint");
    Test.assertEqual(relay.lastRecipient, "sender");
    Test.assertEqual(relay.lastReply, "Roger, bloodhounding to Checkpoint");
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
    map.updateIncomingCot("test-point", 38.0, -77.0, "a-n-G", "Checkpoint", null, null, metadata);
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
    relay.accept = false;
    Test.assert(!map.markIncomingPointInPosition("cot-test-point"));
    Test.assert(map.isBloodhoundTarget("cot-test-point"));
    Test.assert(map.pointLocations.hasKey("cot-test-point"));
    relay.accept = true;
    Test.assert(map.markIncomingPointInPosition("cot-test-point"));
    Test.assertEqual(relay.lastReply, "In Position at Checkpoint");
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.pointLocations.hasKey("cot-test-point"));
    map.updateIncomingCot("test-point", 38.0, -77.0, "a-n-G", "Checkpoint", null, null, metadata);
    Test.assert(!map.pointLocations.hasKey("cot-test-point"));
    metadata.put("time", "revision-2");
    map.updateIncomingCot("test-point", 38.0, -77.0, "a-n-G", "Checkpoint", null, null, metadata);
    Test.assertEqual(map.pendingIncomingPoints.size(), 1);
    map.incomingLastSeen.put("cot-test-point", Time.now().value() - 301);
    Test.assert(map.pruneIncomingEntities());
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
    Test.assert(!map.pointLocations.hasKey("cot-test-point"));
    map.updateIncomingCot("portal-point", 38.0, -77.0, "a-f-G-U-C", "Portal", "Red", "Team Member",
        {"takv" => {"device" => "Map Marker"}, "time" => "revision-1"});
    Test.assertEqual(map.incomingUserGroups(true).size(), 0);
    Test.assert(map.isIncomingUserVisible("cot-portal-point"));
    map.removeIncomingPoint("cot-portal-point", false);
    map.takClient = originalClient;
    return true;
}
