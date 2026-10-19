// What the contraption logic needs from a world (pure). The host implements it over a
// `World` and the block entity store (`host/host_level.dart`); the tests use a map.
import '../../api/block_state.dart';
import '../../common/common.dart';
import 'nbt_map.dart';
import 'structure_info.dart';

/// `PushReaction` of a block state.
enum PushReaction {
  /// Pushed and pulled by pistons.
  normal,

  /// Broken by pistons.
  destroy,

  /// Cannot be moved (`IMMOVEABLE`).
  block,

  /// Entities-only: not a block reaction.
  ignore,

  /// Pushed but not pulled (`PUSH`).
  pushOnly;

  static PushReaction fromName(String? name) => switch (name) {
    'destroy' => destroy,
    'block' => block,
    'ignore' => ignore,
    'push_only' || 'pushOnly' || 'push-only' => pushOnly,
    _ => normal,
  };
}

/// A block entity as a contraption captures it.
final class CapturedBlockEntity {
  /// The registry key of the block entity type (`create:chassis`, `minecraft:chest`).
  final String typeKey;

  /// The saved data (`saveWithFullMetadata` minus the position), including `id`.
  final NbtMap saved;

  /// The client update tag (`getUpdateTag`).
  final NbtMap update;

  const CapturedBlockEntity(this.typeKey, this.saved, this.update);
}

/// A super glue box in the world (`SuperGlueEntity`).
final class GlueRef {
  /// The host entity id.
  final int id;

  /// The box in world coordinates.
  final Aabb box;

  const GlueRef(this.id, this.box);

  /// `SuperGlueEntity.contains(pos)`: the block centre is inside.
  bool contains(Pos p) => box.contains(p.center);

  @override
  bool operator ==(Object other) => other is GlueRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A minecart in the world (the part a mounted contraption needs).
final class MinecartRef {
  final int id;
  final String uuid;
  final String typeKey;

  /// `CartAssemblerBlock.canAssembleTo(cart)`: rideable, furnace or chest minecarts.
  final bool canAssemble;
  final Vec3 position;

  const MinecartRef(this.id, this.uuid, this.typeKey, this.canAssemble, this.position);
}

/// A read view of the world for contraptions, with the hooks assembly has side effects through.
abstract class ContraptionLevel extends BlockGetter {
  /// `Level.isOutsideBuildHeight`.
  bool isOutsideBuildHeight(Pos p);

  /// The lowest build height (`Level.getMinY`).
  int get minY;

  /// The block entity at [p] as a contraption saves it, `null` without one.
  CapturedBlockEntity? blockEntityAt(Pos p);

  /// `BlockState.getPistonPushReaction`.
  PushReaction pushReaction(BState state);

  /// `getDestroySpeed(...) == -1`.
  bool isUnbreakable(BState state);

  /// `BlockState.is(TagKey)` for a state that is not in the world.
  bool stateHasTag(BState state, String tag);

  /// The limits of the config.
  ContraptionSettings get settings;

  /// Glue boxes whose box intersects [area], world coordinates.
  List<GlueRef> gluesIn(Aabb area) => const [];

  /// Removes the glue entity (`glue.discard()`).
  void discardGlue(GlueRef glue) {}

  /// The uuid of the first passenger of the seat entity at [pos], `null` for none.
  String? seatPassengerAt(Pos pos) => null;

  /// Minecarts whose box intersects the block at [pos].
  List<MinecartRef> minecartsAt(Pos pos) => const [];

  /// Moves a minecart to a position (`setPos`).
  void moveMinecart(MinecartRef cart, Vec3 position) {}

  /// `world.scheduleTick(pos, block, -1)`: a button or pressure plate that is captured unpowered.
  void scheduleBlockTick(Pos pos, String blockKey) {}

  /// `WindmillBearingBlockEntity.disassembleForMovement()`.
  void disassembleWindmillBearing(Pos pos) {}

  /// `ChainConveyorBlockEntity.notifyConnectedToValidate()`.
  void notifyChainConveyor(Pos pos) {}

  /// Whether the actuator block entity at [pos] (a bearing, clockwork bearing or pulley)
  /// currently runs a contraption.
  bool isActuatorRunning(Pos pos) => false;

  /// `ConnectivityHandler.isConnected(world, a, b)`: two blocks of one multiblock (fluid tank,
  /// item vault).
  bool isConnected(Pos a, Pos b) {
    final x = blockEntityAt(a);
    final y = blockEntityAt(b);
    if (x == null || y == null) return false;
    Pos controllerOf(Pos p, CapturedBlockEntity be) => be.saved.contains('Controller') ? be.saved.getBlockPos('Controller') : p;
    return controllerOf(a, x) == controllerOf(b, y);
  }

  /// `BlockState.getCollisionShape(...).isEmpty()` for a state not in the world.
  bool stateCollisionEmpty(BState state);

  /// `BlockState.canBeReplaced()` for a state not in the world.
  bool stateReplaceable(BState state);

  /// `BlockState.isRedstoneConductor` of the block at [p].
  bool isRedstoneConductor(Pos p) => isCollisionShapeFullBlock(p);
}
