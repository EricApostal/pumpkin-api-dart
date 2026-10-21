// `PlaceMergingGluePacket.handle`, minus the world.
//
// Two differences from the spring are easy to miss:
//
//  * the distance is measured between the **clicked** blocks, not the offset
//    ones (`Vec3.atCenterOf(parentPos)`, `childPos`), and it is compared with
//    `SimConfigService.assembly.mergingGlueRange` (4 blocks by default);
//  * both clicked blocks have to be inside a sub-level already, because the glue
//    joins two sub-levels — it cannot create one.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.PlaceMergingGluePacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart';

/// The placement rules of merging glue.
abstract final class MergingGluePlacement {
  /// Whether the click may place glue: the player holds glue, the two clicks are
  /// within [range] blocks, and both sides are already in a sub-level.
  static bool canPlace({
    required bool holdingGlue,
    required double distanceSquared,
    required double range,
    required bool parentInSubLevel,
    required bool childInSubLevel,
  }) =>
      holdingGlue &&
      distanceSquared <= range * range &&
      parentInSubLevel &&
      childInSubLevel;

  /// The block a glue end attaches to: the clicked block, offset by the face the
  /// player clicked.
  static Pos relativeEnd(Pos clicked, Direction facing) => clicked.relative(facing);
}
