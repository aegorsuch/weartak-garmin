import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

class StandaloneApp extends Application.AppBase {
    private var view;
    private var takClient;
    private var chatMessages = [];
    private var sensorInfo;
    private var locationServices as Boolean = true;
    private var physiologicalAlertsEnabled as Boolean = true;
    private var highRestingHeartRate as Number = 120;
    private var highRestingWarningLength as Number = 5;
    private var highRestingAlertLength as Number = 10;
    private var lowRestingHeartRate as Number = 40;
    private var lowRestingWarningLength as Number = 5;
    private var lowRestingAlertLength as Number = 10;
    private var exertionWarningThreshold as Number = 80;
    private var exertionWarningLength as Number = 120;
    private var exertionAlertThreshold as Number = 90;
    private var exertionAlertLength as Number = 120;
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
        applyLocationServices();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    function setLocationServices(enabled as Boolean) as Void {
        locationServices = enabled;
        Application.Storage.setValue("locationServices", enabled);
        applyLocationServices();
    }

    function isLocationServicesEnabled() as Boolean {
        return locationServices;
    }

    function loadAlertSettings() as Void {
        var storedValue = Application.Storage.getValue("physiologicalAlertsEnabled");
        if (storedValue != null) {
            physiologicalAlertsEnabled = storedValue as Boolean;
        }
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
    }

    function storedNumber(key as String, fallback as Number) as Number {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as Number;
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
        WatchUi.requestUpdate();
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
        return view;
    }

    function getTakClient() as TakClient {
        return takClient;
    }

    function getInitialView() {
        var mapView = getMapView();
        mapView.setTakClient(takClient);
        return [mapView, new StandaloneMapDelegate(mapView, true, self)];
    }
}
