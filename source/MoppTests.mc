import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
function moppNoneAndZeroAreDistinctAndPersistent(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = Application.Storage.getValue("moppLevel");
    Test.assert(app.setMoppLevel(null));
    app.loadMoppLevel();
    Test.assert(app.getMoppLevel() == null);
    Test.assertEqual(moppLevelLabel(app.getMoppLevel()), "None");
    for (var level = 0; level <= 4; level++) {
        Test.assert(app.setMoppLevel(level));
        app.loadMoppLevel();
        Test.assertEqual(app.getMoppLevel(), level);
        Test.assertEqual((Application.Storage.getValue("moppLevel") as Dictionary).get("level"), level);
        Test.assert((Application.Storage.getValue("moppLevel") as Dictionary).get("savedAt") instanceof Number);
        Test.assertEqual(moppLevelLabel(level), "MOPP " + level.toString());
    }
    Test.assert(!app.setMoppLevel(5));
    Test.assert(!app.setMoppLevel(-1));
    Test.assertEqual(app.getMoppLevel(), 4);
    var invalid = ["3", 2.5, true, -1, 5];
    for (var i = 0; i < invalid.size(); i++) {
        Application.Storage.setValue("moppLevel", invalid[i]);
        app.loadMoppLevel();
        Test.assert(app.getMoppLevel() == null);
    }
    Test.assert(app.setMoppLevel(null));
    Test.assert((Application.Storage.getValue("moppLevel") as Dictionary).get("level") == null);
    if (previous == null) { Application.Storage.deleteValue("moppLevel"); }
    else { Application.Storage.setValue("moppLevel", previous); }
    app.loadMoppLevel();
    return true;
}

(:test)
function moppDraftDoesNotCommitUntilSaved(logger) as Boolean {
    var app = Application.getApp() as StandaloneApp;
    var previous = Application.Storage.getValue("moppLevel");
    var monitoring = app.isPhysiologicalMonitoringEnabled();
    var alerts = app.isPhysiologicalAlertsEnabled();
    app.setMoppLevel(null);
    var before = app.getTakClient().selfStatus.ppe;
    var menu = new MoppMenu(app);
    var delegate = new MoppDelegate(app, menu);
    Test.assertEqual(menu.getItem(0).getLabel(), "PPE Status");
    Test.assertEqual(menu.getItem(0).getSubLabel(), "None");
    for (var id = -1; id <= 4; id++) {
        delegate.onSelect(menu.getItem(menu.findItemById(id)));
        Test.assert(app.getMoppLevel() == null);
        Test.assert(app.getTakClient().selfStatus.ppe == before);
        Test.assert((Application.Storage.getValue("moppLevel") as Dictionary).get("level") == null);
        Test.assertEqual(menu.getItem(menu.findItemById(id)).getSubLabel(), app.text(Rez.Strings.TextSelected));
    }
    Test.assert(new MoppMenu(app).draft == null);
    delegate.onSelect(menu.getItem(menu.findItemById(:saveMopp)));
    Test.assertEqual(app.getMoppLevel(), 4);
    Test.assertEqual(menu.getItem(0).getSubLabel(), "MOPP 4");
    var reopened = new MoppMenu(app);
    Test.assertEqual(reopened.draft, 4);
    Test.assertEqual(reopened.getItem(reopened.findItemById(4)).getSubLabel(), app.text(Rez.Strings.TextSelected));
    delegate.onSelect(menu.getItem(menu.findItemById(-1)));
    Test.assertEqual(app.getMoppLevel(), 4);
    delegate.onSelect(menu.getItem(menu.findItemById(:saveMopp)));
    Test.assert(app.getMoppLevel() == null);
    Test.assertEqual(app.isPhysiologicalMonitoringEnabled(), monitoring);
    Test.assertEqual(app.isPhysiologicalAlertsEnabled(), alerts);
    if (previous == null) { Application.Storage.deleteValue("moppLevel"); }
    else { Application.Storage.setValue("moppLevel", previous); }
    app.loadMoppLevel();
    return true;
}
