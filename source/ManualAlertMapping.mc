import Toybox.Lang;

const MANUAL_ALERT_MAX_LABEL_LENGTH = 32;
const CHAT_QUICK_REPLY_MAX_LENGTH = 128;

function manualAlertCotType(alertType as String, state as Symbol) as String {
    if (state == :CANCEL) { return "b-a-o-can"; }
    if (alertType.equals("911 Alert")) { return "b-a-o-tbl"; }
    if (alertType.equals("Ring The Bell")) { return "b-a-o-pan"; }
    if (alertType.equals("Geofence Breached")) { return "b-a-g"; }
    if (alertType.equals("In Contact")) { return "b-a-o-opn"; }
    return "b-a-o";
}

function isBuiltInManualAlert(alertType as String) as Boolean {
    var builtIns = ["911 Alert", "Gate Runner", "Geofence Breached", "Gunshot",
        "In Contact", "Injury", "Ring The Bell", "UAS", "Vehicle"];
    for (var index = 0; index < builtIns.size(); index++) {
        if (builtIns[index].toLower().equals(alertType.toLower())) { return true; }
    }
    return false;
}

function normalizeCustomManualAlert(value as String) as String? {
    return normalizeSingleLineValue(value, MANUAL_ALERT_MAX_LABEL_LENGTH);
}

function normalizeSingleLineValue(value as String, maxLength as Number) as String? {
    var start = 0;
    var end = value.length();
    while (start < end) {
        var character = value.substring(start, start + 1);
        if (character.equals(" ") || character.equals("\t")) { start++; }
        else { break; }
    }
    while (end > start) {
        var character = value.substring(end - 1, end);
        if (character.equals(" ") || character.equals("\t")) { end--; }
        else { break; }
    }
    if (end == start || end - start > maxLength) { return null; }
    var normalized = value.substring(start, end);
    if (normalized.find("\n") != null || normalized.find("\r") != null) { return null; }
    return normalized;
}

function isBuiltInChatQuickReply(value as String) as Boolean {
    var builtIns = ["Rgr", "Neg", "ObjS", "nPos"];
    for (var index = 0; index < builtIns.size(); index++) {
        if (builtIns[index].toLower().equals(value.toLower())) { return true; }
    }
    return false;
}
