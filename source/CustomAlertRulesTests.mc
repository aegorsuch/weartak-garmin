import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
function customAlertRulesCountNormalizeAndRejectControls(logger) as Boolean {
    var sixty = "";
    for (var i = 0; i < 60; i++) { sixty += "A"; }
    Test.assertEqual(normalizeCustomManualAlert(sixty), sixty);
    Test.assert(normalizeCustomManualAlert(sixty + "A") == null);
    Test.assert(normalizeCustomManualAlert("") == null);
    Test.assertEqual(normalizeCustomManualAlert("  Aid   Needed\u00a0 Now  "), "Aid Needed Now");
    Test.assert(normalizeCustomManualAlert("\u0000") == null);
    var controls = ["\n", "\r", "\t", "\u0001", "\u001f", "\u007f", "\u0085", "\u009f"];
    for (var i = 0; i < controls.size(); i++) {
        Test.assert(normalizeCustomManualAlert(controls[i] + "Aid") == null);
        Test.assert(normalizeCustomManualAlert("Aid" + controls[i]) == null);
    }
    var nonBmp = "";
    for (var i = 0; i < 30; i++) { nonBmp += "🚀"; }
    Test.assertEqual(normalizeCustomManualAlert(nonBmp), nonBmp);
    Test.assert(normalizeCustomManualAlert(nonBmp + "A") == null);
    Test.assert(manualAlertLabelsEqual("Alert", "ALERT"));
    Test.assert(manualAlertLabelsEqual("I", "\u0131"));
    Test.assert(!manualAlertLabelsEqual("\u00df", "SS"));
    return true;
}

(:test)
function customAlertRulesLimitOnlyNewInputAndPreserveLegacy(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = Application.Storage.getValue("customManualAlerts");
    var old = "";
    for (var i = 0; i < 70; i++) { old += "L"; }
    var legacy = [old, "  Legacy  Spacing  ", "Line\nBreak", "Gunshot", "duplicate", "duplicate"];
    Application.Storage.setValue("customManualAlerts", legacy);
    app.loadCustomManualAlerts();
    var loaded = app.getCustomManualAlerts();
    Test.assertEqual(loaded.size(), legacy.size());
    for (var i = 0; i < legacy.size(); i++) { Test.assertEqual(loaded[i], legacy[i]); }
    Test.assert(app.addCustomManualAlert("legacy spacing") != null);
    Test.assert(app.addCustomManualAlert("gunshot") != null);
    Test.assert(app.removeCustomManualAlert(old));
    Test.assert(app.getCustomManualAlerts().indexOf("Line\nBreak") >= 0);
    Application.Storage.setValue("customManualAlerts", []);
    app.loadCustomManualAlerts();
    var alerting = app.getTakClient().isAlerting();
    var queueSize = app.getTakClient().pointReplies.replies.size();
    for (var i = 0; i < 20; i++) { Test.assert(app.addCustomManualAlert("Saved " + i) == null); }
    Test.assert(app.addCustomManualAlert("Twenty First") != null);
    app.loadCustomManualAlerts();
    Test.assertEqual(app.getCustomManualAlerts().size(), 20);
    Test.assertEqual(app.getTakClient().isAlerting(), alerting);
    Test.assertEqual(app.getTakClient().pointReplies.replies.size(), queueSize);
    Test.assert(app.removeCustomManualAlert("Saved 0"));
    Test.assert(app.addCustomManualAlert("Twenty First") == null);
    var oversized = app.getCustomManualAlerts();
    oversized.add("Legacy twenty first");
    Application.Storage.setValue("customManualAlerts", oversized);
    app.loadCustomManualAlerts();
    Test.assertEqual(app.getCustomManualAlerts().size(), 21);
    Test.assertEqual((Application.Storage.getValue("customManualAlerts") as Array).size(), 21);
    Test.assert(app.addCustomManualAlert("Still Full") != null);
    if (previous == null) { Application.Storage.deleteValue("customManualAlerts"); }
    else { Application.Storage.setValue("customManualAlerts", previous); }
    app.loadCustomManualAlerts();
    return true;
}
