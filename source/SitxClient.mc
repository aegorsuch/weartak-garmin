import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;

class SitxGroup {
    var flowTag as String;
    var name as String;

    function initialize(tag as String, groupName as String) {
        flowTag = tag;
        name = groupName;
    }
}

class SitxClient {
    const CLIENT_ID = "D4RTE81TJjccxlc8LPD7QQ";
    var apiHost as String = "";
    var accessToken as String? = null;
    var refreshToken as String? = null;
    var selectedGroupFlowTag as String = "";
    var selectedGroupName as String = "";
    var groups as Array<SitxGroup> = [];
    var takEnabled as Boolean = false;
    var verificationUrl as String = "";
    var groupEndpoint as String? = null;
    var pollRequestPending as Boolean = false;
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
        selectedGroupFlowTag = storedString("sitxGroupFlowTag", "");
        selectedGroupName = storedString("sitxGroupName", "");
        var enabledValue = Application.Storage.getValue("sitxEnabled");
        takEnabled = enabledValue instanceof Boolean ? enabledValue as Boolean : false;
        if (accessToken != null || refreshToken != null) {
            status = :authorized;
        }
        if (!takEnabled) { status = :off; }
    }

    function getApiHost() as String {
        return apiHost;
    }

    function getOrganizationAddress() as String {
        var address = apiHost;
        if (address.length() >= 8 && address.substring(0, 8).equals("https://")) {
            address = address.substring(8, address.length());
        }
        if (hasSuffix(address, ".sitx.io")) {
            address = address.substring(0, address.length() - 8);
        }
        return address;
    }

    function isTakEnabled() as Boolean {
        return takEnabled;
    }

    function getGroups() as Array<SitxGroup> {
        return groups;
    }

    function getSelectedGroupFlowTag() as String {
        return selectedGroupFlowTag;
    }

    function getSelectedGroupName() as String {
        return selectedGroupName.length() == 0 ? "Not selected" : selectedGroupName;
    }

    function getVerificationUrl() as String {
        return verificationUrl;
    }

    function getUserCode() as String {
        return userCode;
    }

    function setApiHost(value as String) as Void {
        var normalizedHost = normalizeHost(value);
        if (!apiHost.equals(normalizedHost)) {
            clearAuthorizationState();
            clearGroupSelection();
        }
        apiHost = normalizedHost;
        Application.Storage.setValue("sitxApiHost", apiHost);
        status = takEnabled ? :unconfigured : :off;
        notifyStatusChanged();
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

    function setTakEnabled(enabled as Boolean) as Void {
        takEnabled = enabled;
        Application.Storage.setValue("sitxEnabled", enabled);
        if (!enabled) {
            stopPolling();
            pollRequestPending = false;
            status = :off;
            notifyStatusChanged();
            return;
        }
        connect();
    }

    function refreshAuthCode() as Void {
        clearAuthorizationState();
        clearGroupSelection();
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
        verificationUrl = "";
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
        verificationUrl = data.get("verification_uri") != null ? data.get("verification_uri").toString()
            : data.get("verification_url") != null ? data.get("verification_url").toString() : "";
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
        if (!takEnabled || pollRequestPending) { return; }
        if (deviceCode == null || expiresAt == null || Time.now().value() >= expiresAt) {
            stopPolling();
            status = :expired;
            notifyStatusChanged();
            return;
        }
        pollRequestPending = true;
        post("/api/v1/device/authorization/token", {
            "client_id" => CLIENT_ID,
            "device_code" => deviceCode,
            "grant_type" => "urn:ietf:params:oauth:grant-type:device_code"
        }, method(:onDeviceTokenResponse));
    }

    function onDeviceTokenResponse(responseCode as Number, data as Dictionary?) as Void {
        pollRequestPending = false;
        var error = data != null && data.get("error") != null ? data.get("error").toString() : "";
        if (responseCode == 200 && data != null && data.get("access_token") != null) {
            acceptTokens(data);
        } else if (error.equals("authorization_pending")) {
            return;
        } else if (error.equals("slow_down")) {
            pollInterval += 5;
            stopPolling();
            pollTimer = new Timer.Timer();
            pollTimer.start(method(:pollDeviceToken), pollInterval * 1000, true);
        } else if (error.equals("expired_token") || error.equals("access_denied")) {
            stopPolling();
            status = error.equals("expired_token") ? :expired : :failed;
            failureStatus = error.equals("access_denied") ? "Device authorization denied" : "";
            notifyStatusChanged();
        } else if (responseCode != 400) {
            stopPolling();
            failureStatus = "Device token HTTP " + responseCode.toString();
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
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Authorization" => "Bearer " + refreshToken,
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(apiHost + "/api/v1/refresh/token", null, options, method(:onRefreshResponse));
    }

    function onRefreshResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            if (data != null && data.get("refresh_token") != null) {
                refreshToken = data.get("refresh_token").toString();
                Application.Storage.setValue("sitxRefreshToken", refreshToken);
            }
            fetchGroups();
        } else if (responseCode == 400 || responseCode == 401 || responseCode == 403) {
            clearAuthorizationState();
            requestDeviceCode();
        } else {
            failureStatus = "Refresh HTTP " + responseCode.toString();
            status = :failed;
            notifyStatusChanged();
        }
    }

    function acceptTokens(data as Dictionary) as Void {
        stopPolling();
        accessToken = data.get("access_token").toString();
        if (data.get("refresh_token") != null) {
            refreshToken = data.get("refresh_token").toString();
        }
        if (refreshToken != null) {
            Application.Storage.setValue("sitxRefreshToken", refreshToken);
        }
        deviceCode = null;
        userCode = "";
        verificationUrl = "";
        fetchGroups();
    }

    function fetchGroups() as Void {
        if (refreshToken == null) {
            failureStatus = "Refresh token missing";
            status = :failed;
            notifyStatusChanged();
            return;
        }
        status = :loadingGroups;
        notifyStatusChanged();
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {"Authorization" => "Bearer " + refreshToken},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        Communications.makeWebRequest(apiHost + "/api/v1/tak_servers", null, options, method(:onGroupsResponse));
    }

    function onGroupsResponse(responseCode as Number, data as String?) as Void {
        groups = [];
        if (responseCode < 200 || responseCode >= 300 || data == null) {
            failureStatus = "Groups HTTP " + responseCode.toString();
            status = :failed;
            notifyStatusChanged();
            return;
        }
        var groupObjects = jsonArrayObjects(data);
        if (groupObjects == null) {
            failureStatus = "Invalid TAK groups response";
            status = :failed;
            notifyStatusChanged();
            return;
        }
        for (var index = 0; index < groupObjects.size(); index++) {
            var groupObject = groupObjects[index] as String;
            var flowTag = jsonStringProperty(groupObject, "flow_tag");
            var name = jsonStringProperty(groupObject, "name");
            if (flowTag != null && name != null) {
                groups.add(new SitxGroup(flowTag, name));
            }
        }
        var foundSelectedGroup = false;
        for (var groupIndex = 0; groupIndex < groups.size(); groupIndex++) {
            var knownGroup = groups[groupIndex] as SitxGroup;
            if (knownGroup.flowTag.equals(selectedGroupFlowTag)) { foundSelectedGroup = true; }
        }
        if (!foundSelectedGroup) { clearGroupSelection(); }
        if (responseCode >= 200 && responseCode < 300) {
            if (groups.size() == 0) {
                status = :noGroups;
            } else if (groups.size() == 1) {
                setSelectedGroup(groups[0] as SitxGroup);
            } else if (selectedGroupFlowTag.length() > 0) {
                requestGroupAccessToken();
            } else {
                status = :selectGroup;
            }
        } else {
            failureStatus = "Groups HTTP " + responseCode.toString();
            status = :failed;
        }
        notifyStatusChanged();
    }

    function jsonArrayObjects(json as String) as Array<String>? {
        var text = trimWhitespace(json);
        if (text.length() < 2 || !text.substring(0, 1).equals("[") || !text.substring(text.length() - 1, text.length()).equals("]")) {
            return null;
        }
        var result = [];
        var objectStart = null;
        var objectDepth = 0;
        var inString = false;
        var escaped = false;
        for (var index = 0; index < text.length(); index++) {
            var character = text.substring(index, index + 1);
            if (inString) {
                if (escaped) {
                    escaped = false;
                } else if (character.equals("\\")) {
                    escaped = true;
                } else if (character.equals("\"")) {
                    inString = false;
                }
            } else if (character.equals("\"")) {
                inString = true;
            } else if (character.equals("{")) {
                if (objectDepth == 0) { objectStart = index; }
                objectDepth += 1;
            } else if (character.equals("}")) {
                objectDepth -= 1;
                if (objectDepth < 0) { return null; }
                if (objectDepth == 0 && objectStart != null) {
                    result.add(text.substring(objectStart as Number, index + 1));
                    objectStart = null;
                }
            }
        }
        if (inString || objectDepth != 0 || objectStart != null) { return null; }
        return result;
    }

    function jsonStringProperty(objectText as String, property as String) as String? {
        var index = 1;
        while (index < objectText.length() - 1) {
            while (index < objectText.length() - 1 && isJsonWhitespace(objectText.substring(index, index + 1))) { index += 1; }
            if (!objectText.substring(index, index + 1).equals("\"")) { return null; }
            var keyEnd = jsonStringEnd(objectText, index);
            if (keyEnd == null) { return null; }
            var key = decodeJsonString(objectText.substring(index, (keyEnd as Number) + 1));
            index = (keyEnd as Number) + 1;
            while (index < objectText.length() - 1 && isJsonWhitespace(objectText.substring(index, index + 1))) { index += 1; }
            if (index >= objectText.length() - 1 || !objectText.substring(index, index + 1).equals(":")) { return null; }
            index += 1;
            while (index < objectText.length() - 1 && isJsonWhitespace(objectText.substring(index, index + 1))) { index += 1; }
            if (key.equals(property) && index < objectText.length() - 1 && objectText.substring(index, index + 1).equals("\"")) {
                var valueEnd = jsonStringEnd(objectText, index);
                if (valueEnd == null) { return null; }
                return decodeJsonString(objectText.substring(index, (valueEnd as Number) + 1));
            }
            if (index < objectText.length() - 1 && objectText.substring(index, index + 1).equals("\"")) {
                var valueEnd = jsonStringEnd(objectText, index);
                if (valueEnd == null) { return null; }
                index = (valueEnd as Number) + 1;
            } else {
                while (index < objectText.length() - 1 && !objectText.substring(index, index + 1).equals(",")) { index += 1; }
            }
            while (index < objectText.length() - 1 && isJsonWhitespace(objectText.substring(index, index + 1))) { index += 1; }
            if (index < objectText.length() - 1 && objectText.substring(index, index + 1).equals(",")) { index += 1; }
        }
        return null;
    }

    function jsonStringEnd(text as String, start as Number) as Number? {
        var escaped = false;
        for (var index = start + 1; index < text.length(); index++) {
            var character = text.substring(index, index + 1);
            if (escaped) {
                escaped = false;
            } else if (character.equals("\\")) {
                escaped = true;
            } else if (character.equals("\"")) {
                return index;
            }
        }
        return null;
    }

    function decodeJsonString(token as String) as String? {
        var result = "";
        for (var index = 1; index < token.length() - 1; index++) {
            var character = token.substring(index, index + 1);
            if (!character.equals("\\")) {
                result += character;
                continue;
            }
            index += 1;
            if (index >= token.length() - 1) { return null; }
            character = token.substring(index, index + 1);
            if (character.equals("\"") || character.equals("\\") || character.equals("/")) { result += character; }
            else if (character.equals("b")) { result += "\b"; }
            else if (character.equals("f")) { result += "\f"; }
            else if (character.equals("n")) { result += "\n"; }
            else if (character.equals("r")) { result += "\r"; }
            else if (character.equals("t")) { result += "\t"; }
            else if (character.equals("u")) { return null; }
            else { return null; }
        }
        return result;
    }

    function isJsonWhitespace(character as String) as Boolean {
        return character.equals(" ") || character.equals("\t") || character.equals("\r") || character.equals("\n");
    }

    function setSelectedGroup(group as SitxGroup) as Void {
        if (!selectedGroupFlowTag.equals(group.flowTag)) {
            groupEndpoint = null;
        }
        selectedGroupFlowTag = group.flowTag;
        selectedGroupName = group.name;
        Application.Storage.setValue("sitxGroupFlowTag", selectedGroupFlowTag);
        Application.Storage.setValue("sitxGroupName", selectedGroupName);
        requestGroupAccessToken();
    }

    function requestGroupAccessToken() as Void {
        if (selectedGroupFlowTag.length() == 0 || refreshToken == null) { return; }
        status = :requestingGroupToken;
        notifyStatusChanged();
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Authorization" => "Bearer " + refreshToken,
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(apiHost + "/api/v1/access/token", {
            "grant_type" => "access",
            "resource_type" => "TAKSERVER",
            "resource_key" => selectedGroupFlowTag
        }, options, method(:onGroupAccessTokenResponse));
    }

    function onGroupAccessTokenResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode < 200 || responseCode >= 300 || data == null || data.get("access_token") == null || data.get("end_point") == null) {
            failureStatus = "Group token HTTP " + responseCode.toString();
            status = :failed;
            notifyStatusChanged();
            return;
        }
        var endpoint = data.get("end_point").toString();
        if (endpoint.length() < 6 || !endpoint.substring(0, 6).equals("wss://")) {
            failureStatus = "Sit(x) returned an insecure or invalid endpoint";
            status = :failed;
            notifyStatusChanged();
            return;
        }
        groupEndpoint = endpoint;
        if (data.get("refresh_token") != null) {
            refreshToken = data.get("refresh_token").toString();
            Application.Storage.setValue("sitxRefreshToken", refreshToken);
        }
        status = :transportUnavailable;
        notifyStatusChanged();
    }

    function forgetAuthorization() as Void {
        clearAuthorizationState();
        clearGroupSelection();
        status = :unconfigured;
        notifyStatusChanged();
    }

    function networkStatusLabel() as String {
        return statusText();
    }

    function clearAuthorizationState() as Void {
        stopPolling();
        Application.Storage.deleteValue("sitxAccessToken");
        Application.Storage.deleteValue("sitxRefreshToken");
        accessToken = null;
        refreshToken = null;
        accessToken = null;
        deviceCode = null;
        userCode = "";
        verificationUrl = "";
        groupEndpoint = null;
    }

    function clearGroupSelection() as Void {
        selectedGroupFlowTag = "";
        selectedGroupName = "";
        groups = [];
        Application.Storage.deleteValue("sitxGroupFlowTag");
        Application.Storage.deleteValue("sitxGroupName");
    }

    function statusText() as String {
        if (status == :needsConfiguration) { return failureStatus.length() > 0 ? failureStatus : "Enter Sit(x) API host"; }
        if (status == :requestingCode) { return "Requesting device code"; }
        if (status == :awaitingAuthorization) { return "Waiting for authorization"; }
        if (status == :refreshing) { return "Refreshing token"; }
        if (status == :off) { return "Off"; }
        if (status == :authorized) { return "Authorized"; }
        if (status == :loadingGroups) { return "Loading TAK groups"; }
        if (status == :selectGroup) { return "Select a TAK group"; }
        if (status == :noGroups) { return "No permitted TAK groups"; }
        if (status == :requestingGroupToken) { return "Requesting group token"; }
        if (status == :transportUnavailable) { return "Group ready; WebSocket unavailable on Connect IQ"; }
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
            host = host.substring(7, host.length());
        } else if (host.length() >= 8 && host.substring(0, 8).equals("https://")) {
            host = host.substring(8, host.length());
        }
        host = trimTrailingSlashes(host);
        for (var index = 0; index < host.length(); index++) {
            var character = host.substring(index, index + 1);
            if (isWhitespace(character) || character.equals("/") || character.equals("?") || character.equals("#") || character.equals("@") || character.equals(":")) {
                return "";
            }
        }
        while (host.length() > 8 && hasSuffix(host, ".sitx.io.sitx.io")) {
            host = host.substring(0, host.length() - 8);
        }
        if (!host.equals("sitx.io") && !hasSuffix(host, ".sitx.io")) {
            host += ".sitx.io";
        }
        return "https://" + host;
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

    function hasSuffix(value as String, suffix as String) as Boolean {
        return value.length() >= suffix.length()
            && value.substring(value.length() - suffix.length(), value.length()).equals(suffix);
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