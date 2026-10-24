import Toybox.Lang;

function formatDistanceInUnits(meters, units as String, precision as Number) as String {
    var decimalFormat = precision > 1 ? "%.2f" : "%.1f";
    if (units.equals("Imperial")) {
        if (meters < 1609.344) {
            return (meters * 3.280839895).format("%.0f") + " ft";
        }
        return (meters / 1609.344).format(decimalFormat) + " mi";
    }
    if (meters < 1000) {
        return meters.format("%.0f") + " m";
    }
    return (meters / 1000.0).format(decimalFormat) + " km";
}

function distanceUnitsForAtakRangePreference(value as String) as String? {
    if (value.equals("0") || value.equals("2")) { return "Imperial"; }
    if (value.equals("1")) { return "Metric"; }
    return null;
}
