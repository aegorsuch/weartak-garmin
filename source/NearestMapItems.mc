import Toybox.Lang;

const MAP_RETAINED_LIMIT = 999;
const MAP_DRAWN_LIMIT = 99;

class NearestMapItems {
    var pointIds as Array<String> = [];
    var distances as Array<Number or Float or Double> = [];

    function add(id as String, distance as Number or Float or Double) as Void {
        var size = pointIds.size();
        if (size == MAP_DRAWN_LIMIT && distance >= distances[size - 1]) { return; }
        if (size < MAP_DRAWN_LIMIT) {
            pointIds.add(id);
            distances.add(distance);
            size += 1;
        }
        var index = size - 1;
        while (index > 0 && distances[index - 1] > distance) {
            pointIds[index] = pointIds[index - 1];
            distances[index] = distances[index - 1];
            index -= 1;
        }
        pointIds[index] = id;
        distances[index] = distance;
    }

}
