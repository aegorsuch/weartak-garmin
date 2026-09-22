import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class StandaloneApp extends Application.AppBase {
    const APP_VERSION = "5.8.0.2.1";

    private var view;
    private var takClient;
    private var versionTapCount as Number = 0;
    private var devModeEnabled as Boolean = false;
    private var verboseLoggingEnabled as Boolean = false;
    private var chatMessages = [];
    private var sensorInfo;
    private var exertionPercent as Number = 0;
    private var locationServices as Boolean = true;
    private var physiologicalAlertsEnabled as Boolean = false;
    private var batteryAlertsEnabled as Boolean = false;
    private var immersionAlertsEnabled as Boolean = false;
    private var lowPressureAlertsEnabled as Boolean = false;
    private var highPressureAlertsEnabled as Boolean = false;
    private var lowPressureThreshold as Number = 950;
    private var highPressureThreshold as Number = 2000;
    private var chatEnabled as Boolean = true;
    private var bloodhoundCompassEnabled as Boolean = true;
    private var bloodhoundProximityVibrationEnabled as Boolean = true;
    private var bloodhoundProximityRadius as Number = 50;
    private var bloodhoundProximityIntensity as String = "Single Burst";
    private var highRestingHeartRate as Number = 120;
    private var highRestingWarningLength as Number = 5;
    private var highRestingAlertLength as Number = 10;
    private var lowRestingHeartRate as Number = 40;
    private var lowRestingWarningLength as Number = 5;
    private var lowRestingAlertLength as Number = 10;
    private var highRestingWarningActive as Boolean = false;
    private var highRestingAlertActive as Boolean = false;
    private var lowRestingWarningActive as Boolean = false;
    private var lowRestingAlertActive as Boolean = false;
    private var lowPressureAlertActive as Boolean = false;
    private var highPressureAlertActive as Boolean = false;
    private var exertionWarningThreshold as Number = 80;
    private var exertionWarningLength as Number = 120;
    private var exertionAlertThreshold as Number = 90;
    private var exertionAlertLength as Number = 120;
    private var exertionWarningActive as Boolean = false;
    private var exertionAlertActive as Boolean = false;
    private var birthYear as Number = 1990;
    private var height as Number = 68;
    private var weight as Number = 155;
    private var sex as String = "Not Set";
    private var bloodType as String = "Unknown";
    private var userType as String = "N/A";
    private var allergies as Array = ["N/A"];
    private var uniformWaistSize as Number = 32;
    private var strideLength as Number = 30;
    private var uniformPantsLength as Number = 32;
    private var loadoutWeight as Number = 72;

    function initialize() {
        Application.AppBase.initialize();
        takClient = new TakClient();
        takClient.incomingCotCallback = method(:onIncomingCot);
        takClient.incomingChatCallback = method(:onIncomingChat);
        var storedLocationServices = Application.Storage.getValue("locationServices");
        if (storedLocationServices != null) {
            locationServices = storedLocationServices as Boolean;
        }
        loadAlertSettings();
        takClient.setVerboseLogging(verboseLoggingEnabled);
        applyLocationServices();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    function getAppVersion() as String {
        return APP_VERSION;
    }

    // Returns true the moment the 7th consecutive tap unlocks dev mode.
    function registerVersionTap() as Boolean {
        versionTapCount += 1;
        if (versionTapCount < 7) {
            return false;
        }
        versionTapCount = 0;
        if (devModeEnabled) {
            return false;
        }
        devModeEnabled = true;
        Application.Storage.setValue("devModeEnabled", true);
        return true;
    }

    function resetVersionTapCount() as Void {
        versionTapCount = 0;
    }

    function isDevModeEnabled() as Boolean {
        return devModeEnabled;
    }

    function isVerboseLoggingEnabled() as Boolean {
        return verboseLoggingEnabled;
    }

    function setVerboseLoggingEnabled(enabled as Boolean) as Void {
        verboseLoggingEnabled = enabled;
        Application.Storage.setValue("verboseLoggingEnabled", enabled);
        takClient.setVerboseLogging(enabled);
    }

    function setLocationServices(enabled as Boolean) as Void {
        locationServices = enabled;
        Application.Storage.setValue("locationServices", enabled);
        applyLocationServices();
    }

    function isLocationServicesEnabled() as Boolean {
        return locationServices;
    }

    const TEXT_RESOURCE_IDS = {
        :map => Rez.Strings.TextMap,
        :settings => Rez.Strings.TextSettings,
        :clear2525d => Rez.Strings.TextClear2525d,
        :environment => Rez.Strings.TextEnvironment,
        :exit => Rez.Strings.TextExit,
        :manualAlert => Rez.Strings.TextManualAlert,
        :clearManualAlert => Rez.Strings.TextClearManualAlert,
        :gateRunner => Rez.Strings.TextGateRunner,
        :gunshot => Rez.Strings.TextGunshot,
        :gunshotInjury => Rez.Strings.TextGunshotInjury,
        :injury => Rez.Strings.TextInjury,
        :uas => Rez.Strings.TextUas,
        :vehicle => Rez.Strings.TextVehicle,
        :pointTitle => Rez.Strings.TextPointTitle,
        :bloodhound => Rez.Strings.TextBloodhound,
        :stopBloodhound => Rez.Strings.TextStopBloodhound,
        :coordinates => Rez.Strings.TextCoordinates,
        :latLon => Rez.Strings.TextLatLon,
        :mgrs => Rez.Strings.TextMgrs,
        :setTitle => Rez.Strings.TextSetTitle,
        :setRemark => Rez.Strings.TextSetRemark,
        :setType => Rez.Strings.TextSetType,
        :delete => Rez.Strings.TextDelete,
        :self => Rez.Strings.TextSelf,
        :proximity => Rez.Strings.TextProximity,
        :cancelBloodhound => Rez.Strings.TextStopBloodhound,
        :takConnect => Rez.Strings.TextTakConnect,
        :myUserMetrics => Rez.Strings.TextMyUserMetrics,
        :medicalProfile => Rez.Strings.TextMedicalProfile,
        :gaitTracking => Rez.Strings.TextGaitTracking,
        :birthYear => Rez.Strings.TextBirthYear,
        :height => Rez.Strings.TextHeight,
        :weight => Rez.Strings.TextWeight,
        :sex => Rez.Strings.TextSex,
        :bloodType => Rez.Strings.TextBloodType,
        :allergies => Rez.Strings.TextAllergies,
        :userType => Rez.Strings.TextUserType,
        :uniformWaistSize => Rez.Strings.TextUniformWaistSize,
        :strideLength => Rez.Strings.TextStrideLength,
        :uniformPantsLength => Rez.Strings.TextUniformPantsLength,
        :loadoutWeight => Rez.Strings.TextLoadoutWeight,
        :proximityVibration => Rez.Strings.TextProximityVibration,
        :proximityRadius => Rez.Strings.TextProximityRadius,
        :proximityIntensity => Rez.Strings.TextProximityIntensity,
        :allergyEnabled => Rez.Strings.TextAllergyEnabled,
        :allergyDisabled => Rez.Strings.TextAllergyDisabled,
        :oldPointsCleared => Rez.Strings.TextOldPointsCleared,
        :active => Rez.Strings.TextActive,
        :unknownPoint => Rez.Strings.TextUnknownPoint,
        :friendlyPoint => Rez.Strings.TextFriendlyPoint,
        :hostilePoint => Rez.Strings.TextHostilePoint,
        :obstaclePoint => Rez.Strings.TextObstaclePoint,
        :waitingForLocation => Rez.Strings.TextWaitingForLocation,
        :highHrThreshold => Rez.Strings.TextHighHrThreshold,
        :lowHrThreshold => Rez.Strings.TextLowHrThreshold,
        :navigationTitle => Rez.Strings.TextBloodhoundCompass,
        :proximityRadiusTitle => Rez.Strings.TextProximityRadius,
        :proximityIntensityTitle => Rez.Strings.TextProximityIntensity,
        :range => Rez.Strings.TextRange,
        :bearing => Rez.Strings.TextBearing,
        :noBloodhoundTarget => Rez.Strings.TextNoBloodhoundTarget,
        :tapMapPoint => Rez.Strings.TextTapMapPoint,
        :physiology => Rez.Strings.TextPhysiology,
        :devicePreferences => Rez.Strings.TextDevicePreferences,
        :networkPreferences => Rez.Strings.TextNetworkPreferences,
        :alertingPreferences => Rez.Strings.TextAlertingPreferences,
        :toolPreferences => Rez.Strings.TextToolPreferences,
        :locationServices => Rez.Strings.TextLocationServices,
        :userMetrics => Rez.Strings.TextUserMetrics,
        :physiologicalAlerts => Rez.Strings.TextPhysiologicalAlerts,
        :environmentalAlerts => Rez.Strings.TextEnvironmentalAlerts,
        :batteryAlerts => Rez.Strings.TextBatteryAlerts,
        :immersionAlerts => Rez.Strings.TextImmersionAlerts,
        :atmPressureAlerts => Rez.Strings.TextAtmPressureAlerts,
        :restingHeartRateAlerts => Rez.Strings.TextRestingHeartRateAlerts,
        :exertionAlerts => Rez.Strings.TextExertionAlerts,
        :chat => Rez.Strings.TextChat,
        :bloodhoundCompass => Rez.Strings.TextBloodhoundCompass,
        :clearPointsMain => Rez.Strings.TextClearPointsMain,
        :dropPoint => Rez.Strings.TextDropPoint,
        :clearPointsPrompt => Rez.Strings.TextClearPointsPrompt,
        :clearPointsAction => Rez.Strings.TextClearPointsMain,
        :pointDropped => Rez.Strings.TextPointDropped,
        :locationUnavailable => Rez.Strings.TextLocationUnavailable,
        :cancel => Rez.Strings.TextCancel,
        :atmPressureTitle => Rez.Strings.TextAtmPressureAlerts,
        :lowPressureAlert => Rez.Strings.TextLowPressureAlert,
        :highPressureAlert => Rez.Strings.TextHighPressureAlert,
        :pressureThreshold => Rez.Strings.TextPressureThreshold,
        :restingHeartRateTitle => Rez.Strings.TextRestingHeartRateAlerts,
        :highRestingHeartRate => Rez.Strings.TextHighRestingHeartRate,
        :lowRestingHeartRate => Rez.Strings.TextLowRestingHeartRate,
        :warningLength => Rez.Strings.TextWarningLength,
        :alertLength => Rez.Strings.TextAlertLength,
        :exertionTitle => Rez.Strings.TextExertionAlerts,
        :warningThreshold => Rez.Strings.TextWarningThreshold,
        :alertThreshold => Rez.Strings.TextAlertThreshold,
        :heartRateThreshold => Rez.Strings.TextHeartRateThreshold,
        :alertDuration => Rez.Strings.TextAlertDuration,
        :setTypeTitle => Rez.Strings.TextSetType,
        :friendly => Rez.Strings.TextFriendlyPoint,
        :hostile => Rez.Strings.TextHostilePoint,
        :obstacle => Rez.Strings.TextObstaclePoint,
        :selected => Rez.Strings.TextSelected,
        :on => Rez.Strings.TextOn,
        :off => Rez.Strings.TextOff,
        :altitude => Rez.Strings.TextAltitude,
        :pressure => Rez.Strings.TextPressure,
        :temperature => Rez.Strings.TextTemperature,
        :physiologyView => Rez.Strings.TextPhysiologyView,
        :exertion => Rez.Strings.TextExertion,
        :heartRate => Rez.Strings.TextHeartRate,
        :unavailable => Rez.Strings.TextUnavailable,
    } as Dictionary<Symbol, ResourceId>;

    function text(key as Symbol) as String {
        var resourceId = TEXT_RESOURCE_IDS[key];
        if (resourceId != null) {
            return WatchUi.loadResource(resourceId) as String;
        }
        return key.toString();
    }

    function alertTypeLabel(alertType as String) as String {
        if (alertType.equals("Gate Runner")) { return text(:gateRunner); }
        else if (alertType.equals("Gunshot")) { return text(:gunshot); }
        else if (alertType.equals("Gunshot Injury")) { return text(:gunshotInjury); }
        else if (alertType.equals("Injury")) { return text(:injury); }
        else if (alertType.equals("UAS")) { return text(:uas); }
        else if (alertType.equals("Vehicle")) { return text(:vehicle); }
        return alertType;
    }

    function loadAlertSettings() as Void {
        var storedValue = Application.Storage.getValue("physiologicalAlertsEnabled");
        if (storedValue != null) {
            physiologicalAlertsEnabled = storedValue as Boolean;
        }
        batteryAlertsEnabled = storedBoolean("batteryAlertsEnabled", batteryAlertsEnabled);
        immersionAlertsEnabled = storedBoolean("immersionAlertsEnabled", immersionAlertsEnabled);
        lowPressureAlertsEnabled = storedBoolean("lowPressureAlertsEnabled", lowPressureAlertsEnabled);
        highPressureAlertsEnabled = storedBoolean("highPressureAlertsEnabled", highPressureAlertsEnabled);
        lowPressureThreshold = storedNumber("lowPressureThreshold", lowPressureThreshold);
        highPressureThreshold = storedNumber("highPressureThreshold", highPressureThreshold);
        chatEnabled = storedBoolean("chatEnabled", chatEnabled);
        bloodhoundCompassEnabled = storedBoolean("bloodhoundCompassEnabled", bloodhoundCompassEnabled);
        bloodhoundProximityVibrationEnabled = storedBoolean("bloodhoundProximityVibrationEnabled", bloodhoundProximityVibrationEnabled);
        bloodhoundProximityRadius = storedNumber("bloodhoundProximityRadius", bloodhoundProximityRadius);
        bloodhoundProximityIntensity = storedString("bloodhoundProximityIntensity", bloodhoundProximityIntensity);
        highRestingHeartRate = storedNumber("highRestingHeartRate", highRestingHeartRate);
        highRestingWarningLength = storedNumber("highRestingWarningLength", highRestingWarningLength);
        highRestingAlertLength = storedNumber("highRestingAlertLength", highRestingAlertLength);
        lowRestingHeartRate = storedNumber("lowRestingHeartRate", lowRestingHeartRate);
        lowRestingWarningLength = storedNumber("lowRestingWarningLength", lowRestingWarningLength);
        lowRestingAlertLength = storedNumber("lowRestingAlertLength", lowRestingAlertLength);
        exertionWarningThreshold = storedNumber("exertionWarningThreshold", exertionWarningThreshold);
        exertionWarningLength = storedNumber("exertionWarningLength", exertionWarningLength);
        exertionAlertThreshold = storedNumber("exertionAlertThreshold", exertionAlertThreshold);
        exertionAlertLength = storedNumber("exertionAlertLength", exertionAlertLength);
        birthYear = storedNumber("birthYear", birthYear);
        height = storedNumber("height", height);
        weight = storedNumber("weight", weight);
        sex = storedString("sex", sex);
        bloodType = storedString("bloodType", bloodType);
        userType = storedString("userType", userType);
        var storedAllergies = Application.Storage.getValue("allergies");
        if (storedAllergies != null) {
            allergies = storedAllergies as Array;
        }
        uniformWaistSize = storedNumber("uniformWaistSize", uniformWaistSize);
        strideLength = storedNumber("strideLength", strideLength);
        uniformPantsLength = storedNumber("uniformPantsLength", uniformPantsLength);
        loadoutWeight = storedNumber("loadoutWeight", loadoutWeight);
        devModeEnabled = storedBoolean("devModeEnabled", devModeEnabled);
        verboseLoggingEnabled = storedBoolean("verboseLoggingEnabled", verboseLoggingEnabled);
        ensureValidAlertRange();
        ensureValidUserMetrics();
    }

    function ensureValidAlertRange() as Void {
        if (lowPressureThreshold < 800) {
            lowPressureThreshold = 950;
        } else if (lowPressureThreshold > 1100) {
            lowPressureThreshold = 1100;
        }
        if (highPressureThreshold < 1000) {
            highPressureThreshold = 2000;
        } else if (highPressureThreshold > 3000) {
            highPressureThreshold = 3000;
        }
        if (highPressureThreshold < lowPressureThreshold) {
            highPressureThreshold = lowPressureThreshold + 25;
        }

        if (highRestingHeartRate < 80) {
            highRestingHeartRate = 120;
        } else if (highRestingHeartRate > 220) {
            highRestingHeartRate = 220;
        }
        if (lowRestingHeartRate < 25) {
            lowRestingHeartRate = 40;
        } else if (lowRestingHeartRate > 110) {
            lowRestingHeartRate = 110;
        }
        if (highRestingHeartRate <= lowRestingHeartRate) {
            highRestingHeartRate = lowRestingHeartRate + 20;
        }

        if (exertionWarningThreshold < 50) {
            exertionWarningThreshold = 80;
        } else if (exertionWarningThreshold > 100) {
            exertionWarningThreshold = 100;
        }
        if (exertionAlertThreshold < 50) {
            exertionAlertThreshold = 90;
        } else if (exertionAlertThreshold > 100) {
            exertionAlertThreshold = 100;
        }
        if (exertionAlertThreshold < exertionWarningThreshold) {
            exertionAlertThreshold = exertionWarningThreshold + 5;
            if (exertionAlertThreshold > 100) {
                exertionAlertThreshold = 100;
            }
        }
    }

    function ensureValidUserMetrics() as Void {
        if (birthYear < 1920 || birthYear > 2026) {
            birthYear = 1990;
        }
        if (height < 48 || height > 84) {
            height = 68;
        }
        if (weight < 80 || weight > 320) {
            weight = 155;
        }
        if (sex == null || sex.equals("")) {
            sex = "Not Set";
        }
        if (bloodType == null || bloodType.equals("")) {
            bloodType = "Unknown";
        }
        if (userType == null || userType.equals("")) {
            userType = "N/A";
        }
        if (allergies == null || allergies.size() == 0) {
            allergies = ["N/A"];
        }
        if (uniformWaistSize < 24 || uniformWaistSize > 60) {
            uniformWaistSize = 32;
        }
        if (strideLength < 20 || strideLength > 45) {
            strideLength = 30;
        }
        if (uniformPantsLength < 24 || uniformPantsLength > 60) {
            uniformPantsLength = 32;
        }
        if (loadoutWeight < 10 || loadoutWeight > 150) {
            loadoutWeight = 72;
        }
    }

    function storedNumber(key as String, fallback as Number) as Number {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as Number;
    }

    function storedBoolean(key as String, fallback as Boolean) as Boolean {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as Boolean;
    }

    function storedString(key as String, fallback as String) as String {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as String;
    }

    function isPhysiologicalAlertsEnabled() as Boolean {
        return physiologicalAlertsEnabled;
    }

    function setPhysiologicalAlertsEnabled(enabled as Boolean) as Void {
        physiologicalAlertsEnabled = enabled;
        Application.Storage.setValue("physiologicalAlertsEnabled", enabled);
    }

    function isBatteryAlertsEnabled() as Boolean {
        return batteryAlertsEnabled;
    }

    function setBatteryAlertsEnabled(enabled as Boolean) as Void {
        batteryAlertsEnabled = enabled;
        Application.Storage.setValue("batteryAlertsEnabled", enabled);
    }

    function isImmersionAlertsEnabled() as Boolean {
        return immersionAlertsEnabled;
    }

    function setImmersionAlertsEnabled(enabled as Boolean) as Void {
        immersionAlertsEnabled = enabled;
        Application.Storage.setValue("immersionAlertsEnabled", enabled);
    }

    function isLowPressureAlertsEnabled() as Boolean {
        return lowPressureAlertsEnabled;
    }

    function setLowPressureAlertsEnabled(enabled as Boolean) as Void {
        lowPressureAlertsEnabled = enabled;
        Application.Storage.setValue("lowPressureAlertsEnabled", enabled);
    }

    function isHighPressureAlertsEnabled() as Boolean {
        return highPressureAlertsEnabled;
    }

    function setHighPressureAlertsEnabled(enabled as Boolean) as Void {
        highPressureAlertsEnabled = enabled;
        Application.Storage.setValue("highPressureAlertsEnabled", enabled);
    }

    function isChatEnabled() as Boolean {
        return chatEnabled;
    }

    function setChatEnabled(enabled as Boolean) as Void {
        chatEnabled = enabled;
        Application.Storage.setValue("chatEnabled", enabled);
    }

    function isBloodhoundCompassEnabled() as Boolean {
        return bloodhoundCompassEnabled;
    }

    function setBloodhoundCompassEnabled(enabled as Boolean) as Void {
        bloodhoundCompassEnabled = enabled;
        Application.Storage.setValue("bloodhoundCompassEnabled", enabled);
    }

    function isBloodhoundProximityVibrationEnabled() as Boolean {
        return bloodhoundProximityVibrationEnabled;
    }

    function setBloodhoundProximityVibrationEnabled(enabled as Boolean) as Void {
        bloodhoundProximityVibrationEnabled = enabled;
        Application.Storage.setValue("bloodhoundProximityVibrationEnabled", enabled);
    }

    function getBloodhoundProximityRadius() as Number {
        return bloodhoundProximityRadius;
    }

    function setBloodhoundProximityRadius(radius as Number) as Void {
        bloodhoundProximityRadius = radius;
        Application.Storage.setValue("bloodhoundProximityRadius", radius);
    }

    function getBloodhoundProximityIntensity() as String {
        return bloodhoundProximityIntensity;
    }

    function setBloodhoundProximityIntensity(intensity as String) as Void {
        bloodhoundProximityIntensity = intensity;
        Application.Storage.setValue("bloodhoundProximityIntensity", intensity);
    }

    function getAlertSetting(setting as Symbol) as Number {
        if (setting == :highThreshold) {
            return highRestingHeartRate;
        } else if (setting == :highWarning) {
            return highRestingWarningLength;
        } else if (setting == :highAlert) {
            return highRestingAlertLength;
        } else if (setting == :lowThreshold) {
            return lowRestingHeartRate;
        } else if (setting == :lowWarning) {
            return lowRestingWarningLength;
        } else if (setting == :lowAlert) {
            return lowRestingAlertLength;
        } else if (setting == :exertionWarningThreshold) {
            return exertionWarningThreshold;
        } else if (setting == :exertionWarningLength) {
            return exertionWarningLength;
        } else if (setting == :exertionAlertThreshold) {
            return exertionAlertThreshold;
        } else if (setting == :lowPressureThreshold) {
            return lowPressureThreshold;
        } else if (setting == :highPressureThreshold) {
            return highPressureThreshold;
        }
        return exertionAlertLength;
    }

    function setAlertSetting(setting as Symbol, value as Number) as Void {
        var key = "exertionAlertLength";
        if (setting == :highThreshold) {
            highRestingHeartRate = value;
            key = "highRestingHeartRate";
        } else if (setting == :highWarning) {
            highRestingWarningLength = value;
            key = "highRestingWarningLength";
        } else if (setting == :highAlert) {
            highRestingAlertLength = value;
            key = "highRestingAlertLength";
        } else if (setting == :lowThreshold) {
            lowRestingHeartRate = value;
            key = "lowRestingHeartRate";
        } else if (setting == :lowWarning) {
            lowRestingWarningLength = value;
            key = "lowRestingWarningLength";
        } else if (setting == :lowAlert) {
            lowRestingAlertLength = value;
            key = "lowRestingAlertLength";
        } else if (setting == :exertionWarningThreshold) {
            exertionWarningThreshold = value;
            key = "exertionWarningThreshold";
        } else if (setting == :exertionWarningLength) {
            exertionWarningLength = value;
            key = "exertionWarningLength";
        } else if (setting == :exertionAlertThreshold) {
            exertionAlertThreshold = value;
            key = "exertionAlertThreshold";
        } else if (setting == :lowPressureThreshold) {
            lowPressureThreshold = value;
            key = "lowPressureThreshold";
        } else if (setting == :highPressureThreshold) {
            highPressureThreshold = value;
            key = "highPressureThreshold";
        } else {
            exertionAlertLength = value;
        }
        Application.Storage.setValue(key, value);
    }

    function getUserMetric(setting as Symbol) {
        if (setting == :birthYear) {
            return birthYear;
        } else if (setting == :height) {
            return height;
        } else if (setting == :weight) {
            return weight;
        } else if (setting == :sex) {
            return sex;
        } else if (setting == :bloodType) {
            return bloodType;
        } else if (setting == :uniformWaistSize) {
            return uniformWaistSize;
        } else if (setting == :strideLength) {
            return strideLength;
        } else if (setting == :uniformPantsLength) {
            return uniformPantsLength;
        } else if (setting == :loadoutWeight) {
            return loadoutWeight;
        }
        return userType;
    }

    function setUserMetric(setting as Symbol, value) as Void {
        var key = "userType";
        if (setting == :birthYear) {
            birthYear = value as Number;
            key = "birthYear";
        } else if (setting == :height) {
            height = value as Number;
            key = "height";
        } else if (setting == :weight) {
            weight = value as Number;
            key = "weight";
        } else if (setting == :sex) {
            sex = value as String;
            key = "sex";
        } else if (setting == :bloodType) {
            bloodType = value as String;
            key = "bloodType";
        } else if (setting == :uniformWaistSize) {
            uniformWaistSize = value as Number;
            key = "uniformWaistSize";
        } else if (setting == :strideLength) {
            strideLength = value as Number;
            key = "strideLength";
        } else if (setting == :uniformPantsLength) {
            uniformPantsLength = value as Number;
            key = "uniformPantsLength";
        } else if (setting == :loadoutWeight) {
            loadoutWeight = value as Number;
            key = "loadoutWeight";
        } else {
            userType = value as String;
        }
        Application.Storage.setValue(key, value);
    }

    function isAllergySelected(allergy as String) as Boolean {
        for (var i = 0; i < allergies.size(); i++) {
            if (allergies[i].equals(allergy)) {
                return true;
            }
        }
        return false;
    }

    function toggleAllergy(allergy as String) as Void {
        if (allergy.equals("N/A")) {
            allergies = ["N/A"];
        } else if (isAllergySelected(allergy)) {
            removeAllergy(allergy);
            if (allergies.size() == 0) {
                allergies = ["N/A"];
            }
        } else {
            removeAllergy("N/A");
            allergies.add(allergy);
        }
        Application.Storage.setValue("allergies", allergies);
    }

    function removeAllergy(allergy as String) as Void {
        for (var i = allergies.size() - 1; i >= 0; i--) {
            if (allergies[i].equals(allergy)) {
                allergies.remove(i);
            }
        }
    }

    function allergiesLabel() as String {
        return allergies.size() == 1 && isAllergySelected("N/A") ? "N/A" : allergies.size().toString() + " selected";
    }

    function applyLocationServices() as Void {
        if (locationServices) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function onStart(params) {
    }

    function onPosition(info as Toybox.Position.Info) as Void {
        if (!locationServices) {
            return;
        }
        takClient.updatePosition(info);
        if (view != null) {
            view.updatePosition(info);
        }
    }

    function onSensor(info as Sensor.Info) as Void {
        sensorInfo = info;
        exertionPercent = calculateExertionPercent(info.heartRate);
        evaluateExertionAlerts();
        evaluateRestingHeartRateAlerts();
        evaluatePressureAlerts();
        WatchUi.requestUpdate();
    }

    function evaluateRestingHeartRateAlerts() as Void {
        if (!physiologicalAlertsEnabled || sensorInfo.heartRate == null) {
            return;
        }
        var heartRate = sensorInfo.heartRate;
        if (heartRate >= highRestingHeartRate) {
            lowRestingWarningActive = false;
            lowRestingAlertActive = false;
            if (!highRestingWarningActive) {
                highRestingWarningActive = true;
                notifySensorAlert("High HR warning", highRestingWarningLength, 50);
            }
            if (!highRestingAlertActive) {
                highRestingAlertActive = true;
                queueTakAlert("High resting heart rate", heartRate);
            }
        } else if (heartRate <= lowRestingHeartRate) {
            highRestingWarningActive = false;
            highRestingAlertActive = false;
            if (!lowRestingWarningActive) {
                lowRestingWarningActive = true;
                notifySensorAlert("Low HR warning", lowRestingWarningLength, 50);
            }
            if (!lowRestingAlertActive) {
                lowRestingAlertActive = true;
                queueTakAlert("Low resting heart rate", heartRate);
            }
        } else {
            highRestingWarningActive = false;
            highRestingAlertActive = false;
            lowRestingWarningActive = false;
            lowRestingAlertActive = false;
        }
    }

    function evaluatePressureAlerts() as Void {
        if (sensorInfo.pressure == null) {
            return;
        }
        var pressureHpa = sensorInfo.pressure / 100;
        if (lowPressureAlertsEnabled && pressureHpa <= lowPressureThreshold) {
            highPressureAlertActive = false;
            if (!lowPressureAlertActive) {
                lowPressureAlertActive = true;
                notifySensorAlert("Low pressure warning", 1, 50);
                queueTakAlert("Low atmospheric pressure", pressureHpa);
            }
        } else if (highPressureAlertsEnabled && pressureHpa >= highPressureThreshold) {
            lowPressureAlertActive = false;
            if (!highPressureAlertActive) {
                highPressureAlertActive = true;
                notifySensorAlert("High pressure warning", 1, 50);
                queueTakAlert("High atmospheric pressure", pressureHpa);
            }
        } else {
            lowPressureAlertActive = false;
            highPressureAlertActive = false;
        }
    }

    function notifySensorAlert(label as String, durationMinutes as Number, intensity as Number) as Void {
        var durationMilliseconds = durationMinutes * 1000;
        if (durationMilliseconds < 250) {
            durationMilliseconds = 250;
        } else if (durationMilliseconds > 10000) {
            durationMilliseconds = 10000;
        }
        Attention.vibrate([new Attention.VibeProfile(intensity, durationMilliseconds)]);
        WatchUi.showToast(label, null);
    }

    function queueTakAlert(label as String, value as Number) as Void {
        // Full alert relay will be connected when the ATAK device channel is available.
    }

    function evaluateExertionAlerts() as Void {
        if (!physiologicalAlertsEnabled) {
            return;
        }
        if (exertionPercent >= exertionAlertThreshold) {
            if (!exertionAlertActive) {
                exertionAlertActive = true;
                exertionWarningActive = true;
                notifyExertion("Exertion alert", exertionAlertLength, 100);
            }
        } else if (exertionPercent >= exertionWarningThreshold) {
            exertionAlertActive = false;
            if (!exertionWarningActive) {
                exertionWarningActive = true;
                notifyExertion("Exertion warning", exertionWarningLength, 50);
            }
        } else {
            exertionWarningActive = false;
            exertionAlertActive = false;
        }
    }

    function notifyExertion(label as String, durationSeconds as Number, intensity as Number) as Void {
        var durationMilliseconds = durationSeconds * 1000;
        if (durationMilliseconds < 250) {
            durationMilliseconds = 250;
        } else if (durationMilliseconds > 10000) {
            durationMilliseconds = 10000;
        }
        Attention.vibrate([new Attention.VibeProfile(intensity, durationMilliseconds)]);
        WatchUi.showToast(label + " (" + exertionPercent.toNumber().toString() + "%)", null);
    }

    function calculateExertionPercent(heartRate) as Number {
        if (heartRate == null) {
            return 0;
        }
        var currentYear = Gregorian.info(Time.now(), Time.FORMAT_SHORT).year;
        var age = currentYear - birthYear;
        if (age < 0) {
            age = 0;
        }
        var predictedMaxHeartRate = 208 - (0.7 * age);
        return (heartRate / predictedMaxHeartRate) * 100;
    }

    function getExertionPercent() as Number {
        return exertionPercent;
    }

    function getSensorInfo() as Sensor.Info? {
        return sensorInfo;
    }

    function onIncomingCot(uid, latitude, longitude, type) as Void {
        getMapView().updateIncomingCot(uid, latitude, longitude, type);
    }

    function onIncomingChat(message as Dictionary) as Void {
        chatMessages.add(message);
        if (chatMessages.size() > 20) {
            chatMessages.remove(0);
        }
    }

    function getChatMessages() as Array {
        return chatMessages;
    }

    function sendChatReply(replyTo as String, text as String) as Void {
        takClient.sendChatReply(replyTo, text);
    }

    function getMapView() as StandaloneMapView {
        if (view == null) {
            view = new StandaloneMapView();
            view.setTakClient(takClient);
        }
        view.setApplication(self);
        return view;
    }

    function getTakClient() as TakClient {
        return takClient;
    }

    function getInitialView() {
        return [buildMainMenu(self), new MainMenuDelegate(self)];
    }
}
