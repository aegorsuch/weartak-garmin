import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

class DynamicReporting {
    var speed as Double? = null;
    var sampledAt as Number? = null;
    var validUntil as Number? = null;

    function initialize() {}
    function clear() as Void { speed = null; sampledAt = null; validUntil = null; }

    function observe(app as StandaloneApp, value, timestamp as Number?, quality as Number,
            hasPosition as Boolean, now as Number, enabled as Boolean) as Void {
        if (!hasPosition || (quality != Position.QUALITY_GOOD && quality != Position.QUALITY_USABLE)
                || !valid(value, timestamp, now, enabled)
                || (sampledAt != null && timestamp < sampledAt)) {
            speed = null;
            return;
        }
        // Re-delivery of the same native sample must not extend its frozen budget.
        if (timestamp != sampledAt) { validUntil = timestamp + observationInterval(app, value); }
        speed = value.toDouble();
        sampledAt = timestamp;
    }

    function valid(value, timestamp as Number?, now as Number, enabled as Boolean) as Boolean {
        if (!enabled || timestamp == null || timestamp > now
                || (!(value instanceof Float) && !(value instanceof Double) && !(value instanceof Number))) { return false; }
        var number = value.toDouble();
        return number >= 0 && (number - number) == 0.0d;
    }

    function currentInterval(app as StandaloneApp, now as Number, enabled as Boolean) as Number {
        var current = valid(speed, sampledAt, now, enabled) && validUntil != null && now <= validUntil ? speed : null;
        if (app.isDynamicReportingEnabled() && !app.getTakClient().isAlerting()) {
            Diagnostics.record(current == null ? Diagnostics.SPEED_UNKNOWN
                : current < 0.44704d ? Diagnostics.SPEED_STATIONARY : Diagnostics.SPEED_MOVING);
        }
        return selectInterval(app, current);
    }

    function observationInterval(app as StandaloneApp, value) as Number {
        var interval = 60;
        var limits = [app.getReportingInterval(:onFoot), app.getReportingInterval(:vehicle), selectInterval(app, value)];
        for (var i = 0; i < limits.size(); i++) {
            if (limits[i] < interval) { interval = limits[i]; }
        }
        return interval;
    }

    function selectInterval(app as StandaloneApp, value) as Number {
        if (!app.isDynamicReportingEnabled()) { return app.getReportingInterval(:constant); }
        if (app.getTakClient().isAlerting()) { return app.getReportingInterval(:whileAlerting); }
        var foot = app.getReportingInterval(:onFoot);
        var vehicle = app.getReportingInterval(:vehicle);
        if (value == null) { return foot > vehicle ? foot : vehicle; }
        var velocity = value.toDouble();
        if (velocity < 0.44704d) { return app.getReportingInterval(:stationary); }
        if (velocity >= 13.4112d) { return vehicle; }
        var fraction = (velocity - 0.44704d) / (13.4112d - 0.44704d);
        var seconds = Math.floor(foot + (vehicle - foot) * fraction + 0.5d).toNumber();
        var minimum = foot < vehicle ? foot : vehicle;
        var maximum = foot > vehicle ? foot : vehicle;
        return seconds < minimum ? minimum : seconds > maximum ? maximum : seconds;
    }
}
