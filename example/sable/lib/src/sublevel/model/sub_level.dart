// `dev.ryanhcode.sable.sublevel.SubLevel`: a subdivision of a level, containing
// an isolated chunk grid (stored in a `LevelPlot`) and an isometry — a 3D pose
// with translation, rotation and scale.
//
// Pure: no host imports.
import '../api/sub_level_access.dart';
import '../host/sub_level_host.dart';
import '../math/bounding_box.dart';
import '../math/pose.dart';
import '../math/vector.dart';
import 'level_plot.dart';
import 'sub_level_container.dart';

/// A subdivision of a level, containing an isolated chunk grid and a pose.
abstract class SubLevel implements SubLevelAccess {
  /// The parent level of this sub-level.
  final SableLevel level;

  /// The current, logical pose.
  final Pose3d _pose;

  /// The logical pose from the previous tick.
  final Pose3d _lastPose;

  /// The global bounding box of this sub-level; updated per tick to reflect the
  /// current pose.
  final BoundingBox3d globalBounds = BoundingBox3d();

  /// The last global bounding box of this sub-level.
  final BoundingBox3d lastGlobalBounds = BoundingBox3d();

  final Matrix4d _globalBoundsTransform = Matrix4d();

  /// The plot of this sub-level.
  late final LevelPlot plot;

  /// The plot container of the level.
  late final SubLevelContainer container;

  bool _isRemoved = false;

  /// The unique ID of this sub-level: persists for its lifetime, is consistent
  /// between client and server, and survives serialization.
  String? _uniqueId;

  String? _name;

  /// Creates a new sub-level with the given parent level and pose.
  ///
  /// [plotX] and [plotZ] are the *global* plot coordinates.
  SubLevel(this.level, int plotX, int plotZ, Pose3d pose)
    : _pose = Pose3d.copy(pose),
      _lastPose = Pose3d.copy(pose) {
    final plotContainer = SubLevelContainer.of(level);
    if (plotContainer == null) {
      throw StateError('Level does not have a plot container');
    }
    container = plotContainer;
    plot = createPlot(plotContainer, plotX, plotZ, plotContainer.logPlotSize);
  }

  /// Creates the plot for this sub-level.
  ///
  /// [plotX] and [plotZ] are the global plot coordinates; [logPlotSize] is the
  /// log_2 of the side length of a plot, in chunks.
  LevelPlot createPlot(SubLevelContainer plotContainer, int plotX, int plotZ, int logPlotSize);

  /// Called when the bounds of the inner plot have changed.
  void onPlotBoundsChanged() {}

  /// Sets the last pose to the current pose.
  void updateLastPose() => _lastPose.set(_pose);

  /// Ticks this sub-level, updating the global bounding box and components.
  void tick() => plot.tick();

  /// Recomputes [globalBounds] from the plot bounds and the current pose.
  void updateBoundingBox() {
    final plotBounds = plot.getBoundingBox();
    lastGlobalBounds.set(globalBounds);

    // `BoundingBox3i.empty` is inverted (min at INT_MAX, max at INT_MIN); a plot
    // with no solid blocks has no global bounds, so the box collapses onto the
    // pose position instead of becoming a 268-million-chunk span.
    if (plotBounds.maxX < plotBounds.minX ||
        plotBounds.maxY < plotBounds.minY ||
        plotBounds.maxZ < plotBounds.minZ) {
      final position = _pose.position();
      globalBounds.setValues(position.x, position.y, position.z, position.x, position.y, position.z);
      return;
    }

    globalBounds.setValues(
      plotBounds.minX.toDouble(),
      plotBounds.minY.toDouble(),
      plotBounds.minZ.toDouble(),
      plotBounds.maxX + 1.0,
      plotBounds.maxY + 1.0,
      plotBounds.maxZ + 1.0,
    );
    globalBounds.transformWith(_pose, _globalBoundsTransform);
  }

  /// Copies the current global bounds into the last ones (Java
  /// `forceUpdateGlobalBounds`).
  void forceUpdateGlobalBounds() => lastGlobalBounds.set(globalBounds);

  /// The parent level of this sub-level.
  SableLevel getLevel() => level;

  @override
  Pose3dc get logicalPose => _pose;

  /// The current, mutable pose.
  Pose3d get pose => _pose;

  @override
  Pose3dc get lastPose => _lastPose;

  /// The mutable last pose.
  Pose3d get mutableLastPose => _lastPose;

  @override
  BoundingBox3dc get boundingBox => globalBounds;

  /// The plot containing the contents of this sub-level.
  LevelPlot getPlot() => plot;

  /// Removes this sub-level from the parent level.
  void onRemove() {
    plot.onRemove();
    markRemoved();
  }

  /// Whether this sub-level is removed / marked for removal.
  bool isRemoved() => _isRemoved;

  /// Marks this sub-level as removed; the container removes it on its next tick.
  void markRemoved() => _isRemoved = true;

  /// Sets the unique ID (assigned by the container when it allocates the plot).
  void setUniqueId(String uniqueId) => _uniqueId = uniqueId;

  @override
  String get uniqueId => _uniqueId ?? (throw StateError('Sub-level has no unique ID yet'));

  /// The unique ID, or `null` before the container assigned one.
  String? get uniqueIdOrNull => _uniqueId;

  @override
  String? get name => _name;

  /// Sets the display name; `null` means "no name".
  void setName(String? name) => _name = name;

  /// The position vector of the pose (Java exposes it mutably).
  Vector3d get position => _pose.position();

  @override
  String toString() => '[name=$_name, id=$_uniqueId, global_plot=${plot.plotPos.$1},${plot.plotPos.$2}]';
}
