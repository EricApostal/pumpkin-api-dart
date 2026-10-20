// What the balloon model needs from the world: block states, the airtight test
// and the vertical bounds. The plugin implements it over `pumpkin_api`'s
// `World`; tests implement it over a map.
//
// Java reads `Level` directly (`LevelAccelerator` caches chunk lookups). The
// port keeps the same shape: one object per world, created once per balloon
// operation.
//
// Pure: no host imports.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/common/direction.dart' show Direction;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:sable/sable.dart' show SableLevel;

/// The block access a balloon flood fill needs.
abstract interface class BalloonWorld {
  /// The world id (`World.getId()`), the key of the balloon map.
  String get id;

  /// The level as the sub-level model sees it (pressure, gravity, sub-levels).
  SableLevel get level;

  /// `Level.getMinBuildHeight()`.
  int get minY;

  /// `Level.getMaxBuildHeight() - 1`.
  int get maxY;

  /// The state at a global block position.
  BState stateAt(int x, int y, int z);

  /// `state.is(AeroTags.BlockTags.AIRTIGHT)`.
  bool isAirtight(BState state);

  /// Whether the world is the server side (only the server owns balloons).
  bool get isServerSide;

  /// The state at a block position.
  BState stateAtPos(Pos pos) => stateAt(pos.$1, pos.$2, pos.$3);

  /// The state next to [pos] in [direction].
  BState stateAtOffset(Pos pos, Direction direction) =>
      stateAt(pos.$1 + direction.stepX, pos.$2 + direction.stepY, pos.$3 + direction.stepZ);
}
