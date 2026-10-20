import Toybox.Lang;
import Toybox.Position;

const ROUTE_LIMIT = 8;
const ROUTE_POINT_LIMIT = 64;
const ROUTE_TOTAL_POINT_LIMIT = 128;

class RouteStore {
    var routes as Array<Dictionary> = [];
    var error as String? = null;

    function initialize() {}

    function receive(kind as String, payload as Dictionary) as Boolean {
        error = null;
        if (payload.get("routeVersion") != 1) { return fail("Unsupported route protocol"); }
        if (kind.equals("routes_reset")) {
            routes = [];
            return true;
        }
        if (!validText(payload.get("serverId"), 64, false)
                || !validText(payload.get("uid"), 128, false)) { return fail("Invalid route identity"); }
        var server = payload.get("serverId") as String;
        var uid = payload.get("uid") as String;
        var previous = find(server, uid);
        if (kind.equals("route_remove")) {
            if (previous != null) { routes.remove(previous); }
            return true;
        }
        if (!kind.equals("route") || !validText(payload.get("name"), 64, false)
                || !validOptional(payload, "missionName", 128)
                || !validOptional(payload, "senderUid", 128)) { return fail("Invalid route metadata"); }
        var points = payload.get("points");
        if (!(points instanceof Array) || points.size() < 2 || points.size() > ROUTE_POINT_LIMIT) {
            return fail("Route must contain 2 to 64 points");
        }
        var total = points.size();
        for (var i = 0; i < routes.size(); i++) {
            if (routes[i] != previous) { total += (routes[i].get("points") as Array).size(); }
        }
        if ((previous == null && routes.size() >= ROUTE_LIMIT) || total > ROUTE_TOTAL_POINT_LIMIT) {
            return fail("Route capacity reached (8 routes / 128 points)");
        }
        var normalized = [];
        for (var i = 0; i < points.size(); i++) {
            var point = points[i];
            if (!(point instanceof Dictionary) || !coordinate(point.get("lat"), 90)
                    || !coordinate(point.get("lon"), 180) || !validOptional(point, "name", 64)) {
                return fail("Invalid route point");
            }
            normalized.add({"lat" => point.get("lat"), "lon" => point.get("lon"), "name" => point.get("name")});
        }
        var route = {"serverId" => server, "uid" => uid, "name" => payload.get("name"),
            "missionName" => payload.get("missionName"), "senderUid" => payload.get("senderUid"),
            "points" => normalized};
        if (previous != null) { routes[routes.indexOf(previous)] = route; }
        else { routes.add(route); }
        return true;
    }

    function fail(message as String) as Boolean {
        error = message;
        return false;
    }

    function coordinate(value, limit as Number) as Boolean {
        return (value instanceof Number || value instanceof Float || value instanceof Double || value instanceof Long)
            && value == value && value >= -limit && value <= limit;
    }

    function validText(value, limit as Number, empty as Boolean) as Boolean {
        if (!(value instanceof String)) { return false; }
        var bytes = value.toUtf8Array();
        if (bytes.size() > limit || (!empty && bytes.size() == 0)) { return false; }
        for (var i = 0; i < bytes.size(); i++) {
            if (bytes[i] < 32 || bytes[i] == 127) { return false; }
        }
        return bytes.size() == 0 || (bytes[0] > 32 && bytes[bytes.size() - 1] > 32);
    }

    function validOptional(payload as Dictionary, key as String, limit as Number) as Boolean {
        return payload.get(key) == null || validText(payload.get(key), limit, true);
    }

    function find(server as String, uid as String) as Dictionary? {
        for (var i = 0; i < routes.size(); i++) {
            var route = routes[i];
            if (server.equals(route.get("serverId")) && uid.equals(route.get("uid"))) { return route; }
        }
        return null;
    }

    function routeId(route as Dictionary) as String {
        var server = route.get("serverId") as String;
        var uid = route.get("uid") as String;
        return "route:" + server.toUtf8Array().size().toString() + ":" + server
            + uid.toUtf8Array().size().toString() + ":" + uid;
    }

    function route(id as String) as Dictionary? {
        for (var i = 0; i < routes.size(); i++) {
            if (id.equals(routeId(routes[i]))) { return routes[i]; }
        }
        return null;
    }

    function removeLocal(id as String) as Boolean {
        var selected = route(id);
        if (selected == null) { return false; }
        routes.remove(selected);
        return true;
    }

    function pointId(route as Dictionary, index as Number) as String {
        var server = route.get("serverId") as String;
        var uid = route.get("uid") as String;
        return "route-point:" + server.toUtf8Array().size().toString() + ":" + server
            + uid.toUtf8Array().size().toString() + ":" + uid + ":" + index.toString();
    }

    function namedPointIndices(route as Dictionary) as Array<Number> {
        var indices = [];
        var points = route.get("points") as Array;
        for (var i = 0; i < points.size(); i++) {
            if (hasPointName(points[i])) { indices.add(i); }
        }
        return indices;
    }

    function hasPointName(point as Dictionary) as Boolean {
        var name = point.get("name");
        if (!(name instanceof String)) { return false; }
        var chars = name.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var code = chars[i].toNumber();
            if (code <= 32 || code == 0x85 || code == 0xa0 || code == 0x1680
                    || (code >= 0x2000 && code <= 0x200a) || code == 0x2028
                    || code == 0x2029 || code == 0x202f || code == 0x205f || code == 0x3000) { continue; }
            return true;
        }
        return false;
    }

    function point(id as String) as Dictionary? {
        for (var r = 0; r < routes.size(); r++) {
            var route = routes[r];
            var points = route.get("points") as Array;
            for (var p = 0; p < points.size(); p++) {
                if (id.equals(pointId(route, p))) {
                    return {"route" => route, "point" => points[p], "index" => p};
                }
            }
        }
        return null;
    }

    function location(point as Dictionary) as Position.Location {
        return new Position.Location({:latitude => point.get("lat") as Double,
            :longitude => point.get("lon") as Double, :format => :degrees});
    }

    function title(selected as Dictionary) as String {
        var point = selected.get("point") as Dictionary;
        var name = point.get("name");
        return name instanceof String && name.length() > 0 ? name
            : (selected.get("route") as Dictionary).get("name") + " #" + ((selected.get("index") as Number) + 1).toString();
    }
}
