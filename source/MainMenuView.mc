import Toybox.Lang;
import Toybox.WatchUi;

function addMenuEntry(menu as WatchUi.Menu2, label as String, subLabel, id as Symbol) as Void {
    menu.addItem(new WatchUi.MenuItem(label, subLabel, id, null));
}

function addMenuEntries(menu as WatchUi.Menu2, entries as Array) as Void {
    for (var i = 0; i < entries.size(); i++) {
        var entry = entries[i] as Dictionary;
        addMenuEntry(menu, entry[:label] as String, entry[:subLabel], entry[:id] as Symbol);
    }
}

function addLabelValueEntry(menu as WatchUi.Menu2, label as String, value as String, id as Symbol) as Void {
    addMenuEntry(menu, label, value, id);
}

function addToggleEntry(menu as WatchUi.Menu2, label as String, enabled as Boolean, id as Symbol) as Void {
    addMenuEntry(menu, label, toolToggleLabel(enabled), id);
}

// Builds the app's main menu: choose the map view or manage the ATAK relay.
function buildMainMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.MenuTitleMain)});
    var entries = [
        {:label => app.text(:chat), :subLabel => null, :id => :chat},
        {:label => app.text(:clearPointsMain), :subLabel => null, :id => :clearPoints},
        {:label => app.text(:dropPoint), :subLabel => null, :id => :dropPoint},
        {:label => app.text(:environment), :subLabel => null, :id => :environment},
        {:label => app.text(:exit), :subLabel => null, :id => :exit},
        {:label => manualAlertMenuLabel(app), :subLabel => null, :id => :sos},
        {:label => app.text(:map), :subLabel => null, :id => :map},
        {:label => app.text(:physiology), :subLabel => null, :id => :physiology},
        {:label => app.text(:settings), :subLabel => null, :id => :settings}
    ];
    if (!app.isChatEnabled()) {
        entries = entries.slice(1, entries.size());
    }
    addMenuEntries(menu, entries);
    return menu;
}

function buildSettingsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:settings)});
    var entries = [
        {:label => app.text(:devicePreferences), :subLabel => null, :id => :devicePreferences},
        {:label => app.text(:networkPreferences), :subLabel => null, :id => :networkPreferences},
        {:label => app.text(:alertingPreferences), :subLabel => null, :id => :alertingPreferences},
        {:label => app.text(:toolPreferences), :subLabel => null, :id => :toolPreferences},
        {:label => "Version " + app.getAppVersion(), :subLabel => null, :id => :appVersion}
    ];
    if (app.isDevModeEnabled()) {
        entries.add({:label => "Developer Options", :subLabel => null, :id => :developerOptions});
    }
    addMenuEntries(menu, entries);
    return menu;
}

function buildDeveloperOptionsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "Developer Options"});
    addMenuEntry(menu, "Verbose Logging", toolToggleLabel(app.isVerboseLoggingEnabled()), :verboseLoggingToggle);
    addMenuEntry(menu, "Diagnostics", null, :diagnostics);
    return menu;
}

function buildDevicePreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:devicePreferences)});
    addMenuEntry(menu, app.text(:userMetrics), null, :userMetrics);
    return menu;
}

function buildNetworkPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:networkPreferences)});
    addMenuEntry(menu, app.text(:takConnect), null, :takServer);
    return menu;
}

function buildAlertingPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:alertingPreferences)});
    addMenuEntry(menu, app.text(:physiologicalAlerts), null, :physiologicalAlerts);
    addMenuEntry(menu, app.text(:environmentalAlerts), null, :environmentalAlerts);
    addMenuEntry(menu, "----------------", null, :alertSeparator);
    addMenuEntry(menu, app.text(:batteryAlerts), batteryAlertsLabel(app), :batteryAlertsToggle);
    return menu;
}

function buildEnvironmentalAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:environmentalAlerts)});
    addMenuEntry(menu, app.text(:immersionAlerts), immersionAlertsLabel(app), :immersionAlertsToggle);
    addMenuEntry(menu, app.text(:atmPressureAlerts), null, :atmPressureAlerts);
    return menu;
}

function buildAtmPressureAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:atmPressureTitle)});
    addMenuEntry(menu, app.text(:lowPressureAlert), pressureAlertsLabel(app.isLowPressureAlertsEnabled()), :lowPressureAlertsToggle);
    addLabelValueEntry(menu, app.text(:pressureThreshold), app.getAlertSetting(:lowPressureThreshold).toString() + " hPa", :lowPressureThreshold);
    addMenuEntry(menu, app.text(:highPressureAlert), pressureAlertsLabel(app.isHighPressureAlertsEnabled()), :highPressureAlertsToggle);
    addLabelValueEntry(menu, app.text(:pressureThreshold), app.getAlertSetting(:highPressureThreshold).toString() + " hPa", :highPressureThreshold);
    return menu;
}

function buildPhysiologicalAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:physiologicalAlerts)});
    addMenuEntry(menu, app.text(:physiologicalAlerts), physiologicalAlertsLabel(app), :physiologicalAlertsToggle);
    addMenuEntry(menu, app.text(:restingHeartRateAlerts), null, :restingHeartRateAlerts);
    addMenuEntry(menu, app.text(:exertionAlerts), null, :exertionAlerts);
    return menu;
}

function buildRestingHeartRateMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:restingHeartRateTitle)});
    addMenuEntry(menu, app.text(:highRestingHeartRate), null, :highHeading);
    addLabelValueEntry(menu, app.text(:highHrThreshold), app.getAlertSetting(:highThreshold).toString() + " bpm", :highThreshold);
    addLabelValueEntry(menu, app.text(:warningLength), app.getAlertSetting(:highWarning).toString() + " minutes", :highWarning);
    addLabelValueEntry(menu, app.text(:alertLength), app.getAlertSetting(:highAlert).toString() + " minutes", :highAlert);
    addMenuEntry(menu, app.text(:lowRestingHeartRate), null, :lowHeading);
    addLabelValueEntry(menu, app.text(:lowHrThreshold), app.getAlertSetting(:lowThreshold).toString() + " bpm", :lowThreshold);
    addLabelValueEntry(menu, app.text(:warningLength), app.getAlertSetting(:lowWarning).toString() + " minutes", :lowWarning);
    addLabelValueEntry(menu, app.text(:alertLength), app.getAlertSetting(:lowAlert).toString() + " minutes", :lowAlert);
    return menu;
}

function buildExertionAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:exertionTitle)});
    addLabelValueEntry(menu, app.text(:warningThreshold), app.getAlertSetting(:exertionWarningThreshold).toString() + "%", :exertionWarningThreshold);
    addLabelValueEntry(menu, app.text(:warningLength), app.getAlertSetting(:exertionWarningLength).toString() + " seconds", :exertionWarningLength);
    addLabelValueEntry(menu, app.text(:alertThreshold), app.getAlertSetting(:exertionAlertThreshold).toString() + "%", :exertionAlertThreshold);
    addLabelValueEntry(menu, app.text(:alertLength), app.getAlertSetting(:exertionAlertLength).toString() + " seconds", :exertionAlertLength);
    return menu;
}

function buildUserMetricsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:myUserMetrics)});
    addMenuEntry(menu, app.text(:medicalProfile), null, :medicalProfile);
    addMenuEntry(menu, app.text(:gaitTracking), null, :gaitTracking);
    return menu;
}

function buildMedicalProfileMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:medicalProfile)});
    addLabelValueEntry(menu, app.text(:birthYear), app.getUserMetric(:birthYear).toString(), :birthYear);
    addLabelValueEntry(menu, app.text(:height), formatHeightInFeetAndInches(app.getUserMetric(:height)), :height);
    addLabelValueEntry(menu, app.text(:weight), app.getUserMetric(:weight).toString() + " lb", :weight);
    addLabelValueEntry(menu, app.text(:sex), app.getUserMetric(:sex), :sex);
    addLabelValueEntry(menu, app.text(:bloodType), app.getUserMetric(:bloodType), :bloodType);
    addLabelValueEntry(menu, app.text(:allergies), app.allergiesLabel(), :allergies);
    addLabelValueEntry(menu, app.text(:userType), app.getUserMetric(:userType), :userType);
    return menu;
}

function allergyOptions() as Array {
    return ["N/A", "Antibiotics", "Anti-Inflammatory (Ibuprofen)", "Antiseizure", "Aspirin", "Insulin", "Muscle Relaxers", "Sulfa Drugs"];
}

function buildGaitTrackingMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:gaitTracking)});
    addLabelValueEntry(menu, app.text(:uniformWaistSize), app.getUserMetric(:uniformWaistSize).toString() + " in", :uniformWaistSize);
    addLabelValueEntry(menu, app.text(:strideLength), app.getUserMetric(:strideLength).toString() + " in", :strideLength);
    addLabelValueEntry(menu, app.text(:uniformPantsLength), app.getUserMetric(:uniformPantsLength).toString() + " in", :uniformPantsLength);
    addLabelValueEntry(menu, app.text(:loadoutWeight), app.getUserMetric(:loadoutWeight).toString() + " lbs", :loadoutWeight);
    return menu;
}

function buildAllergiesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:allergies)});
    var options = allergyOptions();
    for (var i = 0; i < options.size(); i++) {
        var allergy = options[i] as String;
        menu.addItem(new WatchUi.MenuItem(allergy, app.isAllergySelected(allergy) ? app.text(:allergyEnabled) : app.text(:allergyDisabled), allergy, null));
    }
    return menu;
}

function physiologicalAlertsLabel(app as StandaloneApp) as String {
    return app.isPhysiologicalAlertsEnabled() ? "On" : "Off";
}

function batteryAlertsLabel(app as StandaloneApp) as String {
    return app.isBatteryAlertsEnabled() ? "On (50%, 25%)" : "Off";
}

function immersionAlertsLabel(app as StandaloneApp) as String {
    return pressureAlertsLabel(app.isImmersionAlertsEnabled());
}

function pressureAlertsLabel(enabled as Boolean) as String {
    return enabled ? "On" : "Off";
}

function alertSettingLabel(setting as Symbol, value as Number) as String {
    if (setting == :lowPressureThreshold || setting == :highPressureThreshold) {
        return value.toString() + " hPa";
    } else if (setting == :highThreshold || setting == :lowThreshold) {
        return value.toString() + " bpm";
    } else if (setting == :exertionWarningThreshold || setting == :exertionAlertThreshold) {
        return value.toString() + "%";
    } else if (setting == :exertionWarningLength || setting == :exertionAlertLength) {
        return value.toString() + " seconds";
    }
    return value.toString() + " minutes";
}

function buildAlertValueMenu(app as StandaloneApp, setting as Symbol, parentItem as WatchUi.MenuItem) as WatchUi.Menu2 {
    var title;
    if (setting == :highThreshold || setting == :lowThreshold) {
        title = app.text(:heartRateThreshold);
    } else if (setting == :exertionWarningThreshold) {
        title = app.text(:warningThreshold);
    } else if (setting == :exertionAlertThreshold) {
        title = app.text(:alertThreshold);
    } else {
        title = app.text(:alertDuration);
    }
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

function buildToolPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:toolPreferences)});
    addToggleEntry(menu, app.text(:chat), app.isChatEnabled(), :chatToggle);
    addMenuEntry(menu, app.text(:bloodhoundCompass), null, :bloodhoundCompass);
    return menu;
}

function buildBloodhoundMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:navigationTitle)});
    addToggleEntry(menu, app.text(:proximityVibration), app.isBloodhoundProximityVibrationEnabled(), :bloodhoundProximityVibrationToggle);
    addLabelValueEntry(menu, app.text(:proximityRadius), app.getBloodhoundProximityRadius().toString() + " meters", :bloodhoundProximityRadius);
    addLabelValueEntry(menu, app.text(:proximityIntensity), app.getBloodhoundProximityIntensity(), :bloodhoundProximityIntensity);
    return menu;
}

function buildBloodhoundRadiusMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:proximityRadiusTitle)});
    addAlertValues(menu, 10, 200, 10);
    return menu;
}

function buildBloodhoundIntensityMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => app.text(:proximityIntensityTitle)});
    addProfileStringValues(menu, ["Single Burst", "Triple Burst", "Until In Position"]);
    return menu;
}

function toolToggleLabel(enabled as Boolean) as String {
    return enabled ? "On" : "Off";
}

function locationServicesLabel(app as StandaloneApp) as String {
    return app.isLocationServicesEnabled() ? app.text(:on) : app.text(:off);
}

function manualAlertMenuLabel(app as StandaloneApp) as String {
    var client = app.getTakClient();
    return client.isAlerting() ? app.text(:manualAlert) + " (" + app.alertTypeLabel(client.getAlertType()) + " " + app.text(:active) + ")" : app.text(:manualAlert);
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
        } else if (id == :bloodhoundCompassView) {
            WatchUi.pushView(new BloodhoundCompassView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :environment) {
            WatchUi.pushView(new EnvironmentalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :physiology) {
            WatchUi.pushView(new PhysiologicalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :chat) {
            var chatMenu = buildChatMenu(app);
            WatchUi.pushView(chatMenu, new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :environmentalAlerts) {
            WatchUi.pushView(buildEnvironmentalAlertsMenu(app), new EnvironmentalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :physiologicalAlerts) {
            WatchUi.pushView(buildPhysiologicalAlertsMenu(app), new PhysiologicalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var sosMenu = buildSosMenu(app);
            WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
        } else if (id == :takServer) {
            var takMenu = buildTakServerMenu();
            WatchUi.pushView(takMenu, new TakServerMenuDelegate(app, takMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :settings) {
            WatchUi.pushView(buildSettingsMenu(app), new SettingsMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :exit) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :clearPoints) {
            var mapView = app.getMapView();
            if (mapView == null || !mapView.hasPoints()) {
                return;
            }
            var confirmation = new WatchUi.Menu2({:title => app.text(:clearPointsPrompt)});
            confirmation.addItem(new WatchUi.MenuItem(app.text(:clearPointsAction), null, :clear, null));
            confirmation.addItem(new WatchUi.MenuItem(app.text(:cancel), null, :cancel, null));
            WatchUi.pushView(confirmation, new ClearPointsDelegate(app), WatchUi.SLIDE_UP);
        } else if (id == :dropPoint) {
            var mapView = app.getMapView();
            mapView.setTakClient(app.getTakClient());
            if (mapView.dropAtCurrentLocation()) {
                WatchUi.showToast(app.text(:pointDropped), null);
            } else {
                WatchUi.showToast(app.text(:locationUnavailable), null);
            }
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
        if (id != :appVersion) {
            app.resetVersionTapCount();
        }
        if (id == :devicePreferences) {
            var deviceMenu = buildDevicePreferencesMenu(app);
            WatchUi.pushView(deviceMenu, new DevicePreferencesDelegate(app, deviceMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :networkPreferences) {
            var networkMenu = buildNetworkPreferencesMenu(app);
            WatchUi.pushView(networkMenu, new NetworkPreferencesDelegate(app, networkMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :alertingPreferences) {
            var alertingMenu = buildAlertingPreferencesMenu(app);
            WatchUi.pushView(alertingMenu, new AlertingPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :toolPreferences) {
            WatchUi.pushView(buildToolPreferencesMenu(app), new ToolPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :developerOptions) {
            WatchUi.pushView(buildDeveloperOptionsMenu(app), new DeveloperOptionsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :appVersion) {
            if (app.registerVersionTap()) {
                WatchUi.showToast("Developer mode enabled", null);
                WatchUi.switchToView(buildSettingsMenu(app), new SettingsMenuDelegate(app), WatchUi.SLIDE_LEFT);
            }
        }
    }
}

class DeveloperOptionsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :verboseLoggingToggle) {
            app.setVerboseLoggingEnabled(!app.isVerboseLoggingEnabled());
            item.setSubLabel(toolToggleLabel(app.isVerboseLoggingEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :diagnostics) {
            WatchUi.pushView(new DiagnosticsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
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
        if (item.getId() == :userMetrics) {
            WatchUi.pushView(buildUserMetricsMenu(app), new UserMetricsDelegate(app), WatchUi.SLIDE_LEFT);
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
            WatchUi.pushView(buildEnvironmentalAlertsMenu(app), new EnvironmentalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :batteryAlertsToggle) {
            app.setBatteryAlertsEnabled(!app.isBatteryAlertsEnabled());
            item.setSubLabel(batteryAlertsLabel(app));
            WatchUi.requestUpdate();
        } else if (id == :physiologicalAlerts) {
            WatchUi.pushView(buildPhysiologicalAlertsMenu(app), new PhysiologicalAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var sosMenu = buildSosMenu(app);
            WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
        } else if (id == :toolPreferences) {
            WatchUi.pushView(buildToolPreferencesMenu(app), new ToolPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class EnvironmentalAlertsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :immersionAlertsToggle) {
            app.setImmersionAlertsEnabled(!app.isImmersionAlertsEnabled());
            item.setSubLabel(immersionAlertsLabel(app));
            WatchUi.requestUpdate();
        } else if (id == :atmPressureAlerts) {
            WatchUi.pushView(buildAtmPressureAlertsMenu(app), new AtmPressureAlertsDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class AtmPressureAlertsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :lowPressureAlertsToggle) {
            app.setLowPressureAlertsEnabled(!app.isLowPressureAlertsEnabled());
            item.setSubLabel(pressureAlertsLabel(app.isLowPressureAlertsEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :highPressureAlertsToggle) {
            app.setHighPressureAlertsEnabled(!app.isHighPressureAlertsEnabled());
            item.setSubLabel(pressureAlertsLabel(app.isHighPressureAlertsEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :lowPressureThreshold || id == :highPressureThreshold) {
            var setting = id as Symbol;
            WatchUi.pushView(buildPressureValueMenu(app, setting), new AlertValueDelegate(app, setting, item), WatchUi.SLIDE_LEFT);
        }
    }
}

function buildPressureValueMenu(app as StandaloneApp, setting as Symbol) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => setting == :lowPressureThreshold ? "Low Pressure Threshold" : "High Pressure Threshold"});
    if (setting == :lowPressureThreshold) {
        addAlertValues(menu, 800, 1100, 5);
    } else {
        addAlertValues(menu, 1000, 3000, 5);
    }
    return menu;
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
        var id = item.getId();
        if (id == :chatToggle) {
            app.setChatEnabled(!app.isChatEnabled());
            item.setSubLabel(toolToggleLabel(app.isChatEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :bloodhoundCompass) {
            WatchUi.pushView(buildBloodhoundMenu(app), new BloodhoundDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :clearPoints) {
            var confirmation = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.ConfirmClearPointsTitle)});
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelClearPoints), null, :clear, null));
            confirmation.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel, null));
            WatchUi.pushView(confirmation, new ClearPointsDelegate(app), WatchUi.SLIDE_UP);
        } else if (id == :chat) {
            WatchUi.pushView(buildChatMenu(app), new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class BloodhoundDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :bloodhoundCompassToggle) {
            app.setBloodhoundCompassEnabled(!app.isBloodhoundCompassEnabled());
            item.setSubLabel(toolToggleLabel(app.isBloodhoundCompassEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :bloodhoundProximityVibrationToggle) {
            app.setBloodhoundProximityVibrationEnabled(!app.isBloodhoundProximityVibrationEnabled());
            item.setSubLabel(toolToggleLabel(app.isBloodhoundProximityVibrationEnabled()));
            WatchUi.requestUpdate();
        } else if (id == :bloodhoundProximityRadius) {
            WatchUi.pushView(buildBloodhoundRadiusMenu(app), new BloodhoundValueDelegate(app, :radius, item), WatchUi.SLIDE_LEFT);
        } else if (id == :bloodhoundProximityIntensity) {
            WatchUi.pushView(buildBloodhoundIntensityMenu(app), new BloodhoundValueDelegate(app, :intensity, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class BloodhoundValueDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var setting as Symbol;
    var parentItem as WatchUi.MenuItem;

    function initialize(application as StandaloneApp, bloodhoundSetting as Symbol, item as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        app = application;
        setting = bloodhoundSetting;
        parentItem = item;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId();
        if (setting == :radius) {
            app.setBloodhoundProximityRadius(value as Number);
            parentItem.setSubLabel((value as Number).toString() + " meters");
        } else {
            app.setBloodhoundProximityIntensity(value as String);
            parentItem.setSubLabel(value as String);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
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
            WatchUi.showToast(app.text(:oldPointsCleared), null);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
