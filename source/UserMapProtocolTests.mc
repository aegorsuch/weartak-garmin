import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

(:test)
class TestUserMapRelay extends TakClient {
    var map;
    function initialize(target) {
        TakClient.initialize();
        map = target;
        incomingCotCallback = method(:receiveEntity);
        incomingUserLifecycleCallback = method(:receiveLifecycle);
        status = :connected;
        relaySession = "current";
    }
    function startRelayRuntime() as Void {}
    function loadOfflineValue(key as String) { return null; }
    function saveOfflineValue(key as String, value) as Boolean { return true; }
    function transmitEnvelope(envelope as Dictionary, listener as Communications.ConnectionListener) as Void {}
    function receiveEntity(uid, lat, lon, type, callsign, team, role, metadata) as Void {
        map.updateIncomingCot(uid, lat, lon, type, callsign, team, role, metadata);
    }
    function receiveLifecycle(action, payload) as Void { map.applyPhoneUserLifecycle(action, payload); }
    function receive(kind as String, payload as Dictionary, session) as Void {
        handlePhoneEnvelope({"msgType" => kind, "payload" => payload, "relaySession" => session});
    }
}

(:test)
class UserMapFixture {
    static function entity(uid as String, source as String, time as String) as Dictionary {
        return {"uid" => uid, "type" => "a-f-G", "lat" => 38.0, "lon" => -77.0,
            "isUser" => true, "isPoint" => false, "callSign" => "REMOTE", "team" => "Blue",
            "role" => "Medic", "__source" => source, "time" => time, "stale" => "2099-01-01T00:00:00Z"};
    }

    static function excludedUids() as Array {
        var watchUid = System.getDeviceSettings().uniqueIdentifier;
        return watchUid == null ? [] : ["phone", watchUid];
    }

    static function establishPhoneIdentity(relay as TestUserMapRelay) as Void {
        relay.receive("entities", {"entities" => [], "replaceUsers" => true,
            "scope" => "phone-relay-users", "excludedUids" => excludedUids()}, "current");
    }
}

(:test)
function userMapSessionFencesSnapshotsLiveAndRemovals(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    var entity = UserMapFixture.entity("remote", "phone-relay", "2026-01-01T00:00:00Z");
    relay.receive("entity", entity, "old");
    relay.receive("entity", entity, null);
    Test.assertEqual(map.incomingDetails.size(), 0);
    relay.receive("entity", entity, "current");
    Test.assertEqual(map.incomingDetails.size(), 0);
    UserMapFixture.establishPhoneIdentity(relay);
    relay.receive("entity", entity, "current");
    Test.assert(map.incomingDetails.hasKey("cot-remote"));
    relay.receive("entities", {"entities" => [], "replaceUsers" => true, "scope" => "phone-relay-users"}, "old");
    relay.receive("entity_remove", {"uid" => "remote", "scope" => "phone-relay-users"}, "old");
    Test.assert(map.incomingDetails.hasKey("cot-remote"));
    relay.receive("entity_remove", {"uid" => "remote", "scope" => "other"}, "current");
    Test.assert(map.incomingDetails.hasKey("cot-remote"));
    relay.receive("entity_remove", {"uid" => "remote", "scope" => "phone-relay-users"}, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-remote"));
    relay.receive("entity_remove", {"uid" => "remote", "scope" => "phone-relay-users"}, "current");
    return true;
}

(:test)
function userMapSnapshotReplacementPreservesOtherSourcesAndPoints(logger) as Boolean {
    var map = new TestMapSelectionView();
    var direct = UserMapFixture.entity("shared", "sitx", "2026-01-01T00:00:00Z");
    map.updateIncomingCot("shared", 37.0, -76.0, "a-f-G", "DIRECT", "Red", "Medic", direct);
    var relay = new TestUserMapRelay(map);
    UserMapFixture.establishPhoneIdentity(relay);
    relay.receive("entity", UserMapFixture.entity("shared", "phone-relay", "2026-01-02T00:00:00Z"), "current");
    relay.receive("entity", UserMapFixture.entity("gone", "phone-relay", "2026-01-02T00:00:00Z"), "current");
    map.updateIncomingCot("point", 38.0, -77.0, "a-f-G", "POINT", null, null, {"isPoint" => true});
    relay.receive("entities", {"entities" => [], "replaceUsers" => true,
        "scope" => "phone-relay-users", "excludedUids" => UserMapFixture.excludedUids()}, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-gone"));
    Test.assert(map.incomingDetails.hasKey("cot-point"));
    Test.assertEqual((map.incomingDetails.get("cot-shared") as Dictionary).get("callSign"), "DIRECT");
    Test.assertEqual((map.incomingDetails.get("cot-shared") as Dictionary).get("source"), "sitx");
    relay.receive("entity_remove", {"uid" => "point", "scope" => "phone-relay-users"}, "current");
    Test.assert(map.incomingDetails.hasKey("cot-point"));
    return true;
}

(:test)
function userMapExpiryUsesPayloadDeadlineAndKeepsDirectCopy(logger) as Boolean {
    var map = new TestMapSelectionView();
    var direct = UserMapFixture.entity("shared", "sitx", "2026-01-01T00:00:00Z");
    map.updateIncomingCot("shared", 37.0, -76.0, "a-f-G", "DIRECT", null, null, direct);
    var relay = new TestUserMapRelay(map);
    UserMapFixture.establishPhoneIdentity(relay);
    relay.receive("entity", UserMapFixture.entity("shared", "phone-relay", "2026-01-02T00:00:00Z"), "current");
    var sources = map.userSourceStates.get("shared") as Dictionary;
    (sources.get("phone-relay") as Dictionary).put("staleDeadline", "2000-01-01T00:00:00Z");
    map.pruneIncomingEntities();
    Test.assertEqual((map.incomingDetails.get("cot-shared") as Dictionary).get("callSign"), "DIRECT");
    var expired = UserMapFixture.entity("expired", "phone-relay", "2026-01-01T00:00:00Z");
    expired.put("stale", "2000-01-01T00:00:00Z");
    relay.receive("entity", expired, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-expired"));
    map.incomingLastSeen.put("cot-shared", 0);
    map.pruneIncomingEntities();
    Test.assert(map.incomingDetails.hasKey("cot-shared"));
    return true;
}

(:test)
function userMapExcludesPhoneWatchButNotDuplicateCallsign(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    var watchUid = System.getDeviceSettings().uniqueIdentifier;
    Test.assert(watchUid != null);
    relay.receive("entities", {"entities" => [
        UserMapFixture.entity("phone", "phone-relay", "2026-01-01T00:00:00Z"),
        UserMapFixture.entity(watchUid as String, "phone-relay", "2026-01-01T00:00:00Z"),
        UserMapFixture.entity("remote", "phone-relay", "2026-01-01T00:00:00Z")],
        "replaceUsers" => true, "scope" => "phone-relay-users",
        "excludedUids" => UserMapFixture.excludedUids()}, "current");
    Test.assertEqual(map.incomingDetails.size(), 1);
    Test.assert(map.incomingDetails.hasKey("cot-remote"));
    Test.assert(map.isIncomingUserVisible("cot-remote"));
    Test.assertEqual(map.incomingUserGroups(true).size(), 1);
    return true;
}

(:test)
function userMapLegacyEntitiesAndPointsRemainCompatible(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    relay.receive("entity", {"uid" => "legacy", "type" => "a-f-G-U-C", "lat" => 38.0, "lon" => -77.0}, null);
    relay.receive("entity", {"uid" => "point", "type" => "a-f-G", "lat" => 38.0, "lon" => -77.0, "isPoint" => true}, null);
    Test.assert(map.incomingDetails.hasKey("cot-legacy"));
    Test.assert(map.incomingDetails.hasKey("cot-point"));
    relay.disconnect();
    Test.assert(!map.incomingDetails.hasKey("cot-legacy"));
    Test.assert(map.incomingDetails.hasKey("cot-point"));
    return true;
}

(:test)
function userMapOldExpiryAndRemovalCannotEraseNewerUser(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    UserMapFixture.establishPhoneIdentity(relay);
    relay.receive("entity", UserMapFixture.entity("remote", "phone-relay", "2026-01-02T00:00:00Z"), "current");
    var old = UserMapFixture.entity("remote", "phone-relay", "2026-01-01T00:00:00Z");
    old.put("stale", "2000-01-01T00:00:00Z");
    relay.receive("entity", old, "current");
    relay.receive("entity_remove", {"uid" => "remote", "scope" => "phone-relay-users",
        "time" => "2026-01-01T00:00:00Z"}, "current");
    Test.assert(map.incomingDetails.hasKey("cot-remote"));
    var expired = UserMapFixture.entity("expired", "phone-relay", "2026-01-01T00:00:00Z");
    expired.remove("stale");
    expired.put("tStale", "2000-01-01T00:00:00Z");
    relay.receive("entity", expired, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-expired"));
    expired.put("tStale", "malformed");
    relay.receive("entity", expired, "current");
    Test.assert(!map.incomingDetails.hasKey("cot-expired"));
    return true;
}

(:test)
function userMapRemovingUserNeverErasesDroppedPointWithSameUid(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    UserMapFixture.establishPhoneIdentity(relay);
    relay.receive("entity", UserMapFixture.entity("shared", "phone-relay", "2026-01-01T00:00:00Z"), "current");
    map.updateIncomingCot("shared", 39.0, -78.0, "a-f-G", "POINT", null, null, {"isPoint" => true});
    relay.receive("entity_remove", {"uid" => "shared", "scope" => "phone-relay-users"}, "current");
    Test.assert(map.incomingDetails.hasKey("cot-shared"));
    Test.assertEqual((map.incomingDetails.get("cot-shared") as Dictionary).get("isPoint"), true);
    Test.assertEqual((map.incomingDetails.get("cot-shared") as Dictionary).get("callSign"), "POINT");
    return true;
}

(:test)
function userMapPhoneSourceCapacityIsBoundedAtFifty(logger) as Boolean {
    var map = new TestMapSelectionView();
    var relay = new TestUserMapRelay(map);
    UserMapFixture.establishPhoneIdentity(relay);
    for (var index = 0; index < PHONE_USER_RETAINED_LIMIT + 1; index++) {
        relay.receive("entity", UserMapFixture.entity("remote-" + index.toString(), "phone-relay",
            "2026-01-01T00:00:00Z"), "current");
    }
    Test.assertEqual(map.phoneRelayUserCount(), PHONE_USER_RETAINED_LIMIT);
    Test.assertEqual(map.userSourceStates.size(), PHONE_USER_RETAINED_LIMIT);
    Test.assert(!map.incomingDetails.hasKey("cot-remote-50"));
    return true;
}
