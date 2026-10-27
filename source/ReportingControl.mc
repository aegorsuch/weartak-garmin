import Toybox.Lang;
import Toybox.Timer;

class ReportingControl {
    private var timer as Timer.Timer;

    function initialize() {
        timer = new Timer.Timer();
    }

    function stopPliTimer() as Void {
        timer.stop();
    }

    function startPliTimer(delay as Number, callback as Method) as Void {
        timer.start(callback, delay * 1000, false);
    }

    function schedulePliFallback(interval as Number, now as Number,
            lastPliSentTime as Number?, locationServices as Boolean, connected as Boolean,
            callback as Method) as Void {
        if (!locationServices || !connected) {
            stopPliTimer();
            return;
        }
        var delay = 1;
        if (lastPliSentTime != null) {
            var remaining = interval - (now - lastPliSentTime);
            if (remaining > 0) { delay = remaining; }
        }
        stopPliTimer();
        startPliTimer(delay, callback);
    }
}
