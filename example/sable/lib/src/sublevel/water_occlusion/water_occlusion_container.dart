// `dev.ryanhcode.sable.sublevel.water_occlusion`: regions of a sub-level that
// occlude water.
//
// A region is a bounded bit volume in the sub-level's local space. To test a
// world position the container finds the sub-level that contains the region and
// transforms the position into that sub-level's local space. Regions are not
// networked.
//
// Pure: no host imports (sub-level lookup is an interface).
import '../host/sub_level_host.dart';
import '../math/pose.dart';
import '../util/bounded_bit_volume3i.dart';

/// A water occlusion region.
final class WaterOcclusionRegion {
  final BoundedBitVolume3i _volume;
  bool _dirty = false;

  WaterOcclusionRegion(this._volume);

  /// The bit volume of the region.
  BoundedBitVolume3i getVolume() => _volume;

  /// Marks the region dirty (it needs to be sent to clients/rebaked).
  void markDirty() => _dirty = true;

  /// Whether the region is dirty.
  bool isDirty() => _dirty;

  /// Clears the dirty flag.
  void clearDirty() => _dirty = false;

  @override
  String toString() => 'WaterOcclusionRegion[$_volume, dirty=$_dirty]';
}

/// Stores the water occlusion regions of a level.
abstract class WaterOcclusionContainer<T extends WaterOcclusionRegion> {
  /// All water occlusion regions within this level.
  final Set<T> regions = {};

  /// The dimension this container belongs to.
  final String dimensionId;

  /// Resolves the sub-level a local region position belongs to.
  final SubLevelLookup lookup;

  /// Resolves a sub-level's pose by identity.
  final Pose3dc? Function(Object subLevel)? poseOf;

  WaterOcclusionContainer(this.dimensionId, this.lookup, {this.poseOf});

  /// The container of [level], when one was registered.
  static final Map<String, WaterOcclusionContainer<WaterOcclusionRegion>> _containers = {};

  /// The container of [level], or `null`.
  static WaterOcclusionContainer<WaterOcclusionRegion>? of(SableLevel level) =>
      _containers[level.dimensionId];

  /// Registers [container] for its level.
  static void register(WaterOcclusionContainer<WaterOcclusionRegion> container) =>
      _containers[container.dimensionId] = container;

  /// Removes the container of [level].
  static void unregister(SableLevel level) => _containers.remove(level.dimensionId);

  /// Whether [location] is in any water-occluded region.
  bool isOccluded((double, double, double) location) => getOccludingRegion(location) != null;

  /// The region occluding [location], or `null`.
  T? getOccludingRegion((double, double, double) location) {
    for (final region in regions) {
      final volume = region.getVolume();
      final min = volume.getMinBlockPos();
      final containing = lookup.containing(dimensionId, (min.$1.toDouble(), min.$2.toDouble(), min.$3.toDouble()));
      final pose = containing == null ? null : poseOf?.call(containing);

      final local = pose == null
          ? (location.$1, location.$2, location.$3)
          : pose.transformPositionInverseVec(location);

      if (volume.getOccupied(local.$1.floor(), local.$2.floor(), local.$3.floor())) {
        return region;
      }
    }
    return null;
  }

  /// Marks every region that touches [pos] or a neighbour dirty.
  void markDirty((int, int, int) pos) {
    const offsets = [
      (0, 0, 0),
      (1, 0, 0),
      (-1, 0, 0),
      (0, 1, 0),
      (0, -1, 0),
      (0, 0, 1),
      (0, 0, -1),
    ];
    for (final region in regions) {
      final volume = region.getVolume();
      for (final offset in offsets) {
        if (volume.getOccupied(pos.$1 + offset.$1, pos.$2 + offset.$2, pos.$3 + offset.$3)) {
          region.markDirty();
          break;
        }
      }
    }
  }

  /// Removes a region.
  void removeRegion(WaterOcclusionRegion region);

  /// Adds a region.
  WaterOcclusionRegion addRegion(BoundedBitVolume3i region);

  /// The regions of this container.
  Set<T> getRegions() => regions;
}

/// The server-side water occlusion container.
final class ServerWaterOcclusionContainer extends WaterOcclusionContainer<WaterOcclusionRegion> {
  ServerWaterOcclusionContainer(
    super.dimensionId,
    super.lookup, {
    super.poseOf,
  });

  @override
  void removeRegion(WaterOcclusionRegion region) => regions.remove(region);

  @override
  WaterOcclusionRegion addRegion(BoundedBitVolume3i region) {
    final created = WaterOcclusionRegion(region);
    regions.add(created);
    return created;
  }
}
