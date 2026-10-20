// The seam between Aeronautics and Simulated: balloons follow a structure that
// the physics assembler moves, and a split tells the balloons in its bounds to
// re-check their enclosure.
//
// Java has no such file: `Balloon.setAssembling(transform)` is called by Sable's
// assembly, and the split listener of the heat map hands the split blocks to
// whoever cares. The Dart split happens in `SimAssemblyHelper`, which keeps a
// listener list, so this is where Aeronautics subscribes.
//
// Pure: no host imports (both packages' assembly code is pure).
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart' show AssemblyTransform, BoundingBox3ic, Rotation;
import 'package:simulated/src/util/assembly/sim_assembly_contraption.dart' show SimAssemblyWorld;
import 'package:simulated/src/util/sim_assembly_helper.dart' show SimAssemblyHelper, SimAssemblyResult;

import 'hot_air/balloon_map.dart';
import 'hot_air/balloon_world.dart';

/// The assembly hooks Aeronautics installs on Simulated.
abstract final class SimulatedBridge {
  static bool _installed = false;

  /// The worlds whose balloons take part, by world id.
  static final Map<String, BalloonWorld> _worlds = {};

  /// Subscribes to Simulated's split listener and remembers [world] as a
  /// balloon world. Idempotent.
  static void install(BalloonWorld world) {
    _worlds[world.id] = world;
    if (_installed) return;
    _installed = true;
    SimAssemblyHelper.registerSplitListener(_onSplit);
  }

  /// Forgets the worlds and the subscription state (plugin unload, tests).
  static void reset() {
    _worlds.clear();
    _installed = false;
  }

  /// `Balloon.setAssembling`: the balloons of [world] follow [result].
  ///
  /// The assembler reports the new sub-level and the offset the blocks moved by;
  /// a balloon's controller and bounds move with the same offset.
  static void balloonsAssembled(BalloonWorld world, SimAssemblyResult result) {
    final map = BalloonMap.of(world);
    if (map.isEmpty) return;

    final plotAnchor = result.subLevel.getPlot().getCenterBlock();
    final anchor = (
      plotAnchor.$1 - result.offset.$1,
      plotAnchor.$2 - result.offset.$2,
      plotAnchor.$3 - result.offset.$3,
    );

    final transform = AssemblyTransform(
      anchor,
      plotAnchor,
      0,
      Rotation.none,
      world.level,
    );

    for (final balloon in map.allBalloons.toList()) {
      balloon.setAssembling(transform);
    }
  }

  /// A sub-level split: every balloon whose bounds touch [bounds] rebuilds, so a
  /// volume that was cut open leaks instead of lifting the wrong half.
  static void _onSplit(SimAssemblyWorld simWorld, BoundingBox3ic bounds, Set<Pos> blocks) {
    for (final world in _worlds.values) {
      final map = BalloonMap.of(world);
      if (map.isEmpty) continue;

      for (final balloon in map.allBalloons.toList()) {
        final balloonBounds = balloon.bounds;
        if (!balloonBounds.intersects(bounds)) continue;
        balloon.onAirtightBlockAdded(balloon.controllerPos);
      }
    }
  }
}
