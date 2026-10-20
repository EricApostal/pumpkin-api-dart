// The seam between Aeronautics and Simulated: balloons follow a structure that
// the physics assembler moves, and a split tells the balloons in its bounds to
// re-check their enclosure.
//
// Java has no such file: `Balloon.setAssembling(transform)` is called by Sable's
// assembly, and the split listener of the heat map hands the split blocks to
// whoever cares. The Dart split happens in `SimAssemblyHelper`, and the
// assembler and the swivel bearing announce their assemblies through
// `SimAssemblyEvents`; this is where Aeronautics subscribes.
//
// The dependency stays one way: `simulated` never imports `aeronautics`, it only
// offers the listener list.
//
// Pure: no host imports (both packages' assembly code is pure).
// create's positions are not exported from its barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart' show AssemblyTransform, BoundingBox3ic, Rotation;
import 'package:simulated/simulated.dart'
    show SimAssemblyEvents, SimAssemblyHelper, SimAssemblyResult, SimAssemblyWorld;

import 'hot_air/balloon_map.dart';
import 'hot_air/balloon_world.dart';

/// The assembly hooks Aeronautics installs on Simulated.
abstract final class SimulatedBridge {
  /// The worlds whose balloons take part, by world id.
  static final Map<String, BalloonWorld> _worlds = {};

  /// Removes the assembly listener; `null` while it is not installed.
  static void Function()? _removeAssembled;

  /// Removes the disassembly listener.
  static void Function()? _removeDisassembled;

  /// The balloon world with [worldId], or `null` when it is not one of ours.
  static BalloonWorld? worldById(String worldId) => _worlds[worldId];

  /// Subscribes to Simulated's assembly notifications and remembers [world] as
  /// a balloon world. Idempotent.
  static void install(BalloonWorld world) {
    _worlds[world.id] = world;
    if (_removeAssembled != null) return;

    _removeAssembled = SimAssemblyEvents.onAssembled((worldId, anchor, result) {
      final balloonWorld = worldById(worldId);
      if (balloonWorld != null) balloonsAssembled(balloonWorld, anchor, result);
    });

    // A sub-level placed back into the world: the blocks are already at their
    // final positions when this fires, so every balloon of the world re-checks
    // its enclosure from its controller. A volume that came back as blocks is
    // found again; one whose enclosure is gone leaks and stops lifting.
    //
    // The payload's `subLevel` is not read: `setAssembling` moved a balloon's
    // controller into the plot frame, so once the blocks are back the world is
    // the only source of truth, and the rebuild reads exactly that.
    _removeDisassembled = SimAssemblyEvents.onDisassembled((worldId, anchor, subLevel) {
      final balloonWorld = worldById(worldId);
      if (balloonWorld == null) return;

      final balloons = BalloonMap.of(balloonWorld);
      if (balloons.isEmpty) return;

      for (final balloon in balloons.allBalloons.toList()) {
        balloon.onAirtightBlockAdded(balloon.controllerPos);
      }
    });

    SimAssemblyHelper.registerSplitListener(_onSplit);
  }

  /// Forgets the worlds and removes every listener (plugin unload, tests).
  static void reset() {
    _removeAssembled?.call();
    _removeAssembled = null;
    _removeDisassembled?.call();
    _removeDisassembled = null;
    _worlds.clear();
  }

  /// `Balloon.setAssembling`: the balloons of [world] follow the assembly.
  ///
  /// [anchor] is the block the assembler worked from; [result] carries the new
  /// sub-level and the offset from [anchor] to the plot centre. A balloon's
  /// controller and bounds move with the same transform.
  static void balloonsAssembled(BalloonWorld world, Pos anchor, SimAssemblyResult result) {
    final map = BalloonMap.of(world);
    if (map.isEmpty) return;

    final plotAnchor = result.subLevel.getPlot().getCenterBlock();
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
        if (!balloon.bounds.intersects(bounds)) continue;
        balloon.onAirtightBlockAdded(balloon.controllerPos);
      }
    }
  }
}
