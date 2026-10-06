import Toybox.Lang;

module MapItemLimits {
    const RETAINED_LIMIT = 999;
    const DRAWN_LIMIT = 99;
}

class NearestMapItem {
    var id as String;
    var distance as Number or Float or Double;

    function initialize(pointId as String, range as Number or Float or Double) {
        id = pointId;
        distance = range;
    }
}

class NearestMapItems {
    var entries as Array<NearestMapItem> = [];

    function initialize() {}

    // A bounded max heap keeps selection O(n log 99), without sorting the retained store.
    function add(id as String, distance as Number or Float or Double) as Void {
        if (entries.size() < MapItemLimits.DRAWN_LIMIT) {
            var entry = new NearestMapItem(id, distance);
            entries.add(entry);
            var index = entries.size() - 1;
            while (index > 0) {
                var parent = ((index - 1) / 2).toNumber();
                if (entries[parent].distance >= distance) { break; }
                entries[index] = entries[parent];
                index = parent;
            }
            entries[index] = entry;
            return;
        }
        if (distance >= entries[0].distance) { return; }
        var entry = entries[0];
        entry.id = id;
        entry.distance = distance;
        var index = 0;
        while (index * 2 + 1 < entries.size()) {
            var child = index * 2 + 1;
            if (child + 1 < entries.size() && entries[child + 1].distance > entries[child].distance) {
                child += 1;
            }
            if (distance >= entries[child].distance) { break; }
            entries[index] = entries[child];
            index = child;
        }
        entries[index] = entry;
    }

    function ids() as Array<String> {
        var result = [] as Array<String>;
        for (var index = 0; index < entries.size(); index++) {
            result.add(entries[index].id);
        }
        return result;
    }
}
