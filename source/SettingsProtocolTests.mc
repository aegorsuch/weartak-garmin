import Toybox.Communications;
import Toybox.Lang;
import Toybox.Test;

const SETTINGS_TEST_TRANSACTION = "12345678-1234-1234-1234-123456789abc";

(:test)
class TestSettingsProtocolClient extends TakClient {
    var envelopes as Array<Dictionary> = [];
    var appliedCount as Number = 0;
    var applyError as String? = null;
    var releaseCount as Number = 0;

    function initialize() {
        TakClient.initialize();
        phoneSettingsCallback = method(:applySettings);
        watchSettingsCallback = method(:settingsSnapshot);
    }

    function startRelayRuntime() as Void {}
    function loadOfflineValue(key as String) { return null; }
    function saveOfflineValue(key as String, value) as Boolean { return true; }

    function applySettings(payload) as String? {
        if (payload == null) {
            releaseCount++;
            return applyError;
        }
        appliedCount++;
        return applyError;
    }

    function settingsSnapshot() as Dictionary {
        return {
            "callsign" => "WATCH",
            "team" => "Blue",
            "role" => "Team Member",
            "reportIntSecs" => 60,
            "dynamicReporting" => false,
            "phoneManagedSettings" => false
        };
    }

    function transmitEnvelope(envelope as Dictionary,
            listener as Communications.ConnectionListener) as Void {
        envelopes.add(envelope);
    }

    function receive(type as String, payload as Dictionary) as Void {
        handlePhoneEnvelope({"msgType" => type, "payload" => payload});
    }

    function receiveRelease(requestId, session) as Void {
        handlePhoneEnvelope({
            "msgType" => "release_phone_management",
            "relaySession" => session,
            "payload" => {"requestId" => requestId}
        });
    }
}

(:test)
class TestPhoneSettingsApplication extends StandaloneApp {
    var savedSettings as Dictionary = {};
    var failOnKey as String? = null;

    function initialize() {}
    function sendPliNow() as Boolean { return false; }
    function requestPositionForAction(action as String) as Void {}

    function persistPhoneSetting(key as String, value) as String? {
        if (failOnKey != null && key.equals(failOnKey)) {
            failOnKey = null;
            return "storage full";
        }
        savedSettings.put(key, value);
        return null;
    }
}

(:test)
function settingsTransactionsCorrelateAckAndSnapshot(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.receive("set_settings", {
        "transactionId" => SETTINGS_TEST_TRANSACTION,
        "callsign" => "WATCH"
    });
    Test.assertEqual(client.appliedCount, 1);
    Test.assertEqual(client.envelopes.size(), 2);
    Test.assertEqual(client.envelopes[0].get("msgType"), "settings_set_ack");
    Test.assertEqual(
        (client.envelopes[0].get("payload") as Dictionary).get("transactionId"),
        SETTINGS_TEST_TRANSACTION);
    Test.assertEqual((client.envelopes[0].get("payload") as Dictionary).get("ok"), true);
    Test.assertEqual(client.envelopes[1].get("msgType"), "watch_settings");
    Test.assertEqual(
        (client.envelopes[1].get("payload") as Dictionary).get("transactionId"),
        SETTINGS_TEST_TRANSACTION);
    return true;
}

(:test)
function settingsTransactionsRejectMalformedIdsWithoutApplying(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.receive("set_settings", {"transactionId" => "wrong-id", "callsign" => "OTHER"});
    Test.assertEqual(client.appliedCount, 0);
    Test.assertEqual(client.envelopes.size(), 1);
    Test.assertEqual(client.envelopes[0].get("msgType"), "settings_set_ack");
    Test.assertEqual((client.envelopes[0].get("payload") as Dictionary).get("ok"), false);

    client.envelopes = [];
    client.receive("request_settings", {"transactionId" => "wrong-id"});
    Test.assertEqual(client.envelopes.size(), 0);
    return true;
}

(:test)
function settingsTransactionsPropagateApplyErrorsAndSkipSnapshots(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.applyError = "Could not save settings (storage full)";
    client.receive("set_settings", {"transactionId" => SETTINGS_TEST_TRANSACTION});
    Test.assertEqual(client.appliedCount, 1);
    Test.assertEqual(client.envelopes.size(), 1);
    Test.assertEqual(client.envelopes[0].get("msgType"), "settings_set_ack");
    var ack = client.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(ack.get("ok"), false);
    Test.assertEqual(ack.get("error"), client.applyError);
    Test.assertEqual(ack.get("transactionId"), SETTINGS_TEST_TRANSACTION);
    return true;
}

(:test)
function phoneSettingsStorageFailureRollsBackBeforeMemoryChanges(logger) as Boolean {
    var app = new TestPhoneSettingsApplication();
    app.failOnKey = "constantReportingInterval";
    var error = app.applyPhoneSettings({
        "callsign" => "NEW-WATCH",
        "team" => "Red",
        "role" => "Medic",
        "reportIntSecs" => 30,
        "phoneManagedSettings" => true
    });
    Test.assert(error instanceof String);
    Test.assertEqual(error as String,
        "Could not save settings (storage full); previous values restored.");
    Test.assertEqual(app.getCallsign(), "");
    Test.assertEqual(app.getMyTeamColor(), "Blue");
    Test.assertEqual(app.getMyRole(), "Team Member");
    Test.assertEqual(app.getReportingInterval(:constant), 60);
    Test.assert(app.isDynamicReportingEnabled());
    Test.assert(!app.isPhoneManagedSettings());
    Test.assertEqual(app.savedSettings.get("callsign"), "");
    Test.assertEqual(app.savedSettings.get("myTeamColor"), "Blue");
    Test.assertEqual(app.savedSettings.get("myRoleCategory"), "MIL");
    return true;
}

(:test)
function settingsTransactionsCorrelateRequestsAndKeepLegacyWireCompatibility(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.receive("request_settings", {"transactionId" => SETTINGS_TEST_TRANSACTION});
    Test.assertEqual(client.envelopes.size(), 1);
    var correlated = client.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(client.envelopes[0].get("msgType"), "watch_settings");
    Test.assertEqual(correlated.get("transactionId"), SETTINGS_TEST_TRANSACTION);

    client.envelopes = [];
    client.receive("request_settings", {});
    Test.assertEqual(client.envelopes.size(), 1);
    var legacy = client.envelopes[0].get("payload") as Dictionary;
    Test.assert(!legacy.hasKey("transactionId"));

    client.envelopes = [];
    client.receive("set_settings", {"callsign" => "LEGACY"});
    Test.assertEqual(client.envelopes.size(), 2);
    var legacyAck = client.envelopes[0].get("payload") as Dictionary;
    var legacySnapshot = client.envelopes[1].get("payload") as Dictionary;
    Test.assert(!legacyAck.hasKey("transactionId"));
    Test.assert(!legacySnapshot.hasKey("transactionId"));
    return true;
}

(:test)
function phoneManagementReleaseRequiresCurrentSessionAndUuid(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.relaySession = "current";
    client.status = :connected;
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "stale");
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, null);
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, 42);
    client.receiveRelease("invalid", "current");
    client.receiveRelease(null, "current");
    client.relaySession = "";
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "");
    client.relaySession = "current";
    client.status = :idle;
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    client.status = :failed;
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    Test.assertEqual(client.releaseCount, 0);
    Test.assertEqual(client.envelopes.size(), 8);
    for (var index = 0; index < client.envelopes.size(); index++) {
        Test.assertEqual(client.envelopes[index].get("msgType"), "phone_management_release_ack");
        Test.assertEqual((client.envelopes[index].get("payload") as Dictionary).get("ok"), false);
    }
    Test.assert(!(client.envelopes[3].get("payload") as Dictionary).hasKey("requestId"));
    Test.assert(!(client.envelopes[4].get("payload") as Dictionary).hasKey("requestId"));
    return true;
}

(:test)
function phoneManagementReleaseAcknowledgesDurableSuccessAndErrors(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.relaySession = "current";
    client.status = :connected;
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    Test.assertEqual(client.releaseCount, 2);
    Test.assertEqual(client.status, :connected);
    for (var index = 0; index < 2; index++) {
        var ack = client.envelopes[index].get("payload") as Dictionary;
        Test.assertEqual(ack.get("requestId"), SETTINGS_TEST_TRANSACTION);
        Test.assertEqual(ack.get("ok"), true);
    }
    client.applyError = "storage unavailable";
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    var failure = client.envelopes[2].get("payload") as Dictionary;
    Test.assertEqual(failure.get("requestId"), SETTINGS_TEST_TRANSACTION);
    Test.assertEqual(failure.get("ok"), false);
    Test.assertEqual(failure.get("error"), "storage unavailable");
    return true;
}

(:test)
function phoneManagementReleaseWithoutSettingsFailsClosed(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.relaySession = "current";
    client.status = :connected;
    client.phoneSettingsCallback = null;
    client.receiveRelease(SETTINGS_TEST_TRANSACTION, "current");
    var ack = client.envelopes[0].get("payload") as Dictionary;
    Test.assertEqual(ack.get("requestId"), SETTINGS_TEST_TRANSACTION);
    Test.assertEqual(ack.get("ok"), false);
    Test.assertEqual(ack.get("error"), "Settings are not available");
    return true;
}

(:test)
function phoneManagementLocalDisconnectAbortsOnStorageFailure(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.relaySession = "current";
    client.status = :connected;
    client.applyError = "storage unavailable";
    client.disconnect();
    Test.assertEqual(client.releaseCount, 1);
    Test.assertEqual(client.status, :connected);
    Test.assertEqual(client.relayGeneration, 0);
    client.applyError = null;
    client.disconnect();
    Test.assertEqual(client.releaseCount, 2);
    Test.assertEqual(client.status, :idle);
    Test.assertEqual(client.relayGeneration, 1);
    return true;
}

(:test)
function phoneManagementTransientLossRetainsOwnershipCallback(logger) as Boolean {
    var client = new TestSettingsProtocolClient();
    client.status = :connected;
    client.onRelayTransmitError();
    Test.assertEqual(client.releaseCount, 0);
    client.connect();
    Test.assertEqual(client.releaseCount, 0);
    client.disconnect();
    Test.assertEqual(client.releaseCount, 1);
    Test.assertEqual(client.status, :idle);
    return true;
}

(:test)
function phoneManagementReleasePreservesProvisionedSettingsAndStorageFailure(logger) as Boolean {
    var app = new TestPhoneSettingsApplication();
    Test.assert(app.applyPhoneSettings({
        "callsign" => "PROVISIONED",
        "team" => "Red",
        "role" => "Medic",
        "reportIntSecs" => 30,
        "phoneManagedSettings" => true
    }) == null);
    app.failOnKey = "phoneManagedSettings";
    Test.assert(app.applyPhoneSettings(null) instanceof String);
    Test.assert(app.isPhoneManagedSettings());
    Test.assertEqual(app.savedSettings.get("phoneManagedSettings"), true);
    Test.assert(app.applyPhoneSettings(null) == null);
    Test.assert(!app.isPhoneManagedSettings());
    Test.assertEqual(app.savedSettings.get("phoneManagedSettings"), false);
    Test.assertEqual(app.getCallsign(), "PROVISIONED");
    Test.assertEqual(app.getMyTeamColor(), "Red");
    Test.assertEqual(app.getMyRole(), "Medic");
    Test.assertEqual(app.getReportingInterval(:constant), 30);
    Test.assert(!app.isDynamicReportingEnabled());
    app.failOnKey = "phoneManagedSettings";
    Test.assert(app.applyPhoneSettings(null) == null);
    Test.assertEqual(app.failOnKey, "phoneManagedSettings");
    return true;
}
