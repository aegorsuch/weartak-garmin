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

    function initialize() {
        Application.AppBase.initialize();
        takClient = new TakClient();
        takClient.incomingCotCallback = method(:onIncomingCot);
        takClient.incomingChatCallback = method(:onIncomingChat);
        var storedLocationServices = Application.Storage.getValue("locationServices");
        if (storedLocationServices != null) {
            locationServices = storedLocationServices as Boolean;
        }
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
