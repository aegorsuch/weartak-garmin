import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

// Geometry only: indices always refer to the original, unfiltered vertex array.
module RouteNavigation {
    function location(point as Dictionary) as Position.Location {
        return new Position.Location({:latitude => point.get("lat") as Double,
            :longitude => point.get("lon") as Double, :format => :degrees});
    }

    function distance(fromLocation, toLocation) {
        var a = fromLocation.toDegrees();
        var b = toLocation.toDegrees();
        var lat = Math.sin(Math.toRadians(b[0] - a[0]) / 2);
        var lon = Math.sin(Math.toRadians(b[1] - a[1]) / 2);
        var h = lat * lat + Math.cos(Math.toRadians(a[0])) * Math.cos(Math.toRadians(b[0])) * lon * lon;
        if (h > 1) { h = 1; }
        return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
    }

    function nearest(points as Array, position) as Number? {
        if (position == null || points.size() == 0) { return null; }
        var index = 0;
        var best = distance(position, location(points[0]));
        for (var i = 1; i < points.size(); i++) {
            var range = distance(position, location(points[i]));
            if (range < best) { best = range; index = i; }
        }
        return index;
    }

    function arrivalRadius(method) as Number {
        var name = method instanceof String ? method.toLower() : "";
        if (name.equals("driving")) { return 20; }
        if (name.equals("watercraft")) { return 100; }
        if (name.equals("flying")) { return 1000; }
        return 10;
    }

    function checkpoint(point as Dictionary) as Boolean {
        var type = point.get("type");
        return type instanceof String && type.equals("b-m-p-w");
    }

    function nextObjective(points as Array, index as Number) as Number {
        while (index < points.size() - 1 && !checkpoint(points[index])) { index++; }
        return index;
    }

    function wrappedLongitude(degrees) {
        while (degrees > 180) { degrees -= 360; }
        while (degrees < -180) { degrees += 360; }
        return degrees;
    }

    // Closest-segment projection; strict distance comparison keeps the earliest loop crossing.
    function projectedAlong(points as Array, position) {
        var here = position.toDegrees();
        var scale = Math.cos(Math.toRadians(here[0]));
        var prior = 0.0;
        var best = null;
        var along = 0.0;
        for (var i = 1; i < points.size(); i++) {
            var a = points[i - 1] as Dictionary;
            var b = points[i] as Dictionary;
            var aLat = a.get("lat") as Number or Float or Double;
            var aLon = a.get("lon") as Number or Float or Double;
            var bLat = b.get("lat") as Number or Float or Double;
            var bLon = b.get("lon") as Number or Float or Double;
            var ax = wrappedLongitude(aLon - here[1]) * scale;
            var ay = aLat - here[0];
            var dx = wrappedLongitude(bLon - aLon) * scale;
            var dy = bLat - aLat;
            var squared = dx * dx + dy * dy;
            var t = squared == 0 ? 0.0 : -(ax * dx + ay * dy) / squared;
            if (t < 0) { t = 0.0; }
            if (t > 1) { t = 1.0; }
            var x = ax + t * dx;
            var y = ay + t * dy;
            var range = x * x + y * y;
            var length = distance(location(a), location(b));
            if (best == null || range < best) { best = range; along = prior + t * length; }
            prior += length;
        }
        return along;
    }

    function nearestObjective(points as Array, position) as Number? {
        if (position == null || points.size() == 0) { return null; }
        var along = projectedAlong(points, position);
        var cumulative = 0.0;
        for (var i = 0; i < points.size(); i++) {
            if (i > 0) { cumulative += distance(location(points[i - 1]), location(points[i])); }
            if ((checkpoint(points[i]) || i == points.size() - 1) && cumulative >= along) { return i; }
        }
        return points.size() - 1;
    }

    // Arrival is remembered, but projection alone never skips an unvisited checkpoint.
    // The final destination bubble completes even if earlier objectives were missed.
    function advance(points as Array, index as Number, position, method, reached as Array) as Number {
        if (position == null || index >= points.size()) { return index; }
        var radius = arrivalRadius(method);
        if (distance(position, location(points[points.size() - 1])) <= radius) { return points.size(); }
        for (var i = 0; i < points.size() - 1; i++) {
            if (checkpoint(points[i]) && distance(position, location(points[i])) <= radius
                    && reached.indexOf(i) < 0) { reached.add(i); }
        }
        index = nextObjective(points, index);
        var along = projectedAlong(points, position);
        var cumulative = 0.0;
        for (var i = 1; i <= index; i++) { cumulative += distance(location(points[i - 1]), location(points[i])); }
        while (index < points.size() - 1 && reached.indexOf(index) >= 0 && along >= cumulative) {
            var next = nextObjective(points, index + 1);
            for (var i = index + 1; i <= next; i++) {
                cumulative += distance(location(points[i - 1]), location(points[i]));
            }
            index = next;
        }
        return index;
    }

    function remaining(points as Array, index as Number, position) {
        if (index >= points.size()) { return 0.0; }
        var previous = location(points[index]);
        var total = position == null ? 0.0 : distance(position, previous);
        for (var i = index + 1; i < points.size(); i++) {
            var next = location(points[i]);
            total += distance(previous, next);
            previous = next;
        }
        return total;
    }

    function bounds(points as Array) as Array {
        var north = points[0].get("lat");
        var south = north;
        var origin = points[0].get("lon");
        var west = origin;
        var east = origin;
        for (var i = 1; i < points.size(); i++) {
            var lat = points[i].get("lat");
            var lon = points[i].get("lon");
            while (lon - origin > 180) { lon -= 360; }
            while (lon - origin < -180) { lon += 360; }
            if (lat > north) { north = lat; }
            if (lat < south) { south = lat; }
            if (lon < west) { west = lon; }
            if (lon > east) { east = lon; }
        }
        var latPad = (north - south) * 0.12;
        var lonPad = (east - west) * 0.12;
        if (latPad < 0.0005) { latPad = 0.0005; }
        if (lonPad < 0.0005) { lonPad = 0.0005; }
        north += latPad; south -= latPad;
        if (north > 90) { north = 90; }
        if (south < -90) { south = -90; }
        west -= lonPad; east += lonPad;
        if (east - west >= 360) { west = -180.0; east = 180.0; }
        else {
            while (west < -180) { west += 360; }
            while (east > 180) { east -= 360; }
        }
        return [north, west, south, east];
    }

}
