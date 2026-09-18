import Toybox.Lang;
import Toybox.WatchUi;

// Builds the app's main menu: choose the map view or manage the ATAK relay.
function buildMainMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleMain)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemMap), null, :map, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemSettings), null, :settings, null));
    return menu;
}

function buildSettingsMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleSettings)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuTitleDevicePreferences), null, :devicePreferences, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuTitleNetworkPreferences), null, :networkPreferences, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuTitleAlertingPreferences), null, :alertingPreferences, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuTitleToolPreferences), null, :toolPreferences, null));
    return menu;
}

function buildDevicePreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleDevicePreferences)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemLocationServices), locationServicesLabel(app), :locationServices, null));
    menu.addItem(new WatchUi.MenuItem("My User Metrics", null, :userMetrics, null));
    return menu;
}

function buildNetworkPreferencesMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleNetworkPreferences)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemTakServer), null, :takServer, null));
    return menu;
}

function buildAlertingPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleAlertingPreferences)});
    menu.addItem(new WatchUi.MenuItem("Environmental Alerts", null, :environmentalAlerts, null));
    menu.addItem(new WatchUi.MenuItem(manualAlertMenuLabel(app), null, :sos, null));
    menu.addItem(new WatchUi.MenuItem("Physiological Alerts", null, :physiologicalAlerts, null));
    return menu;
}

function buildPhysiologicalAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Physiological Alerts"});
    menu.addItem(new WatchUi.MenuItem("Physiological Alerts", physiologicalAlertsLabel(app), :physiologicalAlertsToggle, null));
    menu.addItem(new WatchUi.MenuItem("Resting Heart Rate Alerts", null, :restingHeartRateAlerts, null));
    menu.addItem(new WatchUi.MenuItem("Exertion Alerts", null, :exertionAlerts, null));
    return menu;
}

function buildRestingHeartRateMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Resting Heart Rate Alerts"});
    menu.addItem(new WatchUi.MenuItem("High Resting Heart Rate:", null, :highHeading, null));
    menu.addItem(new WatchUi.MenuItem("High HR Threshold", app.getAlertSetting(:highThreshold).toString() + " bpm", :highThreshold, null));
    menu.addItem(new WatchUi.MenuItem("Warning Length", app.getAlertSetting(:highWarning).toString() + " minutes", :highWarning, null));
    menu.addItem(new WatchUi.MenuItem("Alert Length", app.getAlertSetting(:highAlert).toString() + " minutes", :highAlert, null));
    menu.addItem(new WatchUi.MenuItem("Low Resting Heart Rate:", null, :lowHeading, null));
    menu.addItem(new WatchUi.MenuItem("Low HR Threshold", app.getAlertSetting(:lowThreshold).toString() + " bpm", :lowThreshold, null));
    menu.addItem(new WatchUi.MenuItem("Warning Length", app.getAlertSetting(:lowWarning).toString() + " minutes", :lowWarning, null));
    menu.addItem(new WatchUi.MenuItem("Alert Length", app.getAlertSetting(:lowAlert).toString() + " minutes", :lowAlert, null));
    return menu;
}

function buildExertionAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Exertion Alerts"});
    menu.addItem(new WatchUi.MenuItem("Exertion Warning Threshold", app.getAlertSetting(:exertionWarningThreshold).toString() + "%", :exertionWarningThreshold, null));
    menu.addItem(new WatchUi.MenuItem("Warning Length", app.getAlertSetting(:exertionWarningLength).toString() + " seconds", :exertionWarningLength, null));
    menu.addItem(new WatchUi.MenuItem("Exertion Alert Threshold", app.getAlertSetting(:exertionAlertThreshold).toString() + "%", :exertionAlertThreshold, null));
    menu.addItem(new WatchUi.MenuItem("Alert Length", app.getAlertSetting(:exertionAlertLength).toString() + " seconds", :exertionAlertLength, null));
    return menu;
}

function buildUserMetricsMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "My User Metrics"});
    menu.addItem(new WatchUi.MenuItem("Medical Profile (BATDOK)", null, :medicalProfile, null));
    menu.addItem(new WatchUi.MenuItem("Gait Tracking", null, :gaitTracking, null));
    return menu;
}

function buildMedicalProfileMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Medical Profile (BATDOK)"});
    menu.addItem(new WatchUi.MenuItem("Birth Year", app.getUserMetric(:birthYear).toString(), :birthYear, null));
    menu.addItem(new WatchUi.MenuItem("Height", formatHeightInFeetAndInches(app.getUserMetric(:height)), :height, null));
    menu.addItem(new WatchUi.MenuItem("Weight", app.getUserMetric(:weight).toString() + " lb", :weight, null));
    menu.addItem(new WatchUi.MenuItem("Sex", app.getUserMetric(:sex), :sex, null));
    menu.addItem(new WatchUi.MenuItem("Blood Type", app.getUserMetric(:bloodType), :bloodType, null));
    menu.addItem(new WatchUi.MenuItem("Allergies", app.allergiesLabel(), :allergies, null));
    menu.addItem(new WatchUi.MenuItem("User Type", app.getUserMetric(:userType), :userType, null));
    return menu;
}

function allergyOptions() as Array {
    return ["N/A", "Antibiotics", "Anti-Inflammatory (Ibuprofen)", "Antiseizure", "Aspirin", "Insulin", "Muscle Relaxers", "Sulfa Drugs"];
}

function buildGaitTrackingMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Gait Tracking"});
    menu.addItem(new WatchUi.MenuItem("Uniform Waist Size", app.getUserMetric(:uniformWaistSize).toString() + " in", :uniformWaistSize, null));
    menu.addItem(new WatchUi.MenuItem("Stride Length", app.getUserMetric(:strideLength).toString() + " in", :strideLength, null));
    menu.addItem(new WatchUi.MenuItem("Uniform Pants Length", app.getUserMetric(:uniformPantsLength).toString() + " in", :uniformPantsLength, null));
    menu.addItem(new WatchUi.MenuItem("Loadout Weight", app.getUserMetric(:loadoutWeight).toString() + " lbs", :loadoutWeight, null));
    return menu;
}

function buildAllergiesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Allergies"});
    var options = allergyOptions();
    for (var i = 0; i < options.size(); i++) {
        var allergy = options[i] as String;
        menu.addItem(new WatchUi.MenuItem(allergy, app.isAllergySelected(allergy) ? "Enabled" : "Disabled", allergy, null));
    }
    return menu;
}

function physiologicalAlertsLabel(app as StandaloneApp) as String {
    return app.isPhysiologicalAlertsEnabled() ? "On" : "Off";
}

function alertSettingLabel(setting as Symbol, value as Number) as String {
    if (setting == :highThreshold || setting == :lowThreshold) {
        return value.toString() + " bpm";
    } else if (setting == :exertionWarningThreshold || setting == :exertionAlertThreshold) {
        return value.toString() + "%";
    } else if (setting == :exertionWarningLength || setting == :exertionAlertLength) {
        return value.toString() + " seconds";
    }
    return value.toString() + " minutes";
}

function buildAlertValueMenu(app as StandaloneApp, setting as Symbol, parentItem as WatchUi.MenuItem) as WatchUi.Menu2 {
    var title = setting == :highThreshold || setting == :lowThreshold ? "Heart Rate Threshold" : "Alert Duration";
    var menu = new WatchUi.Menu2({:title => title});
    if (setting == :highThreshold) {
        addAlertValues(menu, 80, 200, 5);
    } else if (setting == :lowThreshold) {
        addAlertValues(menu, 25, 100, 5);
    } else if (setting == :exertionWarningThreshold || setting == :exertionAlertThreshold) {
        addAlertValues(menu, 50, 100, 5);
    } else if (setting == :exertionWarningLength || setting == :exertionAlertLength) {
        addAlertValues(menu, 30, 600, 30);
    } else {
        addAlertValues(menu, 1, 60, 1);
    }
    return menu;
}

function addAlertValues(menu as WatchUi.Menu2, first as Number, last as Number, step as Number) as Void {
    var value = first;
    while (value <= last) {
        menu.addItem(new WatchUi.MenuItem(value.toString(), null, value, null));
        value += step;
    }
}

function buildProfileValueMenu(app as StandaloneApp, setting as Symbol) as WatchUi.Menu2 {
    var title = setting == :birthYear ? "Birth Year" : setting == :height ? "Height" : setting == :weight ? "Weight" : setting == :sex ? "Sex" : setting == :bloodType ? "Blood Type" : setting == :uniformWaistSize ? "Uniform Waist Size" : setting == :strideLength ? "Stride Length" : setting == :uniformPantsLength ? "Uniform Pants Length" : setting == :loadoutWeight ? "Loadout Weight" : "User Type";
    var menu = new WatchUi.Menu2({:title => title});
    if (setting == :birthYear) {
        addProfileNumberValues(menu, 1920, 2026, 1);
    } else if (setting == :height) {
        addProfileNumberValues(menu, 48, 84, 1);
    } else if (setting == :weight) {
        addProfileNumberValues(menu, 80, 320, 5);
    } else if (setting == :sex) {
        addProfileStringValues(menu, ["Not Set", "Female", "Male"]);
    } else if (setting == :bloodType) {
        addProfileStringValues(menu, ["Unknown", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]);
    } else if (setting == :uniformWaistSize || setting == :uniformPantsLength) {
        addProfileNumberValues(menu, 24, 60, 1);
    } else if (setting == :strideLength) {
        addProfileNumberValues(menu, 20, 45, 1);
    } else if (setting == :loadoutWeight) {
        addProfileNumberValues(menu, 10, 150, 5);
    } else {
        addProfileStringValues(menu, ["N/A", "Child", "Coalition Civilian", "Coalition Military", "Non-Coalition Civilian", "Non-Coalition Military", "Opposing Force Detainee"]);
    }
    return menu;
}

function addProfileNumberValues(menu as WatchUi.Menu2, first as Number, last as Number, step as Number) as Void {
    var value = first;
    while (value <= last) {
        menu.addItem(new WatchUi.MenuItem(value.toString(), null, value, null));
        value += step;
    }
}

function addProfileStringValues(menu as WatchUi.Menu2, values as Array) as Void {
    for (var i = 0; i < values.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(values[i], null, values[i], null));
    }
}

function formatHeightInFeetAndInches(inches as Number) as String {
    var feet = inches / 12;
    var wholeFeet = feet.toNumber();
    var remainingInches = inches - (wholeFeet * 12);
    return wholeFeet.toString() + "' " + remainingInches.toString() + "\"";
}

function profileSettingLabel(setting as Symbol, value) as String {
    if (setting == :height) {
        return formatHeightInFeetAndInches(value);
    } else if (setting == :weight) {
        return value.toString() + " lb";
    } else if (setting == :uniformWaistSize || setting == :strideLength || setting == :uniformPantsLength) {
        return value.toString() + " in";
    } else if (setting == :loadoutWeight) {
        return value.toString() + " lbs";
    }
    return value.toString();
}

function buildToolPreferencesMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleToolPreferences)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemChat), null, :chat, null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MenuItemClearPoints), null, :clearPoints, null));
    return menu;
}

function locationServicesLabel(app as StandaloneApp) as String {
    return app.isLocationServicesEnabled() ? WatchUi.loadResource(Rez.Strings.LocationServicesEnabled) : WatchUi.loadResource(Rez.Strings.LocationServicesDisabled);
}

function manualAlertMenuLabel(app as StandaloneApp) as String {
    var client = app.getTakClient();
    return client.isAlerting() ? "Manual Alert (" + client.getAlertType() + " Active)" : "Manual Alert";
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :map) {
            var mapView = app.getMapView();
            mapView.setTakClient(app.getTakClient());
            WatchUi.pushView(mapView, new StandaloneMapDelegate(mapView, false, app), WatchUi.SLIDE_LEFT);
        } else if (id == :chat) {
            var chatMenu = buildChatMenu(app);
            WatchUi.pushView(chatMenu, new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :environmentalAlerts) {
            WatchUi.switchToView(new EnvironmentalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :physiologicalAlerts) {
            WatchUi.pushView(buildPhysiologicalAlertsMenu(app), new PhysiologicalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var sosMenu = buildSosMenu(app);
            WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
        } else if (id == :takServer) {
            var takMenu = buildTakServerMenu();
            WatchUi.pushView(takMenu, new TakServerMenuDelegate(app, takMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :settings) {
            WatchUi.pushView(buildSettingsMenu(), new SettingsMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :clearPoints) {
            var confirmation = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.ConfirmClearPointsTitle)});
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelClearPoints), null, :clear, null));
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel, null));
            WatchUi.pushView(confirmation, new ClearPointsDelegate(app), WatchUi.SLIDE_UP);
        }
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :devicePreferences) {
            var deviceMenu = buildDevicePreferencesMenu(app);
            WatchUi.pushView(deviceMenu, new DevicePreferencesDelegate(app, deviceMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :networkPreferences) {
            var networkMenu = buildNetworkPreferencesMenu();
            WatchUi.pushView(networkMenu, new NetworkPreferencesDelegate(app, networkMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :alertingPreferences) {
            WatchUi.pushView(buildAlertingPreferencesMenu(app), new AlertingPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :toolPreferences) {
            WatchUi.pushView(buildToolPreferencesMenu(), new ToolPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class DevicePreferencesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, preferencesMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = preferencesMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :locationServices) {
            app.setLocationServices(!app.isLocationServicesEnabled());
            item.setSubLabel(locationServicesLabel(app));
            WatchUi.requestUpdate();
        } else if (item.getId() == :userMetrics) {
            WatchUi.pushView(buildUserMetricsMenu(), new UserMetricsDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class NetworkPreferencesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, preferencesMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = preferencesMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :takServer) {
            var takMenu = buildTakServerMenu();
            WatchUi.pushView(takMenu, new TakServerMenuDelegate(app, takMenu), WatchUi.SLIDE_LEFT);
        }
    }
}

class AlertingPreferencesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :environmentalAlerts) {
            WatchUi.switchToView(new EnvironmentalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :physiologicalAlerts) {
            WatchUi.pushView(buildPhysiologicalAlertsMenu(app), new PhysiologicalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var sosMenu = buildSosMenu(app);
            WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
        }
    }
}

class PhysiologicalAlertsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :physiologicalAlertsToggle) {
            app.setPhysiologicalAlertsEnabled(!app.isPhysiologicalAlertsEnabled());
            item.setSubLabel(physiologicalAlertsLabel(app));
            WatchUi.requestUpdate();
        } else if (id == :restingHeartRateAlerts) {
            WatchUi.pushView(buildRestingHeartRateMenu(app), new RestingHeartRateDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :exertionAlerts) {
            WatchUi.pushView(buildExertionAlertsMenu(app), new ExertionAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class RestingHeartRateDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :highThreshold || id == :highWarning || id == :highAlert || id == :lowThreshold || id == :lowWarning || id == :lowAlert) {
            var setting = id as Symbol;
            WatchUi.pushView(buildAlertValueMenu(app, setting, item), new AlertValueDelegate(app, setting, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class ExertionAlertsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :exertionWarningThreshold || id == :exertionWarningLength || id == :exertionAlertThreshold || id == :exertionAlertLength) {
            var setting = id as Symbol;
            WatchUi.pushView(buildAlertValueMenu(app, setting, item), new AlertValueDelegate(app, setting, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class UserMetricsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :medicalProfile) {
            WatchUi.pushView(buildMedicalProfileMenu(app), new MedicalProfileDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :gaitTracking) {
            WatchUi.pushView(buildGaitTrackingMenu(app), new GaitTrackingDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class MedicalProfileDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :birthYear || id == :height || id == :weight || id == :sex || id == :bloodType || id == :userType) {
            var setting = id as Symbol;
            WatchUi.pushView(buildProfileValueMenu(app, setting), new ProfileValueDelegate(app, setting, item), WatchUi.SLIDE_LEFT);
        } else if (id == :allergies) {
            var allergyMenu = buildAllergiesMenu(app);
            WatchUi.pushView(allergyMenu, new AllergiesDelegate(app, allergyMenu, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class AllergiesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;
    var parentItem as WatchUi.MenuItem;

    function initialize(application as StandaloneApp, allergiesMenu as WatchUi.Menu2, profileItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = allergiesMenu;
        parentItem = profileItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var allergy = item.getId() as String;
        app.toggleAllergy(allergy);
        parentItem.setSubLabel(app.allergiesLabel());
        refreshLabels();
        WatchUi.requestUpdate();
    }

    function refreshLabels() as Void {
        var options = allergyOptions();
        for (var i = 0; i < options.size(); i++) {
            var item = menu.getItem(i) as WatchUi.MenuItem;
            item.setSubLabel(app.isAllergySelected(options[i] as String) ? "Enabled" : "Disabled");
        }
    }
}

class ProfileValueDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var setting as Symbol;
    var parentItem as WatchUi.MenuItem;

    function initialize(application as StandaloneApp, profileSetting as Symbol, item as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        app = application;
        setting = profileSetting;
        parentItem = item;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId();
        app.setUserMetric(setting, value);
        parentItem.setSubLabel(profileSettingLabel(setting, value));
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class GaitTrackingDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :uniformWaistSize || id == :strideLength || id == :uniformPantsLength || id == :loadoutWeight) {
            var setting = id as Symbol;
            WatchUi.pushView(buildProfileValueMenu(app, setting), new ProfileValueDelegate(app, setting, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class AlertValueDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var setting as Symbol;
    var parentItem as WatchUi.MenuItem;

    function initialize(application as StandaloneApp, alertSetting as Symbol, item as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        app = application;
        setting = alertSetting;
        parentItem = item;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId() as Number;
        app.setAlertSetting(setting, value);
        parentItem.setSubLabel(alertSettingLabel(setting, value));
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class ToolPreferencesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :chat) {
            WatchUi.pushView(buildChatMenu(app), new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :clearPoints) {
            var confirmation = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.ConfirmClearPointsTitle)});
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelClearPoints), null, :clear, null));
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel, null));
            WatchUi.pushView(confirmation, new ClearPointsDelegate(app), WatchUi.SLIDE_UP);
        }
    }
}

class ClearPointsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :clear) {
            app.getMapView().clearDroppedPoints();
            WatchUi.showToast("Old points cleared", null);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
