import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Test;
import Toybox.Time;

(:test)
class DynamicReportingAppFixture extends StandaloneApp {
    var relay as TestReliableRelay;
    var dynamic as Boolean = true;
    var selector as DynamicReporting = new DynamicReporting();
    var intervals as Dictionary = {:stationary => 3600, :onFoot => 60, :vehicle => 10,
        :whileAlerting => 5, :constant => 120};
    function initialize() { relay = new TestReliableRelay(); }
    function getTakClient() as TakClient { return relay; }
    function isDynamicReportingEnabled() as Boolean { return dynamic; }
    function getReportingInterval(setting as Symbol) as Number { return intervals.get(setting) as Number; }
    function reportingIntervalFromSpeed(speed, sampledAt as Number?, now as Number, enabled as Boolean) as Number {
        selector.observe(self, speed, sampledAt, Position.QUALITY_GOOD, true, now, enabled);
        return selector.currentInterval(self, now, enabled);
    }
}

(:test)
class ReportingFallbackFixture extends ReportingControl {
    var delay as Number? = null;
    var stops as Number = 0;
    function initialize() {}
    function stopPliTimer() as Void { delay = null; stops++; }
    function startPliTimer(seconds as Number, callback as Method) as Void { delay = seconds; }
    function onFallback() as Void {}
}

(:test)
function dynamicReportingFallbackReschedulesWithCurrentSelector(logger) as Boolean {
    var app = new DynamicReportingAppFixture();
    var control = new ReportingFallbackFixture();
    var callback = control.method(:onFallback);
    var interval = app.reportingIntervalFromSpeed(0, 100, 100, true);
    control.schedulePliFallback(interval, 100, 100, true, true, callback);
    Test.assertEqual(control.delay, 3600);
    interval = app.reportingIntervalFromSpeed(13.4112d, 105, 105, true);
    control.schedulePliFallback(interval, 105, 100, true, true, callback);
    Test.assertEqual(control.delay, 5);
    Test.assertEqual(control.stops, 2);
    control.schedulePliFallback(interval, 111, 100, true, true, callback);
    Test.assertEqual(control.delay, 1);
    control.schedulePliFallback(interval, 111, null, true, true, callback);
    Test.assertEqual(control.delay, 1);
    control.schedulePliFallback(interval, 111, 100, false, true, callback);
    Test.assert(control.delay == null);
    control.schedulePliFallback(interval, 111, 100, true, false, callback);
    Test.assert(control.delay == null);
    return true;
}

(:test)
function dynamicReportingInterpolatesClampsAndPreservesRates(logger) as Boolean {
    var app = new DynamicReportingAppFixture();
    Test.assertEqual(app.reportingIntervalFromSpeed(0.0d, 100, 100, true), 3600);
    Test.assertEqual(app.reportingIntervalFromSpeed(0.44703d, 100, 100, true), 3600);
    Test.assertEqual(app.reportingIntervalFromSpeed(0.44704d, 100, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(6.92912d, 100, 100, true), 35);
    Test.assertEqual(app.reportingIntervalFromSpeed(13.4112d, 100, 100, true), 10);
    Test.assertEqual(app.reportingIntervalFromSpeed(300.0d, 100, 100, true), 10);
    var previous = 60;
    for (var i = 0; i <= 100; i++) {
        var speed = 0.44704d + (13.4112d - 0.44704d) * i / 100.0d;
        var selected = app.reportingIntervalFromSpeed(speed, 100, 100, true);
        Test.assert(selected >= 10 && selected <= previous);
        previous = selected;
    }
    app.intervals.put(:onFoot, 10);
    app.intervals.put(:vehicle, 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(0.44704d, 100, 100, true), 10);
    Test.assertEqual(app.reportingIntervalFromSpeed(6.92912d, 100, 100, true), 35);
    Test.assertEqual(app.reportingIntervalFromSpeed(13.4112d, 100, 100, true), 60);
    app.intervals.put(:vehicle, 11);
    Test.assertEqual(app.reportingIntervalFromSpeed(6.92912d, 100, 100, true), 11);
    app.intervals.put(:vehicle, 10);
    Test.assertEqual(app.reportingIntervalFromSpeed(9.0d, 100, 100, true), 10);
    Test.assertEqual(app.intervals.get(:stationary), 3600);
    Test.assertEqual(app.intervals.get(:onFoot), 10);
    Test.assertEqual(app.intervals.get(:vehicle), 10);
    return true;
}

(:test)
function dynamicReportingUnknownFreshnessAndOverridePriority(logger) as Boolean {
    var app = new DynamicReportingAppFixture();
    Test.assertEqual(app.reportingIntervalFromSpeed(null, 100, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(-1, 100, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, null, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, 101, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, 100, 110, true), 3600);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, 100, 111, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, 100, 100, false), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(Math.sqrt(-1), 100, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(Math.log(0, 10), 100, 100, true), 60);
    Test.assertEqual(app.reportingIntervalFromSpeed(-Math.log(0, 10), 100, 100, true), 60);
    app.intervals.put(:onFoot, 10);
    app.intervals.put(:vehicle, 90);
    Test.assertEqual(app.reportingIntervalFromSpeed(null, null, 100, true), 90);
    app.relay.alerting = true;
    Test.assertEqual(app.reportingIntervalFromSpeed(null, null, 100, false), 5);
    Test.assertEqual(app.reportingIntervalFromSpeed(0, 100, 100, true), 5);
    app.dynamic = false;
    Test.assertEqual(app.reportingIntervalFromSpeed(null, null, 100, false), 120);
    return true;
}

(:test)
function dynamicReportingObservationRequiresActualUsableSampleAndNeverSends(logger) as Boolean {
    var app = new DynamicReportingAppFixture();
    var now = Time.now().value();
    app.selector.observe(app, 0, now, Position.QUALITY_GOOD, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 3600);
    app.selector.observe(app, 13.4112d, now, Position.QUALITY_USABLE, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 10);
    app.selector.observe(app, null, now, Position.QUALITY_GOOD, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    app.selector.observe(app, 0, now, Position.QUALITY_POOR, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    app.selector.observe(app, 0, now, Position.QUALITY_GOOD, false, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    app.selector.observe(app, 0, now - 61, Position.QUALITY_GOOD, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    app.selector.observe(app, 0, now + 1, Position.QUALITY_GOOD, true, now, true);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    app.selector.observe(app, 0, now, Position.QUALITY_GOOD, true, now, false);
    Test.assertEqual(app.selector.currentInterval(app, now, true), 60);
    Test.assertEqual(app.relay.envelopes.size(), 0);
    Test.assertEqual(app.relay.pointReplies.replies.size(), 1);
    return true;
}

(:test)
function dynamicReportingExpiryFreezesObservationBudgetWithoutAcquisition(logger) as Boolean {
    var app = new DynamicReportingAppFixture();
    app.intervals.put(:onFoot, 30);
    app.intervals.put(:vehicle, 60);
    Test.assertEqual(app.selector.observationInterval(app, 0), 30);
    Test.assertEqual(app.selector.observationInterval(app, 6.92912d), 30);
    app.selector.observe(app, 0, 100, Position.QUALITY_GOOD, true, 100, true);
    Test.assertEqual(app.selector.validUntil, 130);
    Test.assertEqual(app.selector.currentInterval(app, 130, true), 3600);
    Test.assertEqual(app.selector.currentInterval(app, 131, true), 60);
    Test.assertEqual(app.selector.validUntil, 130);
    Test.assertEqual(app.selector.currentInterval(app, 132, true), 60);
    Test.assertEqual(app.selector.validUntil, 130);
    app.intervals.put(:onFoot, 120);
    app.intervals.put(:vehicle, 90);
    app.selector.observe(app, 0, 100, Position.QUALITY_GOOD, true, 132, true);
    Test.assertEqual(app.selector.currentInterval(app, 132, true), 120);
    Test.assertEqual(app.selector.validUntil, 130);
    app.intervals.put(:vehicle, 60);
    app.intervals.put(:onFoot, 10);
    Test.assertEqual(app.selector.currentInterval(app, 120, true), 3600);
    Test.assertEqual(app.selector.validUntil, 130);
    app.relay.alerting = true;
    Test.assertEqual(app.selector.observationInterval(app, 0), 5);
    Test.assertEqual(app.selector.currentInterval(app, 131, true), 5);
    app.selector.observe(app, 0, 200, Position.QUALITY_GOOD, true, 200, true);
    Test.assertEqual(app.selector.validUntil, 205);
    app.relay.alerting = false;
    Test.assertEqual(app.selector.currentInterval(app, 206, true), 60);
    app.selector.clear();
    Test.assertEqual(app.selector.currentInterval(app, 120, true), 60);
    Test.assert(app.selector.validUntil == null);
    app.intervals.put(:onFoot, 120);
    app.intervals.put(:vehicle, 90);
    Test.assertEqual(app.selector.observationInterval(app, 0), 60);
    app.selector.observe(app, 0, 100, Position.QUALITY_GOOD, true, 159, true);
    Test.assertEqual(app.selector.validUntil, 160);
    Test.assertEqual(app.selector.currentInterval(app, 160, true), 3600);
    Test.assertEqual(app.selector.currentInterval(app, 161, true), 120);
    app.selector.observe(app, 0, 100, Position.QUALITY_GOOD, true, 161, true);
    Test.assertEqual(app.selector.validUntil, 160);
    Test.assertEqual(app.selector.currentInterval(app, 161, true), 120);
    app.selector.observe(app, 0, 99, Position.QUALITY_GOOD, true, 161, true);
    Test.assertEqual(app.selector.currentInterval(app, 161, true), 120);
    Test.assertEqual(app.selector.sampledAt, 100);
    Test.assertEqual(app.relay.envelopes.size(), 0);
    return true;
}
