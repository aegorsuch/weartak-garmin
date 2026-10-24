import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;

(:test)
class OwnPinMapFixture extends TestMapSelectionView {
    var persistedClears as Number = 0;
    function initialize() { TestMapSelectionView.initialize(); }
    function savePoints() as Void {}
    function clearPersistedDroppedWaypoints() as Void { persistedClears++; }
}

(:test)
function ownPinDeleteAndClearNeverDeleteReceivedItems(logger) as Boolean {
    var map = new OwnPinMapFixture();
    var relay = new TestReliableRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    map.setTakClient(relay);
    var position = new Position.Location({:latitude => 1.0, :longitude => 1.0, :format => :degrees});
    Test.assert(map.queuePoint(position, :friendly, "Own one", "120000Z", false));
    var first = map.pointOrder[0];
    Test.assert(map.queuePoint(position, :neutral, "Own two", "120001Z", false));
    var second = map.pointOrder[0];
    relay.status = :connected;
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true, "markerDelete" => 1});
    relay.envelopes = [];
    relay.listeners = [];
    map.updateIncomingCot("peer", 1.0, 1.0, "b-m-p-s-m", "Peer", null, null, {"isPoint" => true});
    var count = relay.pointReplies.replies.size();
    Test.assert(!map.deletePoint("cot-peer"));
    Test.assertEqual(relay.pointReplies.replies.size(), count);
    Test.assert(map.incomingDetails.hasKey("cot-peer"));
    Test.assert(map.deletePoint(first));
    Test.assert(!map.pointDetails.hasKey(first));
    Test.assert(map.clearDroppedPoints());
    Test.assert(!map.pointDetails.hasKey(second));
    Test.assert(map.incomingDetails.hasKey("cot-peer"));
    Test.assertEqual(map.persistedClears, 1);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual(relay.envelopes.size(), 2);
    for (var i = 0; i < relay.envelopes.size(); i++) {
        var event = relay.envelopes[i];
        Test.assertEqual(event.get("msgType"), "marker_delete");
        var uid = (event.get("payload") as Dictionary).get("uid") as String;
        Test.assert(uid.equals("garmin-marker-" + first) || uid.equals("garmin-marker-" + second));
    }
    map.removeIncomingPoint("cot-peer", true);
    Test.assertEqual(relay.envelopes.size(), 2);
    return true;
}

(:test)
function ownPinDeleteCapabilitySessionAndBestEffort(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    Test.assert(relay.deleteMarker("point-1"));
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => "stale", "reliableDelivery" => true, "markerDelete" => 1});
    Test.assert(relay.deleteMarker("point-1"));
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true, "markerDelete" => true});
    Test.assert(relay.deleteMarker("point-1"));
    Test.assertEqual(relay.envelopes.size(), 0);
    relay.applyRelayStatus({"relaySession" => relay.relaySession, "reliableDelivery" => true, "markerDelete" => 1});
    Test.assert(relay.deleteMarker("point-1"));
    Test.assertEqual(relay.envelopes.size(), 1);
    var payload = relay.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(payload.get("uid"), "garmin-marker-point-1");
    Test.assertEqual(payload.get("relaySession"), relay.relaySession);
    Test.assertEqual(payload.get("createdAt"), relay.epoch);
    Test.assert(payload.get("messageId") instanceof String);
    relay.listeners[0].onError();
    relay.clock += 60000;
    relay.flushPointReplies();
    Test.assertEqual(relay.envelopes.size(), 1);
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assert(relay.deleteMarker("point-2"));
    Test.assert(!(relay.envelopes[1].get("payload") as Dictionary).get("messageId").equals(payload.get("messageId")));
    relay.status = :idle;
    Test.assert(relay.deleteMarker("point-3"));
    Test.assertEqual(relay.envelopes.size(), 2);
    return true;
}

(:test)
function ownPinDeleteCancelsQueuedCreationAtomically(logger) as Boolean {
    var map = new OwnPinMapFixture();
    var relay = new TestReliableRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    map.setTakClient(relay);
    Test.assert(map.queuePoint(null, :friendly, "Pending", "120000Z", false));
    relay.storageAvailable = false;
    Test.assert(!relay.deleteMarker("point-" + (map.nextPointNumber - 1).toString()));
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    relay.storageAvailable = true;
    Test.assert(map.clearDroppedPoints());
    Test.assertEqual(relay.pointReplies.replies.size(), 0);
    Test.assertEqual(relay.envelopes.size(), 0);
    Test.assertEqual(map.persistedClears, 1);
    return true;
}

(:test)
function ownPinDeleteLegacyQueueNeverReplays(logger) as Boolean {
    var relay = new TestReliableRelay();
    relay.pointReplies.replies = [];
    Test.assert(relay.pointReplies.add({"messageId" => "old-delete", "createdAt" => relay.epoch,
        "msgType" => "marker_delete", "key" => "marker-point-1",
        "payload" => {"uid" => "garmin-marker-point-1"}}, relay.epoch));
    relay.addEvent("chat-to-keep", null);
    relay.discardLegacyQueuedMarkerDeletes();
    Test.assertEqual(relay.pointReplies.replies.size(), 1);
    Test.assertEqual(relay.pointReplies.replies[0].get("messageId"), "chat-to-keep");
    Test.assertEqual(relay.envelopes.size(), 0);
    return true;
}

(:test)
function newPinTitleTrimsTrailingWhitespaceWithoutRewritingLegacy(logger) as Boolean {
    var map = new OwnPinMapFixture();
    Test.assertEqual(map.trimNewPointTitle("  Keep leading  \t\u00a0\u3000"), "  Keep leading");
    Test.assertEqual(map.trimNewPointTitle("🚀\u2003"), "🚀");
    Test.assertEqual(map.trimNewPointTitle(" \t"), "");
    var relay = new TestReliableRelay();
    relay.status = :idle;
    relay.pointReplies.replies = [];
    map.setTakClient(relay);
    var position = new Position.Location({:latitude => 1.0, :longitude => 1.0, :format => :degrees});
    Test.assert(map.queuePoint(position, :friendly, "New pin  ", "120000Z", false));
    var id = map.pointOrder[0];
    Test.assertEqual((map.pointDetails.get(id) as Dictionary).get("title"), "New pin");
    var payload = relay.pointReplies.replies[0].get("payload") as Dictionary;
    Test.assertEqual(payload.get("title"), "New pin");
    var details = map.copiedPointDetails(id);
    details.put("title", "Legacy title  ");
    details.put("remark", "Legacy remark  \n");
    Test.assert(map.updatePoint(id, details));
    Test.assertEqual(map.getPointText(id, "title"), "Legacy title  ");
    Test.assertEqual(map.getPointText(id, "remark"), "Legacy remark  \n");
    return true;
}
