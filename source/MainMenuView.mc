import Toybox.Lang;
import Toybox.Communications;
import Toybox.System;
import Toybox.WatchUi;

function createMenu(title as String) as WatchUi.Menu2 {
    return new WatchUi.Menu2({:title => title});
}

function addMenuEntry(menu as WatchUi.Menu2, label as String, subLabel, id) as Void {
    menu.addItem(new WatchUi.MenuItem(label, subLabel, id, null));
}

function addLabelValueEntry(menu as WatchUi.Menu2, label as String, value as String, id as Symbol) as Void {
    addMenuEntry(menu, label, value, id);
}

function addToggleEntry(menu as WatchUi.Menu2, label as String, enabled as Boolean, id as Symbol) as Void {
    addMenuEntry(menu, label, toolToggleLabel(enabled), id);
}

function buildMainMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("WearTAK");
    var compassItem = new WatchUi.MenuItem(app.text(Rez.Strings.TextBloodhound), null, :incomingPoints, null);
    menu.addItem(compassItem);
    app.incomingPointMenuItem = compassItem;
    app.refreshIncomingPointCount();
    // Keep Bloodhound first; add remaining entries in alphabetical order.
    addMenuEntry(menu, "Chat", null, :chat);
    addMenuEntry(menu, "Clear 2525D", null, :managePoints);
    addMenuEntry(menu, "Drop 2525D", null, :dropPoint);
    addMenuEntry(menu, manualAlertMenuLabel(app), null, :sos);
    addMenuEntry(menu, app.text(Rez.Strings.TextMap), null, :map);
    addMenuEntry(menu, "Settings", null, :settings);
    return menu;
}

function buildPointDropTypeMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Drop 2525D");
    var defaultType = app.getMapView().getDefaultPointType();
    var hostileLabel = defaultType == :hostile ? "Selected default" : null;
    var neutralLabel = defaultType == :neutral ? "Selected default" : null;
    var friendlyLabel = defaultType == :friendly ? "Selected default" : null;
    var unknownLabel = defaultType == :unknown ? "Selected default" : null;
    addMenuEntry(menu, "Hostile", hostileLabel, :dropHostile);
    addMenuEntry(menu, "Neutral", neutralLabel, :dropNeutral);
    addMenuEntry(menu, "Friendly", friendlyLabel, :dropFriendly);
    addMenuEntry(menu, "Unknown", unknownLabel, :dropUnknown);
    addMenuEntry(menu, "Cancel", null, :cancelPointDrop);
    return menu;
}

function buildPointManagementMenu() as WatchUi.Menu2 {
    var menu = createMenu("Clear 2525D");
    addMenuEntry(menu, "Dropped Markers", null, :droppedMarkers);
    addMenuEntry(menu, "Clear Last Marker", null, :clearLastMarker);
    return menu;
}

function buildSettingsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextSettings));
    addMenuEntry(menu, "Callsign and Device Preferences", app.isPhoneManagedSettings() ? "Phone Managed" : null, :devicePreferences);
    addMenuEntry(menu, app.text(Rez.Strings.TextNetworkPreferences),
        app.isNetworkPreferencesLocked() || app.isPhoneManagedSettings() ? "Locked" : null, :networkPreferences);
    addMenuEntry(menu, app.text(Rez.Strings.TextAlertingPreferences), null, :alertingPreferences);
    addMenuEntry(menu, app.text(Rez.Strings.TextToolPreferences), null, :toolPreferences);
    addMenuEntry(menu, "Version " + app.getAppVersion(), null, :appVersion);
    if (app.isDevModeEnabled()) {
        addMenuEntry(menu, "Developer Options", null, :developerOptions);
    }
    return menu;
}

function buildDeveloperOptionsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Developer Options");
    addToggleEntry(menu, "Network Preferences Lock", app.isNetworkPreferencesLocked(), :networkPreferencesLockToggle);
    addMenuEntry(menu, "Verbose Logging", toolToggleLabel(app.isVerboseLoggingEnabled()), :verboseLoggingToggle);
    addMenuEntry(menu, "Diagnostics", null, :diagnostics);
    return menu;
}

function buildDevicePreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Callsign and Device Preferences");
    var managed = app.isPhoneManagedSettings();
    addMenuEntry(menu, "My Callsign", managed ? app.getCallsign() + " (Phone)" : null, :callsign);
    addMenuEntry(menu, "My Team", managed ? app.getMyTeamColor() + " (Phone)" : app.getMyTeamColor(), :myTeam);
    addMenuEntry(menu, "My Role", managed ? app.getMyRoleLabel() + " (Phone)" : app.getMyRoleLabel(), :myRole);
    addMenuEntry(menu, app.text(Rez.Strings.TextUserMetrics), null, :userMetrics);
    addMenuEntry(menu, "----------------", null, :devicePreferencesSeparator);
    addMenuEntry(menu, "Reporting Strategy",
        managed ? "Phone Managed" : (app.isDynamicReportingEnabled() ? "Dynamic" : "Static"), :reportingStrategy);
    return menu;
}

function buildReportingStrategyMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Reporting Strategy");
    addMenuEntry(menu, "Dynamic Reporting", app.isDynamicReportingEnabled() ? "Selected" : null, :dynamicReporting);
    addMenuEntry(menu, "Constant Reporting", !app.isDynamicReportingEnabled() ? "Selected" : null, :constantReporting);
    addMenuEntry(menu, "Save Battery on WiFi", app.getSaveBatteryOnWifiMode(), :saveBatteryOnWifi);
    addToggleEntry(menu, "Physiological Monitoring", app.isPhysiologicalMonitoringEnabled(), :physiologicalMonitoring);
    addToggleEntry(menu, "BATDOK", app.isBatdokCotEnabled(), :batdokCot);
    return menu;
}

function buildDynamicReportingMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Dynamic Reporting");
    addLabelValueEntry(menu, "Stationary Reporting Interval", app.getReportingInterval(:stationary).toString() + " seconds", :intervalStationary);
    addLabelValueEntry(menu, "On Foot Reporting Interval", app.getReportingInterval(:onFoot).toString() + " seconds", :intervalOnFoot);
    addLabelValueEntry(menu, "Vehicle Reporting Interval", app.getReportingInterval(:vehicle).toString() + " seconds", :intervalVehicle);
    addLabelValueEntry(menu, "While Alerting Reporting Interval", app.getReportingInterval(:whileAlerting).toString() + " seconds", :intervalWhileAlerting);
    return menu;
}

function buildConstantReportingMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Constant Reporting");
    addLabelValueEntry(menu, "Constant Reporting Interval", app.getReportingInterval(:constant).toString() + " seconds", :intervalConstant);
    return menu;
}

function reportingIntervalSetting(id as Symbol) as Symbol {
    if (id == :intervalStationary) { return :stationary; }
    else if (id == :intervalOnFoot) { return :onFoot; }
    else if (id == :intervalVehicle) { return :vehicle; }
    else if (id == :intervalWhileAlerting) { return :whileAlerting; }
    return :constant;
}

function buildReportingIntervalValuesMenu(app as StandaloneApp, setting as Symbol) as WatchUi.Menu2 {
    var title = setting == :stationary ? "Stationary Interval" : setting == :onFoot ? "On Foot Interval" : setting == :vehicle ? "Vehicle Interval" : setting == :whileAlerting ? "While Alerting Interval" : "Constant Interval";
    var menu = createMenu(title);
    var values = [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600];
    var current = app.getReportingInterval(setting);
    for (var index = 0; index < values.size(); index++) {
        var value = values[index] as Number;
        addMenuEntry(menu, value.toString() + " seconds", value == current ? "Selected" : null, value);
    }
    return menu;
}

function buildSaveBatteryOnWifiMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Save Battery on WiFi");
    var mode = app.getSaveBatteryOnWifiMode();
    addMenuEntry(menu, "All WiFi Connections", mode.equals("All WiFi Connections") ? "Selected" : null, :wifiAll);
    addMenuEntry(menu, "No WiFi Connections", mode.equals("No WiFi Connections") ? "Selected" : null, :wifiNone);
    addMenuEntry(menu, "Some WiFi Connections", mode.equals("Some WiFi Connections") ? "Selected" : null, :wifiSome);
    return menu;
}

function buildWifiNetworkMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("Selected WiFi Networks");
    addMenuEntry(menu, "Add WiFi Network (enter name)", null, :addWifiNetwork);
    var networks = app.getKnownWifiNetworks();
    for (var index = 0; index < networks.size(); index++) {
        var ssid = networks[index] as String;
        addMenuEntry(menu, ssid, app.isWifiNetworkSelected(ssid) ? "Selected" : "Not selected", ssid);
    }
    return menu;
}

function teamColorForMenuId(id as Symbol) as String {
    if (id == :teamWhite) { return "White"; }
    else if (id == :teamYellow) { return "Yellow"; }
    else if (id == :teamOrange) { return "Orange"; }
    else if (id == :teamMagenta) { return "Magenta"; }
    else if (id == :teamRed) { return "Red"; }
    else if (id == :teamMaroon) { return "Maroon"; }
    else if (id == :teamPurple) { return "Purple"; }
    else if (id == :teamDarkBlue) { return "Dark Blue"; }
    else if (id == :teamCyan) { return "Cyan"; }
    else if (id == :teamTeal) { return "Teal"; }
    else if (id == :teamGreen) { return "Green"; }
    else if (id == :teamDarkGreen) { return "Dark Green"; }
    else if (id == :teamBrown) { return "Brown"; }
    return "Blue";
}

function teamMenuIdForColor(color as String) as Symbol {
    if (color.equals("White")) { return :teamWhite; }
    else if (color.equals("Yellow")) { return :teamYellow; }
    else if (color.equals("Orange")) { return :teamOrange; }
    else if (color.equals("Magenta")) { return :teamMagenta; }
    else if (color.equals("Red")) { return :teamRed; }
    else if (color.equals("Maroon")) { return :teamMaroon; }
    else if (color.equals("Purple")) { return :teamPurple; }
    else if (color.equals("Dark Blue")) { return :teamDarkBlue; }
    else if (color.equals("Cyan")) { return :teamCyan; }
    else if (color.equals("Teal")) { return :teamTeal; }
    else if (color.equals("Green")) { return :teamGreen; }
    else if (color.equals("Dark Green")) { return :teamDarkGreen; }
    else if (color.equals("Brown")) { return :teamBrown; }
    return :teamBlue;
}

function buildMyTeamMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("My Team");
    var colors = ["White", "Yellow", "Orange", "Magenta", "Red", "Maroon", "Purple", "Dark Blue", "Blue", "Cyan", "Teal", "Green", "Dark Green", "Brown"];
    for (var index = 0; index < colors.size(); index++) {
        var color = colors[index] as String;
        var subLabel = color.equals(app.getMyTeamColor()) ? "Selected" : null;
        addMenuEntry(menu, color, subLabel, teamMenuIdForColor(color));
    }
    return menu;
}

function buildMyRoleCategoryMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("My Role");
    addMenuEntry(menu, "MIL", app.getMyRoleCategory().equals("MIL") ? "Selected" : null, :myRoleMil);
    addMenuEntry(menu, "LEO", app.getMyRoleCategory().equals("LEO") ? "Selected" : null, :myRoleLeo);
    return menu;
}

function myRoleOptions(category as String) as Array<String> {
    if (category.equals("LEO")) {
        return ["Armed Surveillance", "Assistant Team Leader", "Aviation", "Bomb Tech", "Command Post", "Critical Response", "Hazards", "Negotiator", "Surveillance", "Tactical Communicator", "TOC"];
    }
    return ["Forward Observer", "HQ", "K9", "Medic", "RTO", "Sniper", "Team Lead", "Team Member"];
}

function buildMyRoleOptionsMenu(app as StandaloneApp, category as String) as WatchUi.Menu2 {
    var menu = createMenu(category + " Roles");
    var roles = myRoleOptions(category);
    for (var index = 0; index < roles.size(); index++) {
        var role = roles[index] as String;
        var subLabel = app.getMyRoleCategory().equals(category) && app.getMyRole().equals(role) ? "Selected" : null;
        addMenuEntry(menu, role, subLabel, index);
    }
    return menu;
}

function buildNetworkPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextNetworkPreferences));
    addMenuEntry(menu, "TAK Relay", null, :takRelayMenu);
    addMenuEntry(menu, "Sit(x) TAK", app.getSitxClient().networkStatusLabel(), :sitxDeviceApi);
    return menu;
}

function buildTakRelayMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu("TAK Relay");
    var client = app.getTakClient();
    addToggleEntry(menu, "ATAK Relay", client.status == :connecting || client.isConnected(), :atakRelayToggle);
    addMenuEntry(menu, "iTAK", "Teaming", :itakRelay);
    addMenuEntry(menu, "TAK Aware", "Teaming", :takAwareRelay);
    addMenuEntry(menu, "WearTAK Companion", "Developing", :wearTakCompanionRelay);
    return menu;
}

function openTakChannels(app as StandaloneApp) as Void {
    var client = app.getTakClient();
    var emptyLabel = client.isConnected() ? "Loading servers..." : "TAK Relay Off";
    var channelsMenu = buildChannelServersMenu([], emptyLabel);
    WatchUi.pushView(channelsMenu, new TakChannelsMenuDelegate(app, [], []), WatchUi.SLIDE_LEFT);
    if (client.isConnected()) { client.requestChannelServers(); }
}

function buildChannelServersMenu(servers as Array, emptyLabel as String) as WatchUi.Menu2 {
    var menu = createMenu("TAK Channels");
    if (servers.size() == 0) {
        var statusId = emptyLabel.equals("TAK Relay Off") ? :channelRelayOff : :channelStatus;
        addMenuEntry(menu, emptyLabel, null, statusId);
    }
    for (var index = 0; index < servers.size(); index++) {
        var server = servers[index] as Dictionary;
        var label = server.get("name") == null ? "TAK Server" : server.get("name").toString();
        addMenuEntry(menu, label, null, server.get("serverIndex"));
    }
    addMenuEntry(menu, "Back", null, :backChannels);
    return menu;
}

function buildChannelsMenu(serverName as String, channels as Array) as WatchUi.Menu2 {
    var menu = createMenu(serverName);
    for (var index = 0; index < channels.size(); index++) {
        var channel = channels[index] as Dictionary;
        var subLabel = channel.get("direction").toString() + " | " + (channel.get("active") == true ? "Active" : "Inactive");
        addMenuEntry(menu, channel.get("name").toString(), subLabel, channel.get("bitpos"));
    }
    addMenuEntry(menu, "Back", null, :backChannels);
    return menu;
}

function buildSitxDeviceApiMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var client = app.getSitxClient();
    var menu = createMenu("Sit(x) TAK");
    addToggleEntry(menu, "TAK", client.isTakEnabled(), :sitxEnabledToggle);
    var organization = client.getOrganizationAddress();
    addMenuEntry(menu, "Address", organization.length() == 0 ? "Not set" : organization, :sitxApiHost);
    addMenuEntry(menu, "Group", client.getSelectedGroupName(), :sitxGroup);
    addMenuEntry(menu, "Sit(x) State", client.statusText(), :sitxStatus);
    addMenuEntry(menu, "Re-auth", null, :sitxReauth);
    addMenuEntry(menu, "Remove Sit(x) Connection", null, :sitxRemove);
    addMenuEntry(menu, "Back", null, :sitxBack);
    return menu;
}

function buildSitxGroupsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var client = app.getSitxClient();
    var menu = createMenu("Select TAK Group");
    var groups = client.getGroups();
    if (groups.size() == 0) {
        addMenuEntry(menu, "No permitted TAK groups", null, :sitxNoGroups);
    } else {
        for (var index = 0; index < groups.size(); index++) {
            var group = groups[index] as SitxGroup;
            var label = group.flowTag.equals(client.getSelectedGroupFlowTag()) ? "Selected" : null;
            addMenuEntry(menu, group.name, label, index);
        }
    }
    addMenuEntry(menu, "Back", null, :sitxGroupBack);
    return menu;
}

function buildAlertingPreferencesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextAlertingPreferences));
    addMenuEntry(menu, app.text(Rez.Strings.TextPhysiologicalAlerts), null, :physiologicalAlerts);
    addMenuEntry(menu, app.text(Rez.Strings.TextEnvironmentalAlerts), null, :environmentalAlerts);
    addMenuEntry(menu, app.text(Rez.Strings.TextBatteryAlerts), batteryAlertsLabel(app), :batteryAlertsToggle);
    return menu;
}

function buildEnvironmentalAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextEnvironmentalAlerts));
    addMenuEntry(menu, app.text(Rez.Strings.TextImmersionAlerts), immersionAlertsLabel(app), :immersionAlertsToggle);
    addMenuEntry(menu, app.text(Rez.Strings.TextAtmPressureAlerts), null, :atmPressureAlerts);
    return menu;
}

function buildAtmPressureAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextAtmPressureAlerts));
    addMenuEntry(menu, app.text(Rez.Strings.TextLowPressureAlert), pressureAlertsLabel(app.isLowPressureAlertsEnabled()), :lowPressureAlertsToggle);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextPressureThreshold), app.getAlertSetting(:lowPressureThreshold).toString() + " hPa", :lowPressureThreshold);
    addMenuEntry(menu, app.text(Rez.Strings.TextHighPressureAlert), pressureAlertsLabel(app.isHighPressureAlertsEnabled()), :highPressureAlertsToggle);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextPressureThreshold), app.getAlertSetting(:highPressureThreshold).toString() + " hPa", :highPressureThreshold);
    return menu;
}

function buildPhysiologicalAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextPhysiologicalAlerts));
    addMenuEntry(menu, app.text(Rez.Strings.TextPhysiologicalAlerts), physiologicalAlertsLabel(app), :physiologicalAlertsToggle);
    addMenuEntry(menu, app.text(Rez.Strings.TextRestingHeartRateAlerts), null, :restingHeartRateAlerts);
    addMenuEntry(menu, app.text(Rez.Strings.TextExertionAlerts), null, :exertionAlerts);
    return menu;
}

function buildRestingHeartRateMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextRestingHeartRateAlerts));
    addMenuEntry(menu, app.text(Rez.Strings.TextHighRestingHeartRate), null, :highHeading);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextHighHrThreshold), app.getAlertSetting(:highThreshold).toString() + " bpm", :highThreshold);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextWarningLength), app.getAlertSetting(:highWarning).toString() + " minutes", :highWarning);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextAlertLength), app.getAlertSetting(:highAlert).toString() + " minutes", :highAlert);
    addMenuEntry(menu, app.text(Rez.Strings.TextLowRestingHeartRate), null, :lowHeading);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextLowHrThreshold), app.getAlertSetting(:lowThreshold).toString() + " bpm", :lowThreshold);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextWarningLength), app.getAlertSetting(:lowWarning).toString() + " minutes", :lowWarning);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextAlertLength), app.getAlertSetting(:lowAlert).toString() + " minutes", :lowAlert);
    return menu;
}

function buildExertionAlertsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextExertionAlerts));
    addLabelValueEntry(menu, app.text(Rez.Strings.TextWarningThreshold), app.getAlertSetting(:exertionWarningThreshold).toString() + "%", :exertionWarningThreshold);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextWarningLength), app.getAlertSetting(:exertionWarningLength).toString() + " seconds", :exertionWarningLength);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextAlertThreshold), app.getAlertSetting(:exertionAlertThreshold).toString() + "%", :exertionAlertThreshold);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextAlertLength), app.getAlertSetting(:exertionAlertLength).toString() + " seconds", :exertionAlertLength);
    return menu;
}

function buildUserMetricsMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextMyUserMetrics));
    addMenuEntry(menu, app.text(Rez.Strings.TextMedicalProfile), null, :medicalProfile);
    addMenuEntry(menu, app.text(Rez.Strings.TextGaitTracking), null, :gaitTracking);
    return menu;
}

function buildMedicalProfileMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextMedicalProfile));
    addLabelValueEntry(menu, app.text(Rez.Strings.TextBirthYear), app.getUserMetric(:birthYear).toString(), :birthYear);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextHeight), formatHeightInFeetAndInches(app.getUserMetric(:height)), :height);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextWeight), app.getUserMetric(:weight).toString() + " lb", :weight);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextSex), app.getUserMetric(:sex), :sex);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextBloodType), app.getUserMetric(:bloodType), :bloodType);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextAllergies), app.allergiesLabel(), :allergies);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextUserType), app.getUserMetric(:userType), :userType);
    return menu;
}

function allergyOptions() as Array {
    return ["N/A", "Antibiotics", "Anti-Inflammatory (Ibuprofen)", "Antiseizure", "Aspirin", "Insulin", "Muscle Relaxers", "Sulfa Drugs"];
}

function buildGaitTrackingMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextGaitTracking));
    addLabelValueEntry(menu, app.text(Rez.Strings.TextUniformWaistSize), app.getUserMetric(:uniformWaistSize).toString() + " in", :uniformWaistSize);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextStrideLength), app.getUserMetric(:strideLength).toString() + " in", :strideLength);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextUniformPantsLength), app.getUserMetric(:uniformPantsLength).toString() + " in", :uniformPantsLength);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextLoadoutWeight), app.getUserMetric(:loadoutWeight).toString() + " lbs", :loadoutWeight);
    return menu;
}

function buildAllergiesMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextAllergies));
    var options = allergyOptions();
    for (var i = 0; i < options.size(); i++) {
        var allergy = options[i] as String;
        addMenuEntry(menu, allergy, app.isAllergySelected(allergy) ? app.text(Rez.Strings.TextAllergyEnabled) : app.text(Rez.Strings.TextAllergyDisabled), allergy);
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
        title = app.text(Rez.Strings.TextHeartRateThreshold);
    } else if (setting == :exertionWarningThreshold) {
        title = app.text(Rez.Strings.TextWarningThreshold);
    } else if (setting == :exertionAlertThreshold) {
        title = app.text(Rez.Strings.TextAlertThreshold);
    } else {
        title = app.text(Rez.Strings.TextAlertDuration);
    }
    var menu = createMenu(title);
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
        addMenuEntry(menu, value.toString(), null, value);
        value += step;
    }
}

function buildProfileValueMenu(app as StandaloneApp, setting as Symbol) as WatchUi.Menu2 {
    var title = setting == :birthYear ? "Birth Year" : setting == :height ? "Height" : setting == :weight ? "Weight" : setting == :sex ? "Sex" : setting == :bloodType ? "Blood Type" : setting == :uniformWaistSize ? "Uniform Waist Size" : setting == :strideLength ? "Stride Length" : setting == :uniformPantsLength ? "Uniform Pants Length" : setting == :loadoutWeight ? "Loadout Weight" : "User Type";
    var menu = createMenu(title);
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
        addMenuEntry(menu, value.toString(), null, value);
        value += step;
    }
}

function addProfileStringValues(menu as WatchUi.Menu2, values as Array) as Void {
    for (var i = 0; i < values.size(); i++) {
        addMenuEntry(menu, values[i], null, values[i]);
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
    var menu = createMenu(app.text(Rez.Strings.TextToolPreferences));
    addMenuEntry(menu, app.text(Rez.Strings.TextBloodhoundCompass), null, :bloodhoundCompass);
    addMenuEntry(menu, WatchUi.loadResource(Rez.Strings.PluginsTitle), null, :plugins);
    return menu;
}

function buildBloodhoundMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextBloodhoundCompass));
    addToggleEntry(menu, app.text(Rez.Strings.TextProximityVibration), app.isBloodhoundProximityVibrationEnabled(), :bloodhoundProximityVibrationToggle);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextProximityRadius), app.getBloodhoundProximityRadius().toString() + " meters", :bloodhoundProximityRadius);
    addLabelValueEntry(menu, app.text(Rez.Strings.TextProximityIntensity), app.getBloodhoundProximityIntensity(), :bloodhoundProximityIntensity);
    return menu;
}

function buildBloodhoundRadiusMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextProximityRadius));
    addAlertValues(menu, 10, 200, 10);
    return menu;
}

function buildBloodhoundIntensityMenu(app as StandaloneApp) as WatchUi.Menu2 {
    var menu = createMenu(app.text(Rez.Strings.TextProximityIntensity));
    addProfileStringValues(menu, ["Single Burst", "Triple Burst", "Until In Position"]);
    return menu;
}

function toolToggleLabel(enabled as Boolean) as String {
    return enabled ? "On" : "Off";
}

function locationServicesLabel(app as StandaloneApp) as String {
    return app.isLocationServicesEnabled() ? app.text(Rez.Strings.TextOn) : app.text(Rez.Strings.TextOff);
}

function manualAlertMenuLabel(app as StandaloneApp) as String {
    var client = app.getTakClient();
    return client.isAlerting() ? app.text(Rez.Strings.TextManualAlert) + " (" + app.text(Rez.Strings.TextActive) + ")" : app.text(Rez.Strings.TextManualAlert);
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
            app.refreshPliForUserAction();
            var mapView = app.getMapView();
            mapView.setTakClient(app.getTakClient());
            WatchUi.pushView(mapView, new StandaloneMapDelegate(mapView, false, app), WatchUi.SLIDE_LEFT);
        } else if (id == :chat) {
            var chatMenu = buildChatMenu(app);
            WatchUi.pushView(chatMenu, new ChatMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :incomingPoints) {
            WatchUi.pushView(buildIncomingPointsMenu(app), new IncomingPointsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :sos) {
            var alertClient = app.getTakClient();
            if (alertClient.isAlerting()) {
                alertClient.setAlerting(false);
                WatchUi.switchToView(buildMainMenu(app), new MainMenuDelegate(app), WatchUi.SLIDE_RIGHT);
            } else {
                var sosMenu = buildSosMenu(app);
                WatchUi.pushView(sosMenu, new SosMenuDelegate(app, true), WatchUi.SLIDE_LEFT);
            }
        } else if (id == :settings) {
            WatchUi.pushView(buildSettingsMenu(app), new SettingsMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :dropPoint) {
            var pointTypeMenu = buildPointDropTypeMenu(app);
            WatchUi.pushView(pointTypeMenu, new PointDropTypeMenuDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :managePoints) {
            var pointManagementMenu = buildPointManagementMenu();
            WatchUi.pushView(pointManagementMenu, new PointManagementMenuDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class PointDropTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var mapView = app.getMapView();
        if (id == :cancelPointDrop) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        var type = id == :dropHostile ? :hostile : id == :dropNeutral ? :neutral : id == :dropFriendly ? :friendly : :unknown;
        mapView.setTakClient(app.getTakClient());
        if (mapView.dropAtCurrentLocationAs(type)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class PointManagementMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;

    function initialize(application as StandaloneApp) {
        Menu2InputDelegate.initialize();
        app = application;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mapView = app.getMapView();
        if (item.getId() == :droppedMarkers) {
            var markersMenu = buildDroppedMarkersMenu(mapView);
            WatchUi.pushView(markersMenu, new DroppedMarkersMenuDelegate(mapView, markersMenu), WatchUi.SLIDE_LEFT);
        } else if (item.getId() == :clearLastMarker) {
            if (!mapView.hasPoints()) {
                WatchUi.showToast("No markers to clear", null);
                return;
            }
            var confirmation = createMenu("Clear Last Marker?");
            addMenuEntry(confirmation, "Clear Last Marker", null, :confirmClearLast);
            addMenuEntry(confirmation, "Cancel", null, :cancelClearLast);
            WatchUi.pushView(confirmation, new PointDeletionConfirmationDelegate(mapView, :last), WatchUi.SLIDE_UP);
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
            if (app.isNetworkPreferencesLocked() || app.isPhoneManagedSettings()) {
                WatchUi.showToast("Network settings are locked", null);
                return;
            }
            var networkMenu = buildNetworkPreferencesMenu(app);
            WatchUi.pushView(networkMenu, new NetworkPreferencesDelegate(app, networkMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :environment) {
            WatchUi.pushView(new EnvironmentalSensorsView(app), new SensorViewDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :alertingPreferences) {
            var alertingMenu = buildAlertingPreferencesMenu(app);
            WatchUi.pushView(alertingMenu, new AlertingPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :toolPreferences) {
            WatchUi.pushView(buildToolPreferencesMenu(app), new ToolPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :developerOptions) {
            var developerMenu = buildDeveloperOptionsMenu(app);
            WatchUi.pushView(developerMenu, new DeveloperOptionsDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :appVersion) {
            if (app.registerVersionTap()) {
                WatchUi.showToast("Developer mode " + (app.isDevModeEnabled() ? "enabled" : "disabled"), null);
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
        if (id == :networkPreferencesLockToggle) {
            var locked = !app.isNetworkPreferencesLocked();
            app.setNetworkPreferencesLocked(locked);
            item.setSubLabel(toolToggleLabel(locked));
            WatchUi.switchToView(buildSettingsMenu(app), new SettingsMenuDelegate(app), WatchUi.SLIDE_RIGHT);
        } else if (id == :verboseLoggingToggle) {
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
        var id = item.getId();
        if (app.isPhoneManagedSettings()
                && (id == :callsign || id == :myTeam || id == :myRole || id == :reportingStrategy)) {
            WatchUi.showToast("Managed by the paired phone", null);
            return;
        }
        if (id == :callsign) {
            var initialCallsign = app.getCallsign().length() == 0 ? " " : app.getCallsign();
            WatchUi.pushView(new WatchUi.TextPicker(initialCallsign), new CallsignTextPickerDelegate(app, menu), WatchUi.SLIDE_UP);
        } else if (id == :myTeam) {
            WatchUi.pushView(buildMyTeamMenu(app), new MyTeamDelegate(app, menu), WatchUi.SLIDE_LEFT);
        } else if (id == :myRole) {
            var roleMenu = buildMyRoleCategoryMenu(app);
            WatchUi.pushView(roleMenu, new MyRoleCategoryDelegate(app, menu), WatchUi.SLIDE_LEFT);
        } else if (id == :reportingStrategy) {
            var reportingMenu = buildReportingStrategyMenu(app);
            WatchUi.pushView(reportingMenu, new ReportingStrategyDelegate(app, reportingMenu, menu), WatchUi.SLIDE_LEFT);
        } else if (id == :userMetrics) {
            WatchUi.pushView(buildUserMetricsMenu(app), new UserMetricsDelegate(app), WatchUi.SLIDE_LEFT);
        }
    }
}

class ReportingStrategyDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;
    var preferencesMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, reportingMenu as WatchUi.Menu2, parentMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = reportingMenu;
        preferencesMenu = parentMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :dynamicReporting) {
            app.setDynamicReportingEnabled(true);
            updatePreferenceLabel("Dynamic");
            item.setSubLabel("Selected");
            menu.getItem(menu.findItemById(:constantReporting)).setSubLabel(null);
            var dynamicMenu = buildDynamicReportingMenu(app);
            WatchUi.pushView(dynamicMenu, new ReportingIntervalsDelegate(app, dynamicMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :constantReporting) {
            app.setDynamicReportingEnabled(false);
            updatePreferenceLabel("Static");
            item.setSubLabel("Selected");
            menu.getItem(menu.findItemById(:dynamicReporting)).setSubLabel(null);
            var constantMenu = buildConstantReportingMenu(app);
            WatchUi.pushView(constantMenu, new ReportingIntervalsDelegate(app, constantMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :saveBatteryOnWifi) {
            var wifiMenu = buildSaveBatteryOnWifiMenu(app);
            WatchUi.pushView(wifiMenu, new SaveBatteryOnWifiDelegate(app, wifiMenu, menu), WatchUi.SLIDE_LEFT);
        } else if (id == :physiologicalMonitoring) {
            var enabled = !app.isPhysiologicalMonitoringEnabled();
            app.setPhysiologicalMonitoringEnabled(enabled);
            item.setSubLabel(toolToggleLabel(enabled));
            WatchUi.requestUpdate();
        } else if (id == :batdokCot) {
            var enabled = !app.isBatdokCotEnabled();
            app.setBatdokCotEnabled(enabled);
            item.setSubLabel(toolToggleLabel(enabled));
            WatchUi.requestUpdate();
        }
    }

    function updatePreferenceLabel(value as String) as Void {
        var item = preferencesMenu.getItem(preferencesMenu.findItemById(:reportingStrategy));
        if (item != null) { item.setSubLabel(value); }
    }
}

class ReportingIntervalsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, intervalMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = intervalMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var setting = reportingIntervalSetting(item.getId() as Symbol);
        var valuesMenu = buildReportingIntervalValuesMenu(app, setting);
        WatchUi.pushView(valuesMenu, new ReportingIntervalValuesDelegate(app, valuesMenu, menu, setting), WatchUi.SLIDE_LEFT);
    }
}

class ReportingIntervalValuesDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var valuesMenu as WatchUi.Menu2;
    var intervalMenu as WatchUi.Menu2;
    var setting as Symbol;

    function initialize(application as StandaloneApp, valueMenu as WatchUi.Menu2, parentMenu as WatchUi.Menu2, intervalSetting as Symbol) {
        Menu2InputDelegate.initialize();
        app = application;
        valuesMenu = valueMenu;
        intervalMenu = parentMenu;
        setting = intervalSetting;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var seconds = item.getId() as Number;
        app.setReportingInterval(setting, seconds);
        var parentId = setting == :stationary ? :intervalStationary : setting == :onFoot ? :intervalOnFoot : setting == :vehicle ? :intervalVehicle : setting == :whileAlerting ? :intervalWhileAlerting : :intervalConstant;
        intervalMenu.getItem(intervalMenu.findItemById(parentId)).setSubLabel(seconds.toString() + " seconds");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class SaveBatteryOnWifiDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var wifiMenu as WatchUi.Menu2;
    var reportingMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, modeMenu as WatchUi.Menu2, parentMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        wifiMenu = modeMenu;
        reportingMenu = parentMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :wifiAll || id == :wifiNone || id == :wifiSome) {
            var mode = id == :wifiAll ? "All WiFi Connections" : id == :wifiNone ? "No WiFi Connections" : "Some WiFi Connections";
            app.setSaveBatteryOnWifiMode(mode);
            reportingMenu.getItem(reportingMenu.findItemById(:saveBatteryOnWifi)).setSubLabel(mode);
            item.setSubLabel("Selected");
            if (id == :wifiSome) {
                var networksMenu = buildWifiNetworkMenu(app);
                WatchUi.pushView(networksMenu, new WifiNetworkDelegate(app, networksMenu), WatchUi.SLIDE_LEFT);
            }
        }
    }
}

class WifiNetworkDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, networkMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = networkMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :addWifiNetwork) {
            WatchUi.pushView(new WatchUi.TextPicker(""), new WifiNetworkTextPickerDelegate(app, menu), WatchUi.SLIDE_UP);
        } else if (id instanceof String) {
            var ssid = id as String;
            app.toggleWifiNetwork(ssid);
            item.setSubLabel(app.isWifiNetworkSelected(ssid) ? "Selected" : "Not selected");
        }
    }
}

class WifiNetworkTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, networkMenu as WatchUi.Menu2) {
        TextPickerDelegate.initialize();
        app = application;
        menu = networkMenu;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (changed && value.length() > 0) {
            var networks = app.getKnownWifiNetworks();
            var exists = false;
            for (var index = 0; index < networks.size(); index++) {
                if ((networks[index] as String).equals(value)) { exists = true; }
            }
            if (!exists) {
                app.addKnownWifiNetwork(value);
                addMenuEntry(menu, value, "Selected", value);
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

class MyTeamDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var preferencesMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        preferencesMenu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        app.setMyTeamColor(teamColorForMenuId(item.getId() as Symbol));
        var teamItem = preferencesMenu.getItem(preferencesMenu.findItemById(:myTeam));
        if (teamItem != null) {
            teamItem.setSubLabel(app.getMyTeamColor());
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

}

class MyRoleCategoryDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var preferencesMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        preferencesMenu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var category = item.getId() == :myRoleLeo ? "LEO" : "MIL";
        var roleMenu = buildMyRoleOptionsMenu(app, category);
        WatchUi.pushView(roleMenu, new MyRoleOptionsDelegate(app, preferencesMenu, category, roleMenu), WatchUi.SLIDE_LEFT);
    }
}

class MyRoleOptionsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var preferencesMenu as WatchUi.Menu2;
    var category as String;
    var roles as Array<String>;

    function initialize(application as StandaloneApp, menu as WatchUi.Menu2, roleCategory as String, roleMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        preferencesMenu = menu;
        category = roleCategory;
        roles = myRoleOptions(category);
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var index = item.getId() as Number;
        if (index >= 0 && index < roles.size()) {
            app.setMyRole(category, roles[index] as String);
            var roleItem = preferencesMenu.getItem(preferencesMenu.findItemById(:myRole));
            if (roleItem != null) {
                roleItem.setSubLabel(app.getMyRoleLabel());
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class CallsignTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, preferencesMenu as WatchUi.Menu2) {
        TextPickerDelegate.initialize();
        app = application;
        menu = preferencesMenu;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (changed) {
            app.setCallsign(value);
            var callsign = app.getCallsign();
            menu.getItem(menu.findItemById(:callsign)).setSubLabel(callsign.length() == 0 ? null : callsign);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean {
        return true;
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
        var id = item.getId();
        if (id == :sitxDeviceApi) {
            var sitxMenu = buildSitxDeviceApiMenu(app);
            WatchUi.pushView(sitxMenu, new SitxDeviceApiDelegate(app, sitxMenu, menu), WatchUi.SLIDE_LEFT);
        } else if (id == :takRelayMenu) {
            var relayMenu = buildTakRelayMenu(app);
            WatchUi.pushView(relayMenu, new NetworkPreferencesDelegate(app, relayMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :atakRelayToggle) {
            var client = app.getTakClient();
            client.statusCallback = method(:onClientStatusChanged);
            if (client.status == :connecting || client.isConnected()) {
                client.disconnect();
            } else {
                client.connect();
            }
            onClientStatusChanged();
        } else if (id == :itakRelay || id == :takAwareRelay || id == :wearTakCompanionRelay) {
            WatchUi.showToast(item.getLabel() + " - " + item.getSubLabel(), null);
        }
    }

    function onClientStatusChanged() as Void {
        var client = app.getTakClient();
        var relayItem = menu.getItem(menu.findItemById(:atakRelayToggle));
        if (relayItem != null) {
            relayItem.setSubLabel(toolToggleLabel(client.status == :connecting || client.isConnected()));
            WatchUi.requestUpdate();
        }
    }
}

class TakChannelsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var servers as Array;
    var channels as Array;
    var serverIndex as Number = -1;
    var showingChannels as Boolean = false;
    var busy as Boolean = false;

    function initialize(application as StandaloneApp, serverList as Array, channelList as Array) {
        Menu2InputDelegate.initialize();
        app = application;
        servers = serverList;
        channels = channelList;
        app.getTakClient().setChannelsCallback(method(:onChannelsResponse));
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :backChannels) {
            onBack();
            return;
        }
        if (id == :channelRelayOff) {
            var networkMenu = buildNetworkPreferencesMenu(app);
            WatchUi.pushView(networkMenu, new NetworkPreferencesDelegate(app, networkMenu), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == :channelStatus) { return; }
        if (!(item.getId() instanceof Number) || busy) { return; }
        if (showingChannels) {
            var bitPosition = item.getId() as Number;
            for (var index = 0; index < channels.size(); index++) {
                var channel = channels[index] as Dictionary;
                if (channel.get("bitpos") == bitPosition) {
                    busy = true;
                    app.getTakClient().updateChannel(serverIndex, bitPosition, channel.get("active") != true);
                    WatchUi.showToast("Updating channel...", null);
                    return;
                }
            }
            return;
        }

        serverIndex = item.getId() as Number;
        busy = true;
        app.getTakClient().requestChannels(serverIndex);
        WatchUi.showToast("Loading channels...", null);
    }

    function onChannelsResponse(msgType as String, payload as Dictionary) as Void {
        if (msgType == "channels_error") {
            busy = false;
            WatchUi.showToast(payload.get("error").toString(), null);
        } else if (msgType == "channels_servers_response") {
            var serverList = payload.get("servers");
            servers = serverList instanceof Array ? serverList as Array : [];
            busy = false;
            var emptyLabel = servers.size() == 0 ? "No enabled servers" : "";
            WatchUi.switchToView(buildChannelServersMenu(servers, emptyLabel), self, WatchUi.SLIDE_LEFT);
        } else if (msgType == "channels_response") {
            var channelList = payload.get("channels");
            channels = channelList instanceof Array ? channelList as Array : [];
            var serverName = payload.get("serverName").toString();
            showingChannels = true;
            busy = false;
            WatchUi.switchToView(buildChannelsMenu(serverName, channels), self, WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        busy = false;
        if (showingChannels) {
            showingChannels = false;
            var emptyLabel = servers.size() == 0 ? "No enabled servers" : "";
            WatchUi.switchToView(buildChannelServersMenu(servers, emptyLabel), self, WatchUi.SLIDE_RIGHT);
        } else {
            app.getTakClient().setChannelsCallback(null);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class SitxDeviceApiDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;
    var networkMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, sitxMenu as WatchUi.Menu2, parentMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        menu = sitxMenu;
        networkMenu = parentMenu;
        app.getSitxClient().statusCallback = method(:updateMenu);
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var client = app.getSitxClient();
        if (id == :sitxEnabledToggle) {
            client.setTakEnabled(!client.isTakEnabled());
        } else if (id == :sitxApiHost) {
            WatchUi.pushView(new WatchUi.TextPicker(client.getOrganizationAddress()), new SitxSettingsTextPickerDelegate(app, menu), WatchUi.SLIDE_UP);
        } else if (id == :sitxGroup) {
            var groupsMenu = buildSitxGroupsMenu(app);
            WatchUi.pushView(groupsMenu, new SitxGroupsDelegate(app, groupsMenu, menu, networkMenu), WatchUi.SLIDE_LEFT);
        } else if (id == :sitxStatus) {
            if (client.getUserCode().length() > 0) {
                WatchUi.showToast("Auth code: " + client.getUserCode(), null);
                if (client.getVerificationUrl().length() > 0) {
                    Communications.openWebPage(client.getVerificationUrl(), null, null);
                }
            }
        } else if (id == :sitxReauth) {
            client.refreshAuthCode();
        } else if (id == :sitxRemove) {
            client.forgetAuthorization();
        } else if (id == :sitxBack) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        updateMenu();
    }

    function updateMenu() as Void {
        var client = app.getSitxClient();
        var organization = client.getOrganizationAddress();
        setMenuSubLabel(:sitxApiHost, organization.length() == 0 ? "Not set" : organization);
        setMenuSubLabel(:sitxEnabledToggle, toolToggleLabel(client.isTakEnabled()));
        setMenuSubLabel(:sitxGroup, client.getSelectedGroupName());
        setMenuSubLabel(:sitxStatus, client.statusText());
        var parentStatus = networkMenu.getItem(networkMenu.findItemById(:sitxDeviceApi));
        if (parentStatus != null) {
            parentStatus.setSubLabel(client.networkStatusLabel());
        }
        WatchUi.requestUpdate();
    }

    function setMenuSubLabel(id as Symbol, value as String) as Void {
        var item = menu.getItem(menu.findItemById(id));
        if (item != null) {
            item.setSubLabel(value);
        }
    }
}

class SitxGroupsDelegate extends WatchUi.Menu2InputDelegate {
    var app as StandaloneApp;
    var groupsMenu as WatchUi.Menu2;
    var sitxMenu as WatchUi.Menu2;
    var networkMenu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, groupMenu as WatchUi.Menu2, settingsMenu as WatchUi.Menu2, parentNetworkMenu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        app = application;
        groupsMenu = groupMenu;
        sitxMenu = settingsMenu;
        networkMenu = parentNetworkMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :sitxGroupBack || id == :sitxNoGroups) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (!(id instanceof Number)) { return; }
        var groups = app.getSitxClient().getGroups();
        var index = id as Number;
        if (index < 0 || index >= groups.size()) { return; }
        app.getSitxClient().setSelectedGroup(groups[index] as SitxGroup);
        var groupItem = sitxMenu.getItem(sitxMenu.findItemById(:sitxGroup));
        if (groupItem != null) { groupItem.setSubLabel(app.getSitxClient().getSelectedGroupName()); }
        var stateItem = sitxMenu.getItem(sitxMenu.findItemById(:sitxStatus));
        if (stateItem != null) { stateItem.setSubLabel(app.getSitxClient().statusText()); }
        var networkItem = networkMenu.getItem(networkMenu.findItemById(:sitxDeviceApi));
        if (networkItem != null) { networkItem.setSubLabel(app.getSitxClient().networkStatusLabel()); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class SitxSettingsTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var app as StandaloneApp;
    var menu as WatchUi.Menu2;

    function initialize(application as StandaloneApp, sitxMenu as WatchUi.Menu2) {
        TextPickerDelegate.initialize();
        app = application;
        menu = sitxMenu;
    }

    function onTextEntered(value as String, changed as Boolean) as Boolean {
        if (changed) {
            app.getSitxClient().setApiHost(value);
            var organization = app.getSitxClient().getOrganizationAddress();
            menu.getItem(menu.findItemById(:sitxApiHost)).setSubLabel(organization.length() == 0 ? "Not set" : organization);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() as Boolean {
        return true;
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
    var menu = createMenu(setting == :lowPressureThreshold ? "Low Pressure Threshold" : "High Pressure Threshold");
    if (setting == :lowPressureThreshold) {
        addAlertValues(menu, 800, 1100, 5);
    } else {
        addAlertValues(menu, 1000, 3000, 100);
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
        if (id == :bloodhoundCompass) {
            WatchUi.pushView(buildBloodhoundMenu(app), new BloodhoundDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :plugins) {
            var plugins = createMenu(WatchUi.loadResource(Rez.Strings.PluginsTitle));
            addMenuEntry(plugins, WatchUi.loadResource(Rez.Strings.DataSyncTitle), null, :dataSync);
            WatchUi.pushView(plugins, new ToolPreferencesDelegate(app), WatchUi.SLIDE_LEFT);
        } else if (id == :dataSync) {
            openDataSync(app);
        } else if (id == :clearPoints) {
            var confirmation = createMenu(WatchUi.loadResource(Rez.Strings.ConfirmClearPointsTitle));
            addMenuEntry(confirmation, WatchUi.loadResource(Rez.Strings.LabelClearPoints), null, :clear);
            addMenuEntry(confirmation, WatchUi.loadResource(Rez.Strings.LabelCancel), null, :cancel);
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
        if (id == :bloodhoundProximityVibrationToggle) {
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
            if (app.getMapView().clearDroppedPoints()) {
                WatchUi.showToast(app.text(Rez.Strings.TextOldPointsCleared), null);
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
