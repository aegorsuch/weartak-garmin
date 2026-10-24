import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Original 24px glyphs; Menu2 owns focus and the entire row is one action.
class PluginGlyph extends WatchUi.Drawable {
    var kind as Symbol;
    function initialize(value as Symbol) {
        Drawable.initialize({:locX => 0, :locY => 0, :width => 24, :height => 24});
        kind = value;
    }
    function draw(dc as Graphics.Dc) as Void {
        if (!isVisible) { return; }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (kind == :mopp) {
            dc.drawRoundedRectangle(locX + 3, locY + 2, 18, 16, 5);
            dc.drawEllipse(locX + 5, locY + 5, 5, 5);
            dc.drawEllipse(locX + 14, locY + 5, 5, 5);
            dc.drawCircle(locX + 12, locY + 16, 5);
            dc.drawLine(locX + 9, locY + 16, locX + 15, locY + 16);
            dc.drawLine(locX + 12, locY + 13, locX + 12, locY + 19);
        } else {
            dc.drawArc(locX + 12, locY + 12, 8, Graphics.ARC_CLOCKWISE, 35, 175);
            dc.drawArc(locX + 12, locY + 12, 8, Graphics.ARC_CLOCKWISE, 215, 355);
            dc.drawLine(locX + 4, locY + 8, locX + 4, locY + 13);
            dc.drawLine(locX + 4, locY + 13, locX + 9, locY + 12);
            dc.drawLine(locX + 20, locY + 16, locX + 20, locY + 11);
            dc.drawLine(locX + 20, locY + 11, locX + 15, locY + 12);
        }
    }
}

function moppLevelLabel(level as Number?) as String {
    return level == null ? "None" : "MOPP " + level.toString();
}

class MoppMenu extends WatchUi.Menu2 {
    var app as StandaloneApp;
    var draft as Number?;
    function initialize(owner as StandaloneApp) {
        Menu2.initialize({:title => "MOPP"});
        app = owner;
        draft = app.getMoppLevel();
        populate();
    }
    function populate() as Void {
        while (getItem(0) != null) { deleteItem(0); }
        addMenuEntry(self, "PPE Status", moppLevelLabel(app.getMoppLevel()), :status);
        addMenuEntry(self, "Manual / local only", null, :localOnly);
        for (var i = -1; i <= 4; i++) {
            var level = i == -1 ? null : i;
            addMenuEntry(self, moppLevelLabel(level),
                draft == level ? app.text(Rez.Strings.TextSelected) : null, i);
        }
        addMenuEntry(self, "Save PPE Status", moppLevelLabel(draft), :saveMopp);
        addMenuEntry(self, app.text(Rez.Strings.LabelCancel), null, :cancelMopp);
    }
    function selectLevel(id as Number) as Void {
        if (id < -1 || id > 4) { return; }
        draft = id == -1 ? null : id;
        populate();
        setFocus(findItemById(id));
    }
}

class MoppDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as MoppMenu;
    function initialize(owner as StandaloneApp, choices as MoppMenu) {
        Menu2InputDelegate.initialize();
        app = owner;
        menu = choices;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) { menu.selectLevel(id); }
        else if (id == :saveMopp) {
            if (app.setMoppLevel(menu.draft)) { menu.populate(); }
        } else if (id == :cancelMopp) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
    }
}
