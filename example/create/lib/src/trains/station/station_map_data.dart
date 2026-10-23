// `StationMapData` (pure): the station markers of a filled map (`MapItemSavedDataMixin`). The map
// itself and its decorations belong to the host; the markers and the rules of when a station is
// toggled, checked and added are here, with the map's geometry and its decorations behind
// [StationMapSink].
//
// The map side of this is a host gap: nothing here is reachable from wasm yet -- a plugin can read
// neither the filled map's `minecraft:map_id` nor the `MapData` behind it
// (`pumpkin-core/src/world/map.rs` holds the center, the scale and the decorations, kept entirely
// host-side), so [StationMapMarkers] has no [StationMapSink] implementation and is driven by
// nobody. The named primitives are in `docs/host-gaps.md` ("Map saved data"). The rules themselves
// are complete and testable against a fake sink.
import '../../common/common.dart';
import '../../redstone/support/text.dart' show Txt;
import '../util/ctag.dart';
import 'station_marker.dart';

/// `StationMapData`.
abstract interface class StationMapData {
  /// `toggleStation(level, pos, stationBlockEntity)`: adds the marker of the station at [pos], or
  /// removes it when it is on the map already. [lookup] finds station markers by block entity
  /// position (the lookup returns `null` for stations without a graph station).
  bool toggleStation(StationMarkerLookup lookup, Pos pos);

  /// `addStationMarker(marker)`.
  void addStationMarker(StationMarker marker);
}

/// What the markers need of the map they belong to.
abstract interface class StationMapSink {
  /// `centerX`.
  int get centerX;

  /// `centerZ`.
  int get centerZ;

  /// `scale`.
  int get scale;

  /// `decorations.put(id, createStationDecoration(x, z, name))`: shows the marker at the map position.
  void putDecoration(String id, int x, int z, Txt name);

  /// `removeDecoration(id)`.
  void removeDecoration(String id);

  /// `isTrackedCountOverLimit(limit)`.
  bool isTrackedCountOverLimit(int limit);
}

/// The marker state of one map (the fields the mixin adds to `MapItemSavedData`).
class StationMapMarkers implements StationMapData {
  static const String stationMarkersKey = 'create:stations';

  final StationMapSink map;
  final Map<String, StationMarker> stationMarkers = {};

  StationMapMarkers(this.map);

  /// The `load` injection: restores the markers of the saved `create:stations` list.
  void load(CTag tag) {
    for (final c in tag.getCompoundList(stationMarkersKey)) {
      addStationMarker(StationMarker.load(c));
    }
  }

  /// The `save` injection.
  void save(CTag tag) {
    tag.putCompoundList(stationMarkersKey, [for (final m in stationMarkers.values) m.save()]);
  }

  @override
  void addStationMarker(StationMarker marker) {
    stationMarkers[marker.getId()] = marker;

    final scaleMultiplier = 1 << map.scale;
    final localX = (marker.getTarget().x - map.centerX) / scaleMultiplier;
    final localZ = (marker.getTarget().z - map.centerZ) / scaleMultiplier;

    if (localX < -63.0 || localX > 63.0 || localZ < -63.0 || localZ > 63.0) {
      map.removeDecoration(marker.getId());
      return;
    }

    final localXByte = _toByte((localX * 2.0 + 0.5).toInt());
    final localZByte = _toByte((localZ * 2.0 + 0.5).toInt());

    map.putDecoration(marker.getId(), localXByte, localZByte, marker.getName());
  }

  static int _toByte(int v) => v.toSigned(8);

  @override
  bool toggleStation(StationMarkerLookup lookup, Pos pos) {
    final xCenter = pos.x + 0.5;
    final zCenter = pos.z + 0.5;
    final scaleMultiplier = 1 << map.scale;

    final localX = (xCenter - map.centerX) / scaleMultiplier;
    final localZ = (zCenter - map.centerZ) / scaleMultiplier;

    if (localX < -63.0 || localX > 63.0 || localZ < -63.0 || localZ > 63.0) return false;

    final marker = StationMarker.fromWorld(lookup, pos);
    if (marker == null) return false;

    final existing = stationMarkers[marker.getId()];
    if (existing != null && existing == marker) {
      stationMarkers.remove(marker.getId());
      map.removeDecoration(marker.getId());
      return true;
    }

    if (!map.isTrackedCountOverLimit(256)) {
      addStationMarker(marker);
      return true;
    }

    return false;
  }

  /// `create$checkStations(level, x, z)`: after the banners of the chunk were checked, markers whose
  /// target is in that column are refreshed from the world.
  void checkStations(StationMarkerLookup lookup, int x, int z) {
    final newMarkers = <StationMarker>[];

    for (final marker in stationMarkers.values.toList()) {
      if (marker.getTarget().x == x && marker.getTarget().z == z) {
        final other = StationMarker.fromWorld(lookup, marker.getSource());
        if (marker != other) {
          stationMarkers.remove(marker.getId());
          map.removeDecoration(marker.getId());

          if (other != null && marker.getTarget() == other.getTarget()) newMarkers.add(other);
        }
      }
    }

    for (final marker in newMarkers) {
      addStationMarker(marker);
    }
  }
}
