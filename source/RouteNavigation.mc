import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

const ROUTE_ARRIVAL_RADIUS_METERS = 20;

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

    // Returning size means complete; missing GPS never consumes a vertex.
    function advance(points as Array, index as Number, position) as Number {
        while (position != null && index < points.size()
                && distance(position, location(points[index])) <= ROUTE_ARRIVAL_RADIUS_METERS) {
            index++;
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
