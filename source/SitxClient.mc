import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;

class SitxClient {
    const CLIENT_ID = "D4RTE81TJjccxlc8LPD7QQ";
    var apiHost as String = "";
    var accessToken as String? = null;
    var refreshToken as String? = null;
    var deviceCode as String? = null;
    var userCode as String = "";
    var pollInterval as Number = 5;
    var expiresAt as Number? = null;
    var status as Symbol = :unconfigured;
    var failureStatus as String = "";
    var statusCallback as Method? = null;
    var pollTimer as Timer.Timer? = null;

    function initialize() {
        var storedHost = storedString("sitxApiHost", "");
        apiHost = normalizeHost(storedHost);
        if (apiHost != storedHost) {
            Application.Storage.setValue("sitxApiHost", apiHost);
        }
        accessToken = storedNullableString("sitxAccessToken");
        refreshToken = storedNullableString("sitxRefreshToken");
        if (accessToken != null || refreshToken != null) {
            status = :authorized;
        }
    }

    function getApiHost() as String {
        return apiHost;
    }

    function setApiHost(value as String) as Void {
        var normalizedHost = normalizeHost(value);
        if (!apiHost.equals(normalizedHost)) {
            clearAuthorizationState();
        }
        apiHost = normalizedHost;
        Application.Storage.setValue("sitxApiHost", apiHost);
        status = :unconfigured;
        notifyStatusChanged();
    }

    function getUserCode() as String {
        return userCode;
    }

    function connect() as Void {
        failureStatus = "";
        if (apiHost.length() < 8 || !apiHost.substring(0, 8).equals("https://")) {
            failureStatus = apiHost.length() == 0 ? "Enter Sit(x) API host" : "Bad host: " + apiHost;
            status = :needsConfiguration;
            notifyStatusChanged();
            return;
        }
        if (refreshToken != null) {
            refreshAccessToken();
        } else {
            requestDeviceCode();
        }
    }

    function refreshAuthCode() as Void {
        failureStatus = "";
        if (apiHost.length() < 8 || !apiHost.substring(0, 8).equals("https://")) {
            failureStatus = apiHost.length() == 0 ? "Enter Sit(x) API host" : "Bad host: " + apiHost;
            status = :needsConfiguration;
            notifyStatusChanged();
            return;
        }
        stopPolling();
        deviceCode = null;
        userCode = "";
        expiresAt = null;
        requestDeviceCode();
    }

    function requestDeviceCode() as Void {
        status = :requestingCode;
        notifyStatusChanged();
        var settings = System.getDeviceSettings();
        var deviceId = settings.uniqueIdentifier;
        if (deviceId == null) {
            deviceId = settings.partNumber;
        }
        var callsign = "GARMIN";
        if (deviceId.length() > 8) {
            callsign += "-" + deviceId.substring(0, 8);
        }
        var scope = "role:org_user callsign:" + callsign + " device_name:" + deviceId + " device_id:" + deviceId;
        postJson("/api/v1/device/authorization/code", {
            "scope" => scope,
            "client_id" => CLIENT_ID
        }, method(:onDeviceCodeResponse));
    }

    function onDeviceCodeResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode < 200 || responseCode >= 300) {
            failureStatus = "Device auth HTTP " + responseCode.toString();
            status = :failed;
            notifyStatusChanged();
            return;
        }
        if (data == null || data.get("device_code") == null || data.get("user_code") == null) {
            failureStatus = "Invalid device auth response";
            status = :failed;
            notifyStatusChanged();
            return;
        }
        deviceCode = data.get("device_code").toString();
        userCode = data.get("user_code").toString();
        var intervalValue = data.get("interval");
        pollInterval = intervalValue instanceof Number ? intervalValue as Number : 5;
        var expiryValue = data.get("expires_in");
        expiresAt = Time.now().value() + (expiryValue instanceof Number ? expiryValue as Number : 600);
        status = :awaitingAuthorization;
        notifyStatusChanged();
        pollTimer = new Timer.Timer();
        pollTimer.start(method(:pollDeviceToken), pollInterval * 1000, true);
    }

    function pollDeviceToken() as Void {
        if (deviceCode == null || expiresAt == null || Time.now().value() >= expiresAt) {
            stopPolling();
            status = :expired;
            notifyStatusChanged();
            return;
        }
        post("/api/v1/device/authorization/token", {
            "client_id" => CLIENT_ID,
            "device_code" => deviceCode,
            "grant_type" => "urn:ietf:params:oauth:grant-type:device_code"
        }, method(:onDeviceTokenResponse));
    }

    function onDeviceTokenResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null && data.get("access_token") != null) {
            acceptTokens(data);
        } else if (responseCode != 400) {
            stopPolling();
            status = :failed;
            notifyStatusChanged();
        }
    }

    function refreshAccessToken() as Void {
        if (refreshToken == null) {
            requestDeviceCode();
            return;
        }
        status = :refreshing;
        notifyStatusChanged();
        post("/api/v1/refresh/token", {
            "client_id" => CLIENT_ID,
            "refresh_token" => refreshToken,
            "grant_type" => "refresh_token"
        }, method(:onRefreshResponse));
    }

    function onRefreshResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null && data.get("access_token") != null) {
            acceptTokens(data);
        } else {
            accessToken = null;
            Application.Storage.deleteValue("sitxAccessToken");
            refreshToken = null;
            Application.Storage.deleteValue("sitxRefreshToken");
            requestDeviceCode();
        }
    }

    function acceptTokens(data as Dictionary) as Void {
        stopPolling();
        accessToken = data.get("access_token").toString();
        if (data.get("refresh_token") != null) {
            refreshToken = data.get("refresh_token").toString();
        }
        Application.Storage.setValue("sitxAccessToken", accessToken);
        if (refreshToken != null) {
            Application.Storage.setValue("sitxRefreshToken", refreshToken);
        }
        deviceCode = null;
        userCode = "";
        verifyConnection();
    }

    function verifyConnection() as Void {
        status = :checkingConnection;
        notifyStatusChanged();
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {"Authorization" => "Bearer " + accessToken},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(apiHost + "/api/v1/myinfo", null, options, method(:onConnectionResponse));
    }

    function onConnectionResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            status = :connected;
        } else {
            failureStatus = "Profile HTTP " + responseCode.toString();
            status = :failed;
        }
        notifyStatusChanged();
    }

    function forgetAuthorization() as Void {
        clearAuthorizationState();
        status = :unconfigured;
        notifyStatusChanged();
    }

    function clearAuthorizationState() as Void {
        stopPolling();
        Application.Storage.deleteValue("sitxAccessToken");
        Application.Storage.deleteValue("sitxRefreshToken");
        accessToken = null;
        refreshToken = null;
        deviceCode = null;
        userCode = "";
    }

    function statusText() as String {
        if (status == :needsConfiguration) { return failureStatus.length() > 0 ? failureStatus : "Enter Sit(x) API host"; }
        if (status == :requestingCode) { return "Requesting device code"; }
        if (status == :awaitingAuthorization) { return "Waiting for authorization"; }
        if (status == :refreshing) { return "Refreshing token"; }
        if (status == :authorized) { return "Authorized; select Connect to verify"; }
        if (status == :checkingConnection) { return "Checking account"; }
        if (status == :connected) { return "Connected"; }
        if (status == :expired) { return "Code expired; retry"; }
        if (status == :failed) { return failureStatus.length() > 0 ? failureStatus : "Request failed"; }
        return "Not connected";
    }

    function post(path as String, parameters as Dictionary, callback as Method) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(apiHost + path, parameters, options, callback);
    }

    function postJson(path as String, parameters as Dictionary, callback as Method) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(apiHost + path, parameters, options, callback);
    }

    function normalizeHost(value as String) as String {
        var host = trimWhitespace(value).toLower();
        if (host.length() == 0) {
            return "";
        }
        if (host.length() >= 7 && host.substring(0, 7).equals("http://")) {
            host = "https://" + host.substring(7, host.length());
        } else if (host.length() < 8 || !host.substring(0, 8).equals("https://")) {
            host = "https://" + host;
        }
        return trimTrailingSlashes(host);
    }

    function trimWhitespace(value as String) as String {
        while (value.length() > 0 && isWhitespace(value.substring(0, 1))) {
            value = value.substring(1, value.length());
        }
        while (value.length() > 0 && isWhitespace(value.substring(value.length() - 1, value.length()))) {
            value = value.substring(0, value.length() - 1);
        }
        return value;
    }

    function isWhitespace(value as String) as Boolean {
        return value.equals(" ") || value.equals("\t") || value.equals("\r") || value.equals("\n");
    }

    function trimTrailingSlashes(value as String) as String {
        while (value.length() > 0 && value.substring(value.length() - 1, value.length()).equals("/")) {
            value = value.substring(0, value.length() - 1);
        }
        return value;
    }

    function storedString(key as String, defaultValue as String) as String {
        var value = Application.Storage.getValue(key);
        return value instanceof String ? value as String : defaultValue;
    }

    function storedNullableString(key as String) as String? {
        var value = Application.Storage.getValue(key);
        return value instanceof String ? value as String : null;
    }

    function stopPolling() as Void {
        if (pollTimer != null) {
            pollTimer.stop();
            pollTimer = null;
        }
    }

    function notifyStatusChanged() as Void {
        if (statusCallback != null) {
            statusCallback.invoke();
        }
    }
}