// The station map markers: the toggle / add / refresh rules of `StationMapData`
// (`StationBlock.java:121` is the caller; `station_map_data.dart` the rules, complete in pure
// Dart). The map itself is a host gap — no `MapData` is reachable from wasm — so the sink is a
// fake: this pins the rules against the Java semantics so a future wiring only plugs the sink in.
import 'package:create/src/common/common.dart';
import 'package:create/src/common/pos.dart';
import 'package:create/src/redstone/support/text.dart' show Txt;
import 'package:create/src/trains/station/station_map_data.dart';
import 'package:create/src/trains/station/station_marker.dart';
import 'package:create/src/trains/util/ctag.dart';
import 'package:test/test.dart';

/// A fake `StationMapSink`: fixed center and scale, decorations as a map.
final class FakeSink implements StationMapSink {
  @override
  int centerX = 0;
  @override
  int centerZ = 0;
  @override
  int scale = 0;
  final Map<String, (int, int, String)> decorations = {};

  @override
  void putDecoration(String id, int x, int z, Txt name) {
    decorations[id] = (x, z, name.toJson().toString());
  }

  @override
  void removeDecoration(String id) {
    decorations.remove(id);
  }

  @override
  bool isTrackedCountOverLimit(int limit) => decorations.length >= limit;
}

StationMarker markerAt(int x, int y, int z, [String name = 'Station']) =>
    StationMarker((x, y, z), (x, 0, z), Txt.literal(name));

void main() {
  test('toggleStation adds the marker and shows its decoration', () {
    final sink = FakeSink();
    final markers = StationMapMarkers(sink);
    expect(
      markers.toggleStation((pos) => markerAt(pos.$1, pos.$2, pos.$3), (10, 64, 20)),
      isTrue,
    );
    expect(markers.stationMarkers, hasLength(1));
    expect(sink.decorations, hasLength(1));
  });

  test('toggleStation twice removes the marker again', () {
    final sink = FakeSink();
    final markers = StationMapMarkers(sink);
    const at = (10, 64, 20);
    StationMarker? lookup(Pos pos) => markerAt(pos.$1, pos.$2, pos.$3);
    expect(markers.toggleStation(lookup, at), isTrue);
    expect(markers.toggleStation(lookup, at), isTrue);
    expect(markers.stationMarkers, isEmpty);
    expect(sink.decorations, isEmpty);
  });

  test('a station outside the map is refused (like Java: localX/localZ out of range)', () {
    final sink = FakeSink();
    final markers = StationMapMarkers(sink);
    // At scale 0 the map covers -63..63 local blocks; 200 blocks east is off the map.
    expect(
      markers.toggleStation((pos) => markerAt(pos.$1, pos.$2, pos.$3), (200, 64, 0)),
      isFalse,
    );
    expect(markers.stationMarkers, isEmpty);
  });

  test('load/save round-trips the marker list', () {
    final sink = FakeSink();
    final markers = StationMapMarkers(sink);
    StationMarker? lookup(Pos pos) => markerAt(pos.$1, pos.$2, pos.$3);
    markers.toggleStation(lookup, (10, 64, 20));
    final tag = CTag();
    markers.save(tag);
    final revived = StationMapMarkers(sink);
    revived.load(tag);
    expect(revived.stationMarkers.keys, markers.stationMarkers.keys);
  });
}
