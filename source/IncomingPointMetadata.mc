import Toybox.Lang;

function isIncomingCoordinateValue(value) as Boolean {
    return value instanceof Number || value instanceof Float || value instanceof Double
        || value instanceof Long;
}

function incomingCoordinateFloat(value) as Float? {
    if (value instanceof Float) { return value as Float; }
    if (value instanceof Number) { return (value as Number).toFloat(); }
    if (value instanceof Double) { return (value as Double).toFloat(); }
    if (value instanceof Long) { return (value as Long).toFloat(); }
    return null;
}

function isCancelState(value) as Boolean {
    if (value == null) { return false; }
    if (value instanceof Boolean) { return value == false; }
    if (value instanceof Number) { return value == 0; }
    if (!(value instanceof String)) { return false; }
    var normalized = (value as String).toUpper();
    return normalized.equals("CANCEL") || normalized.equals("CANCELLED")
        || normalized.equals("CANCELED") || normalized.equals("FALSE") || normalized.equals("0");
}

function isBooleanTrue(value) as Boolean {
    if (value == null) { return false; }
    if (value instanceof Boolean) { return value == true; }
    if (value instanceof Number) { return value == 1; }
    if (value instanceof String) {
        var normalized = (value as String).toLower();
        return normalized.equals("true") || normalized.equals("1");
    }
    return false;
}

function isIncomingAlert(cotType as String, metadata as Dictionary) as Boolean {
    if (cotType == null) { return false; }
    var type = cotType.toString();
    if (type.equals("b-a-o") || type.find("b-a-o-") == 0) { return true; }
    if (metadata.get("isAlert") == true || isBooleanTrue(metadata.get("isAlert"))) { return true; }
    if (metadata.get("emergency") instanceof Dictionary) { return true; }
    if (metadata.get("emergency") instanceof String) { return true; }
    if (metadata.get("alertType") instanceof String) { return true; }
    if (metadata.get("category") instanceof String) { return true; }
    if (metadata.get("catg") instanceof String) { return true; }
    if (metadata.get("active") == true) { return true; }
    if (isBooleanTrue(metadata.get("cancel")) || isCancelState(metadata.get("state"))) { return true; }
    return false;
}

function isIncomingAlertCleared(cotType as String, metadata as Dictionary) as Boolean {
    if (!isIncomingAlert(cotType, metadata)) { return false; }
    if (cotType != null && (cotType.equals("b-a-o-can") || cotType.find("b-a-o-can") == 0)) { return true; }
    var state = metadata.get("state");
    if (isCancelState(state)) { return true; }
    var active = metadata.get("active");
    if (active instanceof Boolean && active == false) { return true; }
    if (active instanceof Number && active == 0) { return true; }
    if (active instanceof String && (active as String).toLower().equals("false")) { return true; }
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        var cancel = emergency.get("cancel");
        if (isBooleanTrue(cancel) || isCancelState(emergency.get("state"))) { return true; }
    }
    var cancel = metadata.get("cancel");
    if (isBooleanTrue(cancel) || isCancelState(cancel)) { return true; }
    return false;
}

function isIncomingMapPoint(cotType as String, metadata as Dictionary) as Boolean {
    var explicitPoint = metadata.get("isPoint");
    if (explicitPoint instanceof Boolean) { return explicitPoint; }
    var takv = metadata.get("takv");
    if (takv instanceof Dictionary) {
        var device = takv.get("device");
        if (device instanceof String && device.toLower().equals("map marker")) { return true; }
    }
    if (cotType.find("a-") != 0 || cotType.find("-G-U-C") != null) { return false; }
    var how = metadata.get("how");
    return how instanceof String && how.find("h-") == 0;
}

function incomingPointSender(metadata as Dictionary) as String {
    if (!(metadata instanceof Dictionary)) { return ""; }
    var candidates = ["senderUID", "senderUid", "sender", "sourceUid", "sourceUID", "deviceUid", "deviceUID"];
    for (var i = 0; i < candidates.size(); i++) {
        var sender = metadata.get(candidates[i]);
        if (sender instanceof String && (sender as String).length() > 0) { return sender as String; }
    }
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        for (var j = 0; j < candidates.size(); j++) {
            var sender = emergency.get(candidates[j]);
            if (sender instanceof String && (sender as String).length() > 0) { return sender as String; }
        }
    }
    var link = metadata.get("link");
    if (link instanceof Dictionary) {
        var relation = link.get("relation");
        var uid = link.get("uid");
        if (relation instanceof String && uid instanceof String && !uid.toString().equals("")) {
            var relationName = (relation as String).toLower();
            if (relationName.equals("p-p") || relationName.equals("parent") || relationName.equals("p-c") || relationName.equals("child")) {
                return uid as String;
            }
        }
    }
    return "";
}

function incomingPointRevision(metadata as Dictionary) as String {
    if (!(metadata instanceof Dictionary)) { return ""; }
    var expected = ["time", "tStart", "start", "revision", "lastUpdated", "created", "updated"];
    for (var i = 0; i < expected.size(); i++) {
        var value = metadata.get(expected[i]);
        if (value instanceof String && (value as String).length() > 0) { return value as String; }
    }
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        for (var j = 0; j < expected.size(); j++) {
            var value = emergency.get(expected[j]);
            if (value instanceof String && (value as String).length() > 0) { return value as String; }
        }
    }
    return "";
}

function incomingPointSource(metadata as Dictionary) as String {
    if (!(metadata instanceof Dictionary)) { return "phone-relay"; }
    var source = metadata.get("__source");
    if (source == null) { source = metadata.get("source"); }
    if (source instanceof String && (source as String).length() > 0) { return source as String; }
    return "phone-relay";
}

function incomingPointStaleDeadline(metadata as Dictionary) as String {
    if (!(metadata instanceof Dictionary)) { return ""; }
    var stale = metadata.get("stale");
    if (stale == null) { stale = metadata.get("tStale"); }
    if (stale instanceof String) { return stale as String; }
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        var emergencyStale = emergency.get("stale");
        if (emergencyStale == null) { emergencyStale = emergency.get("tStale"); }
        if (emergencyStale instanceof String) { return emergencyStale as String; }
    }
    return "";
}

function incomingPointCategory(cotType as String, metadata as Dictionary) as String {
    var candidates = ["category", "catg", "alertType", "type", "desc"];
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        for (var i = 0; i < candidates.size(); i++) {
            var nested = emergency.get(candidates[i]);
            if (nested instanceof String && (nested as String).length() > 0) { return nested as String; }
        }
    }
    if (emergency instanceof String && (emergency as String).length() > 0) {
        return emergency as String;
    }
    var topLevelCandidates = ["category", "catg", "alertType", "desc"];
    for (var j = 0; j < topLevelCandidates.size(); j++) {
        var value = metadata.get(topLevelCandidates[j]);
        if (value instanceof String && (value as String).length() > 0) { return value as String; }
    }
    if (cotType != null && cotType.find("b-a-o-") == 0 && cotType.length() > 6) {
        return cotType.substring(6, cotType.length());
    }
    return "";
}
