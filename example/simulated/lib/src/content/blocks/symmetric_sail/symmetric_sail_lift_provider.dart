// The symmetric sail: a sail that lifts along its axis and drags along its
// plane, and that can be dyed together with the sails next to it.
//
// Java implements `BlockSubLevelLiftProvider` on the block itself. A Dart block
// is a data object (`CreateBlock`), so the provider is a separate object that the
// index registers for every sail colour, and the block key tells it which normal
// to report.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.symmetric_sail.SymmetricSailBlock
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Axis, Direction;
// sable does not export `LiftProviderContext` from its barrel; the lift provider
// signature names it.
// ignore_for_file: implementation_imports
import 'package:sable/sable.dart'
    show
        BlockSubLevelLiftProvider,
        LiftProviderContext,
        LiftProviderGroup,
        Pose3d,
        ServerSubLevel,
        Vector3d;

/// The lift provider of a symmetric sail.
///
/// Java: `SymmetricSailBlock implements BlockSubLevelLiftProvider`
final class SymmetricSailLiftProvider implements BlockSubLevelLiftProvider {
  /// The drag along the sail's plane (`sable$getParallelDragScalar`).
  static const double parallelDrag = 1.75;

  const SymmetricSailLiftProvider();

  /// `sable$getNormal(state)`: the positive side of the sail's axis.
  @override
  Direction sable$getNormal(BState state) {
    final axis = state['axis'] ?? 'y';
    return switch (axis) {
      'x' => Direction.east,
      'z' => Direction.south,
      _ => Direction.up,
    };
  }

  /// `sable$getLiftScalar()`: the sail does not lift on its own; the wind pushes
  /// it.
  @override
  double sable$getLiftScalar() => 0;

  /// `sable$getParallelDragScalar()`.
  @override
  double sable$getParallelDragScalar() => parallelDrag;

  /// `sable$getDirectionlessDragScalar()`: the sail does not add directionless
  /// drag; its lift comes from the pressure on the sheet.
  @override
  double sable$getDirectionlessDragScalar() => 0;

  /// `sable$contributeLiftAndDrag`: the default contribution of sable.
  @override
  void sable$contributeLiftAndDrag(
    LiftProviderContext ctx,
    ServerSubLevel subLevel,
    Pose3d? localPose,
    double timeStep,
    Vector3d linearVelocity,
    Vector3d angularVelocity,
    Vector3d linearImpulse,
    Vector3d angularImpulse, [
    LiftProviderGroup? group,
  ]) => BlockSubLevelLiftProvider.contributeLiftAndDrag(
    this,
    ctx,
    subLevel,
    localPose,
    timeStep,
    linearVelocity,
    angularVelocity,
    linearImpulse,
    angularImpulse,
    group,
  );
}

/// The dye behaviour of the symmetric sails.
///
/// Java: `SymmetricSailBlock#applyDye`, with the world replaced by the callbacks.
abstract final class SymmetricSailDye {
  /// The block key of the sail of [colour] (`simulated:<colour>_symmetric_sail`).
  static String sailKey(String colour) => 'simulated:${colour}_symmetric_sail';

  /// The colour of a sail block key, or `null` when it is not a sail.
  static String? colourOf(String blockKey) {
    const prefix = 'simulated:';
    const suffix = '_symmetric_sail';
    if (!blockKey.startsWith(prefix) || !blockKey.endsWith(suffix)) return null;
    return blockKey.substring(prefix.length, blockKey.length - suffix.length);
  }

  /// `applyDye(state, world, pos, hit, colour)`.
  ///
  /// Dyes the sail itself, else the first neighbour across its axis that is a
  /// sail of another colour on the same axis, else the whole connected sheet (at
  /// most 100 steps). [neighbourAt] and [setAt] take offsets relative to the
  /// clicked block.
  static void applyDye({
    required BState state,
    required String colour,
    required BState Function((int, int, int) offset) neighbourAt,
    required void Function((int, int, int) offset, BState newState) setAt,
  }) {
    final newKey = sailKey(colour);
    final target = BState(newKey, state.props);

    if (state.key != newKey) {
      setAt((0, 0, 0), target);
      return;
    }

    final axis = state['axis'] ?? 'y';
    final acrossAxis = [
      for (final direction in Direction.values)
        if (_axisName(direction.axis) != axis) direction,
    ];

    for (final direction in acrossAxis) {
      final offset = (direction.stepX, direction.stepY, direction.stepZ);
      final adjacent = neighbourAt(offset);
      if (colourOf(adjacent.key) == null) continue;
      if ((adjacent['axis'] ?? 'y') != axis) continue;
      if (adjacent.key == state.key) continue;
      setAt(offset, BState(newKey, adjacent.props));
      return;
    }

    // The connected sheet: breadth first over the four directions across the
    // sail's axis, at most 100 steps.
    final visited = <(int, int, int)>{(0, 0, 0)};
    final frontier = <(int, int, int)>[(0, 0, 0)];
    var timeout = 100;
    while (frontier.isNotEmpty) {
      if (timeout-- < 0) break;
      final current = frontier.removeAt(0);

      for (final direction in acrossAxis) {
        final offset = (
          current.$1 + direction.stepX,
          current.$2 + direction.stepY,
          current.$3 + direction.stepZ,
        );
        if (visited.contains(offset)) continue;
        final adjacent = neighbourAt(offset);
        if (colourOf(adjacent.key) == null) continue;
        if ((adjacent['axis'] ?? 'y') != axis) continue;
        if (adjacent.key != state.key) {
          setAt(offset, BState(newKey, adjacent.props));
        }
        frontier.add(offset);
        visited.add(offset);
      }
    }
  }

  static String _axisName(Axis axis) => switch (axis) {
    Axis.x => 'x',
    Axis.y => 'y',
    Axis.z => 'z',
  };
}
