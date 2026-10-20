// `dev.ryanhcode.sable.sublevel.tracking_points`: where a player was when they
// left, in sub-level space.
//
// A tracking point either sits in a sub-level (with a local position and,
// optionally, the pointer to where that sub-level is saved) or in the world.
// When the sub-level is deleted, its points are projected into the world; when
// the player logs back in, `take` resolves the point against the live
// sub-level, the holding chunk map, or the save file.
//
// Pure: no host imports (the lookups are callbacks).
import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import '../storage/holding/saved_pointer.dart';
import '../storage/holding_sub_level.dart';
import '../storage/serialization/sub_level_data.dart';
import '../util/sable_nbt.dart';
import '../util/uuid.dart';

/// One tracking point.
///
/// [globalPlaceholderPosition] is a world position stored for points made before
/// a sub-level was ever saved; it is dropped when the sub-level moves and is
/// saved.
final class TrackingPoint {
  final bool inSubLevel;
  final String? subLevelId;
  final GlobalSavedSubLevelPointer? lastSavedSubLevelPointer;
  final Vector3d point;
  final Vector3d? globalPlaceholderPosition;

  TrackingPoint(
    this.inSubLevel,
    this.subLevelId,
    this.lastSavedSubLevelPointer,
    Vector3d point, [
    this.globalPlaceholderPosition,
  ]) : point = Vector3d.copy(point);

  /// A point in the world.
  factory TrackingPoint.inWorld(Vector3d point) =>
      TrackingPoint(false, null, null, point, null);

  @override
  String toString() => 'TrackingPoint[inSubLevel=$inSubLevel, subLevelId=$subLevelId, '
      'pointer=$lastSavedSubLevelPointer, point=$point, placeholder=$globalPlaceholderPosition]';
}

/// The result of consuming a tracking point.
final class TakenLoginPoint {
  final Vector3d position;
  final String? subLevelId;
  final Vector3d? localAnchor;

  const TakenLoginPoint(this.position, this.subLevelId, this.localAnchor);

  @override
  String toString() => 'TakenLoginPoint[$position, subLevelId=$subLevelId, anchor=$localAnchor]';
}

/// `SubLevelTrackingPointSavedData`: the tracking points of one level.
final class TrackingPointStore {
  final Map<String, TrackingPoint> _points = {};

  /// All points, by UUID.
  Iterable<MapEntry<String, TrackingPoint>> getAllTrackingPoints() => _points.entries.toList();

  /// The point of [uuid], or `null`.
  TrackingPoint? getTrackingPoint(String uuid) => _points[uuid];

  /// Sets the point of [uuid].
  void setTrackingPoint(String uuid, TrackingPoint point) => _points[uuid] = point;

  /// Removes the point of [uuid].
  void removeTrackingPoint(String uuid) => _points.remove(uuid);

  /// The points whose local position is inside [bounds].
  Iterable<MapEntry<String, TrackingPoint>> pointsIn(BoundingBox3ic bounds) =>
      _points.entries.where((entry) => bounds.containsVec(entry.value.point));

  /// `load`.
  static TrackingPointStore load(Map<String, Object?> tag) {
    final store = TrackingPointStore();
    final raw = tag['tracking_points'];
    if (raw is! Map) return store;

    for (final entry in raw.entries) {
      final key = entry.key as String;
      final pointTag = entry.value;
      if (pointTag is! Map) continue;
      final map = Map<String, Object?>.from(pointTag);

      final inSubLevel = map['InSubLevel'] == true || map['InSubLevel'] == 1;
      final pointerTag = map['SubLevelPointer'];
      final pointer = pointerTag is Map
          ? GlobalSavedSubLevelPointer.fromMap(Map<String, Object?>.from(pointerTag))
          : null;
      final point = SableNbt.readVector3d(map['Point']);

      final placeholderTag = map['GlobalPlaceholder'];
      final placeholder = placeholderTag == null ? null : SableNbt.readVector3d(placeholderTag);

      final subLevelIdTag = map['SubLevelID'];
      final subLevelId = subLevelIdTag == null ? null : SableNbt.readUuid(subLevelIdTag);

      store._points[key] = TrackingPoint(inSubLevel, subLevelId, pointer, point, placeholder);
    }
    return store;
  }

  /// `serializeTag`.
  Map<String, Object?> save() {
    final points = <String, Object?>{};
    for (final entry in _points.entries) {
      final point = entry.value;
      points[entry.key] = <String, Object?>{
        'InSubLevel': point.inSubLevel,
        if (point.lastSavedSubLevelPointer != null)
          'SubLevelPointer': point.lastSavedSubLevelPointer!.toMap(),
        'Point': SableNbt.writeVector3d(point.point),
        if (point.globalPlaceholderPosition != null)
          'GlobalPlaceholder': SableNbt.writeVector3d(point.globalPlaceholderPosition!),
        if (point.subLevelId != null) 'SubLevelID': uuidToInts(point.subLevelId!),
      };
    }
    return {'tracking_points': points};
  }

  /// Generates a tracking point for [player] at their current position, in
  /// [subLevel].
  ///
  /// [pointer] is the sub-level's last save pointer (`null` for a sub-level
  /// that was never saved, which stores a global placeholder instead).
  String generateTrackingPoint(
    SablePlayer player, {
    required String subLevelId,
    required Pose3dc pose,
    GlobalSavedSubLevelPointer? pointer,
    String? uuid,
  }) {
    final global = Vector3d(player.position.$1, player.position.$2, player.position.$3);
    final local = pose.transformPositionInverse(global);
    final point = TrackingPoint(
      true,
      subLevelId,
      pointer,
      local,
      pointer == null ? Vector3d.copy(global) : null,
    );
    final key = uuid ?? player.uuid;
    _points[key] = point;
    return key;
  }

  /// Generates a tracking point at [worldPosition] in [subLevel].
  String generateTrackingPointAt(
    (double, double, double) worldPosition, {
    required String subLevelId,
    required Pose3dc pose,
    GlobalSavedSubLevelPointer? pointer,
    String? uuid,
  }) {
    final global = Vector3d(worldPosition.$1, worldPosition.$2, worldPosition.$3);
    final point = TrackingPoint(
      true,
      subLevelId,
      pointer,
      Vector3d.copy(global),
      pointer == null ? pose.transformPosition(Vector3d.copy(global)) : null,
    );
    final key = uuid ?? randomKey();
    _points[key] = point;
    return key;
  }

  /// `take`: resolves the point of [uuid], optionally removing it.
  ///
  /// [containing] finds the live sub-level at a local point; [holdingSubLevel]
  /// finds a sub-level in a holding chunk by UUID; [loadSaved] reads a
  /// sub-level's data from its save pointer.
  TakenLoginPoint? take(
    String uuid, {
    bool remove = false,
    ({Pose3dc pose, String id})? Function(Vector3d local)? containing,
    HoldingSubLevel? Function(String subLevelId)? holdingSubLevel,
    SubLevelData? Function(GlobalSavedSubLevelPointer pointer)? loadSaved,
  }) {
    final point = remove ? _points.remove(uuid) : _points[uuid];
    if (point == null) return null;

    if (!point.inSubLevel) {
      return TakenLoginPoint(Vector3d.copy(point.point), null, null);
    }

    final live = containing?.call(point.point);
    if (live != null) {
      return TakenLoginPoint(
        live.pose.transformPosition(Vector3d.copy(point.point)),
        live.id,
        Vector3d.copy(point.point),
      );
    }

    final subLevelId = point.subLevelId;
    if (subLevelId != null) {
      final holding = holdingSubLevel?.call(subLevelId);
      if (holding != null) {
        return TakenLoginPoint(
          holding.data.pose.transformPosition(Vector3d.copy(point.point)),
          holding.data.uuid,
          Vector3d.copy(point.point),
        );
      }
    }

    final pointer = point.lastSavedSubLevelPointer;
    if (pointer != null && loadSaved != null) {
      final data = loadSaved(pointer);
      if (data != null) {
        return TakenLoginPoint(
          data.pose.transformPosition(Vector3d.copy(point.point)),
          data.uuid,
          Vector3d.copy(point.point),
        );
      }
      return null;
    }

    final placeholder = point.globalPlaceholderPosition;
    return placeholder == null ? null : TakenLoginPoint(Vector3d.copy(placeholder), null, null);
  }

  static String randomKey() => randomUuidV4();
}
