import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Time;

(:test)
class TestMapPositionInfo {
    var position;
    var accuracy = Toybox.Position.QUALITY_USABLE;

    function initialize(location) {
        position = location;
    }
}

(:test)
class TestEntitySyncRelay extends TestPointRelay {
    var sentKind as String = "";
    var sentPayload as Dictionary = {};

    function initialize() {
        TestPointRelay.initialize();
        pointReplies.replies = [];
    }

    function transmit(kind as String, payload as Dictionary) as Void {
        sentKind = kind;
        sentPayload = payload;
    }
}

(:test)
function nearestMapItemThreshold(logger) as Boolean {
    var nearest = new NearestMapItems();
    Test.assertEqual(nearest.pointIds.size(), 0);
    for (var i = 998; i >= 0; i--) { nearest.add(i.toString(), i); }
    var ids = nearest.pointIds;
    Test.assertEqual(ids.size(), 99);
    for (var i = 0; i < 99; i++) { Test.assert(ids.indexOf(i.toString()) != -1); }
    nearest.add("far", 2000);
    Test.assertEqual(nearest.pointIds.size(), 99);
    Test.assert(nearest.pointIds.indexOf("far") == -1);
    nearest.add("closer", -1);
    Test.assert(nearest.pointIds.indexOf("closer") != -1);
    Test.assert(nearest.pointIds.indexOf("98") == -1);
    var tied = new NearestMapItems();
    for (var i = 0; i < 999; i++) { tied.add(i.toString(), 0); }
    Test.assertEqual(tied.pointIds.size(), 99);
    var relay = new TestEntitySyncRelay();
    relay.status = :connecting;
    relay.onRelayTransmitComplete();
    Test.assertEqual(relay.sentKind, "entity_sync_request");
    Test.assertEqual(relay.sentPayload.get("limit"), 999);
    Test.assertEqual(relay.sentPayload.get("protocolVersion"), 1);
    return true;
}

(:test)
function coordinateFormatting(logger) as Boolean {
    var map = new StandaloneMapView();
    Test.assertEqual(map.mgrsFromLatLon(38.8977, -77.0365), "18S UJ 23394 07395");
    Test.assertEqual(map.mgrsFromLatLon(51.5074, -0.1278), "30U XC 99316 10164");
    var sydney = map.mgrsFromLatLon(-33.8688, 151.2093);
    Test.assertEqual(sydney, "56H LH 34370 50948");
    Test.assertEqual(map.mgrsFromLatLon(60.0, 6.0), "32V LM 32705 55206");
    Test.assertEqual(map.mgrsFromLatLon(78.0, 15.0), "33X WG 00000 58370");
    Test.assertEqual(map.mgrsFromLatLon(85.0, 0.0), "MGRS unavailable");
    Test.assertEqual(teamColorValue("Blue"), Graphics.createColor(255, 0, 0, 255));
    Test.assertEqual(teamColorValue("dark blue"), Graphics.createColor(255, 0, 0, 139));
    return true;
}

(:test)
function retainedMapEntitiesAndNearestDrawing(logger) as Boolean {
    var map = new StandaloneMapView();
    map.setApplication(Application.getApp() as StandaloneApp);
    map.entityPruneTimer.stop();
    map.markers = {};
    map.pointLocations = {};
    map.pointDetails = {};
    map.pointOrder = [];
    map.hiddenMapTeams = [];
    map.hiddenMapRoles = [];
    map.currentPosition = new Toybox.Position.Location({
        :latitude => 0.0, :longitude => 0.0, :format => :degrees});
    for (var i = 0; i < 999; i++) {
        map.updateIncomingCot("nearest-" + i, i * 0.00001, 0.0, "a-f-G-U-C",
            "User", i < 100 ? "Red" : "Blue", null, {});
    }
    Test.assertEqual(map.incomingIds.size(), 999);
    Test.assertEqual(map.pointLocations.size(), 999);
    Test.assertEqual(map.markers.size(), 0);
    Test.assertEqual(map.markerArray().size(), 99);
    Test.assertEqual(map.markers.size(), 0);
    for (var i = 0; i < 99; i++) {
        Test.assert(map.drawnPointIds.indexOf("cot-nearest-" + i) != -1);
    }
    Test.assert(map.drawnPointIds.indexOf("cot-nearest-99") == -1);
    map.hiddenMapTeams = ["red"];
    Test.assertEqual(map.markerArray().size(), 99);
    for (var i = 100; i < 199; i++) {
        Test.assert(map.drawnPointIds.indexOf("cot-nearest-" + i) != -1);
    }
    var groups = map.incomingUserGroups(true);
    for (var i = 0; i < groups.size(); i++) {
        Test.assertEqual(groups[i].get("count"), groups[i].get("key").equals("red") ? 100 : 899);
    }
    Test.assertEqual(map.pointLocations.size(), 999);
    map.hiddenMapTeams = [];
    var moved = new Toybox.Position.Location({
        :latitude => 0.00998, :longitude => 0.0, :format => :degrees});
    map.markersDirty = false;
    map.updatePosition(new TestMapPositionInfo(moved));
    Test.assert(map.markersDirty);
    Test.assertEqual(map.markerArray().size(), 99);
    for (var i = 900; i < 999; i++) {
        Test.assert(map.drawnPointIds.indexOf("cot-nearest-" + i) != -1);
    }
    map.updateIncomingCot("nearest-0", 0.02, 0.0, "a-f-G-U-C", "Updated", "Red", null, {});
    Test.assertEqual(map.incomingIds.size(), 999);
    map.bloodhoundPointId = "cot-nearest-0";
    map.updateIncomingCot("overflow", 0.0, 0.0, "a-f-G-U-C", null, null, null, {});
    Test.assertEqual(map.incomingIds.size(), 999);
    Test.assert(!map.pointLocations.hasKey("cot-nearest-0"));
    Test.assert(map.pointLocations.hasKey("cot-overflow"));
    Test.assert(!map.isBloodhoundActive());
    map.incomingLastSeen.put("cot-overflow", Time.now().value() - 301);
    Test.assert(map.pruneIncomingEntities());
    Test.assertEqual(map.incomingIds.size(), 998);
    map.setMapMarker(map.markerArray());
    map.clear();
    map.incomingIds = [];
    map.incomingDetails = {};
    map.incomingLastSeen = {};
    map.pointLocations = {};
    map.markers = {};
    map.drawnPointIds = [];
    Test.assertEqual(map.markerArray().size(), 0);
    map.currentPosition = null;
    map.centerOn(null);
    map.updateIncomingCot("far", 20.0, 0.0, "a-n-G", null, null, null, {});
    map.updateIncomingCot("center", 0.0, 0.0, "a-n-G", null, null, null, {});
    Test.assertEqual(map.markerArray().size(), 2);
    Test.assertEqual(map.pointAtScreen(map.screenWidth / 2, map.screenHeight / 2), "cot-center");
    // With 99 nearer items, the remote point at map center must not remain tappable.
    map.currentPosition = new Toybox.Position.Location({
        :latitude => 20.0, :longitude => 0.0, :format => :degrees});
    for (var i = 0; i < 99; i++) {
        map.updateIncomingCot("near-watch-" + i, 20.0 + i * 0.00001, 0.0, "a-n-G", null, null, null, {});
    }
    map.pointLocations.put("local-test", map.currentPosition);
    map.markers.put("local-test", new Toybox.WatchUi.MapMarker(map.currentPosition));
    Test.assertEqual(map.markerArray().size(), 99);
    Test.assert(map.drawnPointIds.indexOf("local-test") != -1);
    Test.assert(map.drawnPointIds.indexOf("cot-center") == -1);
    Test.assert(map.pointAtScreen(map.screenWidth / 2, map.screenHeight / 2) == null);
    return true;
}

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
function bloodhoundIncomingPointsMenu(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var map = app.getMapView();
    var mainMenu = buildMainMenu(app);
    Test.assertEqual(mainMenu.getItem(2).getLabel(), app.text(:bloodhound));
    Test.assertEqual(mainMenu.getItem(2).getId(), :incomingPoints);
    map.currentPosition = new Toybox.Position.Location({:latitude => 38.0, :longitude => -77.0, :format => :degrees});
    map.updateIncomingCot("menu-point", 38.0, -77.0, "a-n-G", "Checkpoint", null, null,
        {"isPoint" => true, "time" => "revision-1"});
    Test.assertEqual(map.incomingPointDetailLabel("cot-menu-point"), app.text(:neutralPoint) + " · 0 m");
    var menu = buildIncomingPointsMenu(app);
    Test.assertEqual(menu.getItem(0).getId(), :removeAll);
    Test.assertEqual(menu.getItem(0).getLabel(), Toybox.WatchUi.loadResource(Rez.Strings.IncomingPointsRemoveAll));
    Test.assertEqual(menu.getItem(1).getId(), "cot-menu-point");
    Test.assertEqual(menu.getItem(1).getLabel(), "Checkpoint");
    Test.assert(menu.getItem(2) == null);
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
    map.removeIncomingPoint("cot-menu-point", false);
    menu.onShow();
    Test.assertEqual(menu.getItem(0).getId(), :removeAll);
    Test.assertEqual(menu.getItem(1).getId(), :empty);
    Test.assert(menu.getItem(2) == null);
    return true;
}

(:test)
function bulkIncomingPointRemoval(logger) as Boolean {
    var map = new StandaloneMapView();
    map.setApplication(Application.getApp() as StandaloneApp);
    map.entityPruneTimer.stop();
    var localPointCount = map.pointOrder.size();
    map.updateIncomingCot("bulk-first", 38.0, -77.0, "a-n-G", "First", null, null,
        {"isPoint" => true, "time" => "revision-1"});
    map.updateIncomingCot("bulk-user", 38.0, -77.0, "a-f-G-U-C", "User", null, null, {});
    map.updateIncomingCot("bulk-last", 38.0, -77.0, "a-f-G", "Last", null, null,
        {"isPoint" => true, "time" => "revision-1"});
    map.bloodhoundPointId = "cot-bulk-first";
    map.bloodhoundProximityNotified = true;
    map.markersDirty = false;
    map.removeAllIncomingPoints();
    Test.assertEqual(map.incomingIds.size(), 1);
    Test.assertEqual(map.incomingIds[0], "cot-bulk-user");
    Test.assert(map.pointLocations.hasKey("cot-bulk-user"));
    Test.assert(!map.pointLocations.hasKey("cot-bulk-first"));
    Test.assert(!map.pointLocations.hasKey("cot-bulk-last"));
    Test.assert(!map.incomingDetails.hasKey("cot-bulk-first"));
    Test.assert(!map.incomingLastSeen.hasKey("cot-bulk-last"));
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
    Test.assertEqual(map.pointOrder.size(), localPointCount);
    Test.assert(!map.isBloodhoundActive());
    Test.assert(!map.bloodhoundProximityNotified);
    Test.assert(map.markersDirty);
    Test.assertEqual(map.dismissedIncomingPoints.size(), 2);
    map.updateIncomingCot("bulk-first", 38.0, -77.0, "a-n-G", "First", null, null,
        {"isPoint" => true, "time" => "revision-1"});
    Test.assert(!map.pointLocations.hasKey("cot-bulk-first"));
    map.updateIncomingCot("bulk-first", 38.0, -77.0, "a-n-G", "First", null, null,
        {"isPoint" => true, "time" => "revision-2"});
    Test.assert(map.pointLocations.hasKey("cot-bulk-first"));
    map.removeAllIncomingPoints();
    map.removeAllIncomingPoints();
    Test.assertEqual(map.incomingIds.size(), 1);
    Test.assertEqual(map.pendingIncomingPoints.size(), 0);
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
