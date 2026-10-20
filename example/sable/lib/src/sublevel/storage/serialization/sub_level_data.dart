// `dev.ryanhcode.sable.sublevel.storage.serialization.SubLevelData`: a
// half-loaded sub-level: its identity, bounds and pose, its loading
// dependencies, and the full tag it will be loaded from.
//
// Pure: no host imports.
import '../../math/bounding_box.dart';
import '../../math/pose.dart';

/// A half-loaded sub-level data stored inside a chunk.
final class SubLevelData {
  final String uuid;
  final BoundingBox3d bounds;
  final Pose3d pose;

  /// The sub-levels that must be loaded with this one.
  final List<String> relations;

  /// The full serialized tag (what `SubLevelSerializer` wrote).
  final Map<String, Object?> fullTag;

  /// The chunk this was loaded from, set by the storage when read from disk.
  (int, int)? originLoadedChunk;

  SubLevelData(this.uuid, this.bounds, this.pose, this.relations, this.fullTag);

  /// The chunk this data was loaded from.
  (int, int)? getOriginLoadedChunk() => originLoadedChunk;

  /// Sets the chunk this data was loaded from.
  void setOriginLoadedChunk((int, int)? chunk) => originLoadedChunk = chunk;

  @override
  bool operator ==(Object other) =>
      other is SubLevelData &&
      other.uuid == uuid &&
      other.bounds == bounds &&
      other.pose == pose &&
      _listEquals(other.relations, relations) &&
      other.fullTag == fullTag;

  @override
  int get hashCode => Object.hash(uuid, bounds, pose, Object.hashAll(relations));

  @override
  String toString() => 'HalfLoadedSubLevel[uuid=$uuid, bounds=$bounds, pose=$pose, '
      'relations=$relations]';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
