import Toybox.Lang;

function isIncomingAlert(cotType as String, metadata as Dictionary) as Boolean {
    return cotType.find("b-a-") == 0 || metadata.get("isAlert") == true
        || metadata.get("emergency") instanceof Dictionary;
}

function isIncomingAlertCleared(cotType as String, metadata as Dictionary) as Boolean {
    if (!isIncomingAlert(cotType, metadata)) { return false; }
    var state = metadata.get("state");
    if (cotType.equals("b-a-o-can") || metadata.get("active") == false
            || (state instanceof String && state.equals("CANCEL"))) { return true; }
    var emergency = metadata.get("emergency");
    if (emergency instanceof Dictionary) {
        var cancel = emergency.get("cancel");
        return cancel == true || (cancel instanceof String && cancel.equals("true"));
    }
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
    var sender = metadata.get("senderUID");
    if (sender == null) { sender = metadata.get("senderUid"); }
    if (sender instanceof String && sender.length() > 0) { return sender; }
    var link = metadata.get("link");
    if (link instanceof Dictionary) {
        var relation = link.get("relation");
        var uid = link.get("uid");
        if (relation instanceof String && relation.equals("p-p") && uid instanceof String) { return uid; }
    }
    return "";
}

function incomingPointRevision(metadata as Dictionary) as String {
    var time = metadata.get("time");
    if (time == null) { time = metadata.get("tStart"); }
    return time instanceof String ? time : "";
}
