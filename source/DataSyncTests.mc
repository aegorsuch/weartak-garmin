import Toybox.Lang;
import Toybox.Test;

(:test)
class TestDataSync extends DataSyncClient {
    var sentKind as String = "";
    var sentPayload as Dictionary = {};

    function initialize(owner as TakClient) {
        DataSyncClient.initialize(owner);
    }

    function sendRequest(kind as String, payload as Dictionary, id as String) as Void {
        sentKind = kind;
        sentPayload = payload;
    }
}

(:test)
function dataSyncServerFeedFlow(logger) as Boolean {
    var relay = new TestPointRelay();
    relay.status = :connected;
    var client = new TestDataSync(relay);
    client.refresh();
    Test.assertEqual(client.sentKind, "missions_servers_request");
    var firstId = client.requestId;
    client.receive("missions_servers_response", {"requestId" => "unrelated", "dataSyncVersion" => 1, "servers" => []});
    Test.assertEqual(client.requestId, firstId);
    client.receive("missions_servers_response", {"requestId" => firstId, "dataSyncVersion" => 1,
        "servers" => [{"id" => "stable-server", "name" => "TAK", "state" => "Ready"}]});
    Test.assertEqual(client.servers.size(), 1);
    client.selectServer("stable-server");
    Test.assertEqual(client.sentKind, "missions_request");
    Test.assertEqual(client.sentPayload.get("serverID"), "stable-server");
    var feed = {"name" => "Operations", "passwordProtected" => false, "subscribed" => false, "itemCount" => 2};
    client.receive("missions_response", {"requestId" => client.requestId, "dataSyncVersion" => 1,
        "serverID" => "stable-server", "missions" => [feed]});
    Test.assert(client.error == null);
    client.subscribe(client.feeds[0]);
    Test.assertEqual(client.sentKind, "mission_update");
    Test.assertEqual(client.sentPayload.get("missionName"), "Operations");
    Test.assertEqual(client.sentPayload.get("missionSubscribe"), true);
    Test.assert(client.feeds[0].get("subscribed") == false);
    // A handoff completion must leave the request pending and the subscription unchanged.
    new DataSyncListener(client, client.requestId).onComplete();
    Test.assert(client.requestId != null);
    feed.put("subscribed", true);
    client.receive("missions_response", {"requestId" => client.requestId, "dataSyncVersion" => 1,
        "serverID" => "stable-server", "missions" => [feed]});
    Test.assert(client.feeds[0].get("subscribed") == true);
    client.subscribe(client.feeds[0]);
    Test.assertEqual(client.sentPayload.get("missionSubscribe"), false);
    relay.dataSync = client;
    relay.status = :idle;
    client.requestedAt = Toybox.System.getTimer() - 64000;
    relay.flushPointReplies();
    Test.assert(client.requestId != null);
    client.requestedAt -= 65000;
    relay.flushPointReplies();
    Test.assert(client.error != null);
    Test.assert(client.requestId == null);
    Test.assert(client.feeds[0].get("subscribed") == true);
    relay.outboxTimer.stop();
    return true;
}

(:test)
function dataSyncResponseValidation(logger) as Boolean {
    var relay = new TestPointRelay();
    relay.status = :connected;
    var client = new TestDataSync(relay);
    Test.assert(!client.validList([{"id" => "same", "name" => "TAK"}, {"id" => "same", "name" => "Other"}], true));
    Test.assert(!client.validList([{"name" => "Feed", "subscribed" => true}], false));
    Test.assert(!client.validList([null], false));
    Test.assert(!client.validList([{"name" => "Feed", "subscribed" => false,
        "passwordProtected" => false, "items" => [1, 2, 3]}], false));
    var many = [];
    for (var i = 0; i < 5; i++) { many.add({"id" => i.toString(), "name" => "TAK"}); }
    Test.assert(!client.validList(many, true));
    client.refresh();
    client.receive("missions_servers_response", {"requestId" => client.requestId, "servers" => []});
    Test.assert(client.error != null);
    Test.assertEqual(client.servers.size(), 0);
    client.selectServer("server");
    client.receive("missions_response", {"requestId" => client.requestId, "dataSyncVersion" => 1,
        "serverID" => "wrong-server", "missions" => []});
    Test.assert(client.error != null);
    Test.assertEqual(client.feeds.size(), 0);
    client.refresh();
    client.receive("missions_response", {"requestId" => client.requestId, "dataSyncVersion" => 1,
        "serverID" => "server", "missions" => []});
    Test.assert(client.error == null);
    Test.assertEqual(client.feeds.size(), 0);
    relay.outboxTimer.stop();
    return true;
}

(:test)
function dataSyncPreferencesMenus(logger) as Boolean {
    var app = Toybox.Application.getApp() as StandaloneApp;
    var tools = buildToolPreferencesMenu(app);
    Test.assertEqual(tools.getItem(1).getId(), :plugins);
    var relay = new TestPointRelay();
    var client = new TestDataSync(relay);
    client.servers = [{"id" => "server", "name" => "TAK", "state" => "Ready"}];
    var menu = new DataSyncMenu(client);
    menu.onShow();
    Test.assertEqual(menu.getItem(0).getLabel(), "TAK");
    Test.assertEqual(menu.getItem(0).getId(), 0);
    client.serverID = "server";
    client.feeds = [{"name" => "Operations", "subscribed" => false, "passwordProtected" => false}];
    client.changed();
    Test.assertEqual(menu.getItem(0).getLabel(), "Operations");
    Test.assertEqual(menu.getItem(0).getSubLabel(),
        Toybox.WatchUi.loadResource(Rez.Strings.DataSyncNotSubscribed));
    new DataSyncDelegate(client).onBack();
    Test.assert(client.serverID == null);
    Test.assertEqual(menu.getItem(0).getLabel(), "TAK");
    menu.onHide();
    Test.assert(client.callback == null);
    relay.outboxTimer.stop();
    return true;
}

(:test)
function dataSyncSubscriptionFailure(logger) as Boolean {
    var relay = new TestPointRelay();
    relay.status = :connected;
    var client = new TestDataSync(relay);
    client.serverID = "server";
    client.feeds = [{"name" => "Locked", "subscribed" => false, "passwordProtected" => true}];
    client.subscribe(client.feeds[0]);
    Test.assert(client.requestId == null);
    Test.assertEqual(client.sentKind, "");
    client.error = null;
    client.feeds[0].put("passwordProtected", false);
    client.subscribe(client.feeds[0]);
    client.receive("missions_response", {"requestId" => client.requestId, "dataSyncVersion" => 1,
        "serverID" => "server", "missions" => client.feeds});
    Test.assert(client.error != null);
    Test.assert(client.feeds[0].get("subscribed") == false);
    client.refresh();
    var oldId = client.requestId;
    client.cancel();
    client.refresh();
    new DataSyncListener(client, oldId).onError();
    Test.assert(client.requestId != null);
    client.cancel();
    relay.status = :idle;
    client.refresh();
    Test.assert(client.requestId == null);
    Test.assert(client.error != null);
    relay.outboxTimer.stop();
    return true;
}
