import Toybox.Lang;

const MANUAL_ALERT_MAX_LABEL_LENGTH = 60;
const MANUAL_ALERT_MAX_SAVED = 20;
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
        if (manualAlertLabelsEqual(builtIns[index], alertType)) { return true; }
    }
    return false;
}

function manualAlertLabelsEqual(left as String, right as String) as Boolean {
    var a = left.toCharArray();
    var b = right.toCharArray();
    if (a.size() != b.size()) { return false; }
    for (var i = 0; i < a.size(); i++) {
        var upperA = a[i].toUpper();
        var upperB = b[i].toUpper();
        if (upperA.toNumber() != upperB.toNumber()
                && upperA.toLower().toNumber() != upperB.toLower().toNumber()) { return false; }
    }
    return true;
}

function normalizeCustomManualAlert(value as String) as String? {
    var characters = value.toCharArray();
    var normalized = "";
    var units = 0;
    var spacePending = false;
    for (var i = 0; i < characters.size(); i++) {
        var code = characters[i].toNumber();
        if (code <= 0x1f || (code >= 0x7f && code <= 0x9f)) { return null; }
        var whitespace = code == 0x20 || code == 0xa0 || code == 0x1680
            || (code >= 0x2000 && code <= 0x200a) || code == 0x2028
            || code == 0x2029 || code == 0x202f || code == 0x205f || code == 0x3000;
        if (whitespace) { spacePending = units > 0; continue; }
        if (spacePending) { normalized += " "; units++; spacePending = false; }
        // Char.toString replaces supplementary characters on Connect IQ.
        normalized += value.substring(i, i + 1);
        // Shared apps count UTF-16 code units, not bytes or graphemes.
        units += code > 0xffff ? 2 : 1;
        if (units > MANUAL_ALERT_MAX_LABEL_LENGTH) { return null; }
    }
    return units == 0 ? null : normalized;
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
