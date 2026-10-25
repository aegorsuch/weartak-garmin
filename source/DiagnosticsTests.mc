import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

(:test)
class DiagnosticJournalFixture extends Diagnostics.DiagnosticJournal {
    var stored = null;
    var writes as Number = 0;
    var failWrites as Boolean = false;
    function initialize() {}
    function readStored() { return stored; }
    function writeStored(value as Dictionary) as Void {
        if (failWrites) { throw new Lang.StorageFullException("Fixture storage full"); }
        stored = {"schema" => value.get("schema"), "enabled" => value.get("enabled"),
            "entries" => (value.get("entries") as Array).slice(0, (value.get("entries") as Array).size())};
        writes++;
    }
}

(:test)
function diagnosticsDefaultOffPersistentOptInAndDisable(logger) as Boolean {
    var journal = new DiagnosticJournalFixture();
    journal.restore(100);
    journal.record(Diagnostics.START, 100);
    Test.assertEqual(journal.entries.size(), 0);
    Test.assertEqual(journal.writes, 0);
    Test.assert(journal.setEnabled(true, 100));
    journal.record(Diagnostics.START, 101);
    journal.record(Diagnostics.REPORT_WAIT, 102);
    Test.assertEqual(journal.entries.size(), 2);
    Test.assertEqual(journal.writes, 1);
    journal.persist(true, 103);
    var restarted = new DiagnosticJournalFixture();
    restarted.stored = journal.stored;
    restarted.restore(104);
    Test.assert(restarted.enabled);
    Test.assertEqual(restarted.entries.size(), 2);
    Test.assert(restarted.setEnabled(false, 105));
    restarted.record(Diagnostics.RELAY_RECEIVED, 106);
    Test.assertEqual(restarted.entries.size(), 2);
    var updated = new DiagnosticJournalFixture();
    updated.stored = restarted.stored;
    updated.restore(107);
    Test.assert(!updated.enabled);
    Test.assertEqual(updated.entries.size(), 2);
    return true;
}

(:test)
function diagnosticsBoundedRateLimitedAndAllowlisted(logger) as Boolean {
    var journal = new DiagnosticJournalFixture();
    journal.setEnabled(true, 100);
    for (var i = 0; i < 60; i++) { journal.record(Diagnostics.RELAY_RECEIVED, 100 + i); }
    Test.assertEqual(journal.entries.size(), 1);
    Test.assertEqual(journal.writes, 1);
    journal.record(Diagnostics.RELAY_RECEIVED, 160);
    Test.assertEqual(journal.entries.size(), 2);
    Test.assertEqual(journal.writes, 2);
    journal.record(999, 160);
    Test.assertEqual(journal.entries.size(), 2);
    for (var n = 1; n <= 50; n++) { journal.record(Diagnostics.REPORT_WAIT, 160 + n * 60); }
    Test.assertEqual(journal.entries.size(), 32);
    Test.assertEqual(journal.writes, 52);
    for (var e = 0; e < journal.entries.size(); e++) {
        var entry = journal.entries[e] as Array;
        Test.assertEqual(entry.size(), 2);
        Test.assert(entry[0] instanceof Number && entry[1] instanceof Number);
        Test.assert(journal.label(entry[1]) != null);
    }
    var restored = new DiagnosticJournalFixture();
    restored.stored = journal.stored;
    restored.restore(10000);
    Test.assertEqual(restored.entries.size(), 32);
    return true;
}

(:test)
function diagnosticsRejectsPrivateCorruptStateAndSurfacesStorageFailure(logger) as Boolean {
    var journal = new DiagnosticJournalFixture();
    journal.stored = {"schema" => 1, "enabled" => true,
        "entries" => [[100, Diagnostics.START], [100, "DO_NOT_RECORD"], [100, 999],
            [100, Diagnostics.RELAY_RECEIVED, "DO_NOT_RECORD"], [101, Diagnostics.STOP]]};
    journal.restore(100);
    Test.assertEqual(journal.entries.size(), 1);
    Test.assertEqual(journal.entries[0][1], Diagnostics.START);
    journal.failWrites = true;
    Test.assert(!journal.setEnabled(false, 102));
    Test.assert(!journal.enabled);
    Test.assert(journal.storageFailed);
    journal.record(Diagnostics.START, 200);
    Test.assertEqual(journal.entries.size(), 1);
    Test.assert(!journal.setEnabled(true, 201));
    Test.assert(!journal.enabled);
    journal.failWrites = false;
    Test.assert(journal.setEnabled(true, 202));
    Test.assert(!journal.storageFailed);
    journal.stored = {"schema" => 2, "enabled" => true, "entries" => []};
    journal.restore(203);
    Test.assert(!journal.enabled && journal.storageFailed);
    return true;
}

(:test)
function diagnosticsNativeMenusSortedAndHooksNeverRecordPayloads(logger) as Boolean {
    var actual = Application.getApp() as StandaloneApp;
    var menu = buildDeveloperPreferencesMenu(actual);
    Test.assert(menu.getItem(3) == null);
    for (var i = 1; i < 3; i++) {
        Test.assert(compareMenuLabels(menu.getItem(i - 1).getLabel(), menu.getItem(i).getLabel()) <= 0);
    }
    Test.assertEqual(menu.getItem(menu.findItemById(:diagnosticsToggle)).getLabel(), "Logging");
    Test.assertEqual(menu.getItem(menu.findItemById(:diagnosticEvents)).getLabel(), "Log Events");
    Test.assertEqual(menu.getItem(menu.findItemById(:diagnostics)).getLabel(), "Device Status");
    Test.assertEqual(menu.getItem(menu.findItemById(:diagnosticsToggle)).getSubLabel(),
        toolToggleLabel(Diagnostics.journal.enabled));
    Test.assertEqual(Diagnostics.buildEventsMenu(new DiagnosticJournalFixture()).getItem(0).getSubLabel(),
        "Logging is opt-in");
    var previous = Diagnostics.journal;
    var journal = new DiagnosticJournalFixture();
    Diagnostics.journal = journal;
    journal.setEnabled(true, Time.now().value());
    var relay = new TestReliableRelay();
    relay.status = :connected;
    relay.notifyStatusChanged();
    relay.handlePhoneEnvelope({"msgType" => "DO_NOT_RECORD", "payload" => {"uid" => "DO_NOT_RECORD"}});
    relay.handlePhoneEnvelope({"msgType" => 123, "payload" => {}});
    actual.onStart(null);
    actual.onStop(null);
    Diagnostics.journal = previous;
    Test.assertEqual(journal.entries.size(), 5);
    for (var e = 0; e < journal.entries.size(); e++) {
        var entry = journal.entries[e] as Array;
        Test.assertEqual(entry.size(), 2);
        Test.assert(entry[0] instanceof Number && entry[1] instanceof Number);
    }
    Test.assertEqual(relay.envelopes.size(), 0);
    var events = Diagnostics.buildEventsMenu(journal);
    Test.assert(events.getItem(4) != null && events.getItem(5) == null);
    Test.assertEqual(events.getItem(0).getLabel(), "App stopped");
    return true;
}

(:test)
class DeveloperPersistenceFixture extends StandaloneApp {
    function initialize() {}
    function loadMoppLevel() as Void {}
}

(:test)
function developerAdminUnlockPersistsWithoutChangingManagedBoundaries(logger) as Boolean {
    var keys = ["devModeEnabled", "networkPreferencesLocked", "phoneManagedSettings"];
    var saved = [];
    for (var i = 0; i < keys.size(); i++) { saved.add(Application.Storage.getValue(keys[i])); }
    Application.Storage.setValue("devModeEnabled", false);
    Application.Storage.setValue("networkPreferencesLocked", true);
    Application.Storage.setValue("phoneManagedSettings", true);
    var app = new DeveloperPersistenceFixture();
    app.loadAlertSettings();
    for (var tap = 0; tap < 7; tap++) { Test.assert(!app.registerVersionTap()); }
    Test.assert(app.registerVersionTap());
    Test.assert(app.isDevModeEnabled());
    var restarted = new DeveloperPersistenceFixture();
    restarted.loadAlertSettings();
    Test.assert(restarted.isDevModeEnabled());
    Test.assert(restarted.isNetworkPreferencesLocked() && restarted.isPhoneManagedSettings());
    for (var t = 0; t < 7; t++) { restarted.registerVersionTap(); }
    Test.assert(restarted.registerVersionTap());
    var updated = new DeveloperPersistenceFixture();
    updated.loadAlertSettings();
    Test.assert(!updated.isDevModeEnabled());
    Test.assert(updated.isNetworkPreferencesLocked() && updated.isPhoneManagedSettings());
    for (var k = 0; k < keys.size(); k++) {
        if (saved[k] == null) { Application.Storage.deleteValue(keys[k]); }
        else { Application.Storage.setValue(keys[k], saved[k]); }
    }
    return true;
}
