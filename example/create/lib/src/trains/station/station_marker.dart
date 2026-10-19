// `StationMarker` (pure): a station shown on a map - where the station block is, the track point
// the marker points at and the name of the station.
import 'dart:convert';

import '../../common/common.dart';
import '../../redstone/support/text.dart' show Txt, plainTextOfJson, tryParseJson;
import '../util/ctag.dart';

/// Looks up the marker of the station at a position (`StationMarker.fromWorld(level, pos)`):
/// `null` when there is no station block entity there or it has no station.
typedef StationMarkerLookup = StationMarker? Function(Pos pos);

/// `StationMarker`.
class StationMarker {
  final Pos _source;
  final Pos _target;
  final Txt _name;
  final String _id;

  /// `new StationMarker(source, target, name)`.
  StationMarker(Pos source, Pos target, Txt name)
    : _source = source,
      _target = target,
      _name = name,
      _id = 'create:station-${target.x},${target.y},${target.z}';

  /// `load(tag, registries)`.
  static StationMarker load(CTag tag) {
    final source = tag.getBlockPos('source');
    final target = tag.getBlockPos('target');
    final json = tryParseJson(tag.getString('name'));
    final name = json == null ? Txt.empty() : Txt.literal(plainTextOfJson(json));
    return StationMarker(source, target, name);
  }

  /// `fromWorld(level, pos)` over a [lookup] of the station block entities: [name] is the station
  /// name, [mapMarkerPos] the `TrackTargetingBehaviour.getPositionForMapMarker()`.
  static StationMarker? fromWorld(StationMarkerLookup lookup, Pos pos) => lookup(pos);

  /// `save(registries)`.
  CTag save() {
    final tag = CTag();
    tag.putBlockPos('source', _source);
    tag.putBlockPos('target', _target);
    tag.putString('name', jsonEncode(_name.toJson()));
    return tag;
  }

  Pos getSource() => _source;

  Pos getTarget() => _target;

  Txt getName() => _name;

  String getId() => _id;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StationMarker) return false;
    return _target == other._target && jsonEncode(_name.toJson()) == jsonEncode(other._name.toJson());
  }

  @override
  int get hashCode => Object.hash(_target, jsonEncode(_name.toJson()));
}
