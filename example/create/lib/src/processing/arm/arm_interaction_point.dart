// `ArmInteractionPoint`: one block the mechanical arm can take items from or deposit items into.
// The point type decides what the point accepts; the point itself does the item transfer through
// the block's item storage.
//
// Ported from `content/kinetics/mechanicalArm/ArmInteractionPoint.java` and the point subclasses
// of `AllArmInteractionPointTypes.java`. The host exposes containers through `ItemHandlers`, so
// points that are not plugin inventories use that; plugin machines (crafter, deployer, ...) use
// their own storage.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/core/structure_transform.dart';
import '../../conveyance/items/stack_bridge.dart';
import '../../conveyance/transport/funnel/funnel_block_entity.dart';
import '../../core/block_entity.dart';
import '../support/kinetics_bridge.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../crafter/machine_support.dart'
    show bStateOf, dropPStack, sharedCraftingRecipes;
import '../crafter/mechanical_crafter_block_entity.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../transport/transport_behaviours.dart';
import 'arm_block_entity.dart';
import 'arm_model.dart';

/// The world view of the arm's interaction points.
final class ArmWorld {
  final String worldId;
  final World? world;
  final BlockEntityStore store;

  const ArmWorld(this.worldId, this.world, this.store);

  static ArmWorld of(World? world, String worldId) =>
      ArmWorld(worldId, world, ProcessingRuntime.instance.store);

  BState stateAt(Pos pos) {
    final level = KineticsRuntime.instance.level(worldId);
    return bStateOf(level.stateAt(toKPos(pos.toBlockPos())));
  }

  bool isLoaded(Pos pos) => world?.isLoaded(pos: pos.toBlockPos()) ?? false;

  CreateBlockEntity? beAt(Pos pos) => store.at(worldId, pos.toBlockPos());
}

/// `ArmInteractionPoint`.
class ArmInteractionPoint {
  final ArmInteractionPointType type;
  final ArmWorld level;
  final Pos pos;
  ArmPointMode mode;

  BState cachedState;

  ArmInteractionPoint(
    this.type,
    this.level,
    this.pos,
    this.cachedState, {
    this.mode = ArmPointMode.deposit,
  });

  String get worldId => level.worldId;

  /// `getInteractionPositionVector`.
  Vec3 get interactionPositionVector => pos.center;

  /// `getInteractionDirection`.
  Direction get interactionDirection => Direction.down;

  /// `cycleMode`.
  void cycleMode() => mode = mode.cycled;

  /// `updateCachedState`.
  void updateCachedState() => cachedState = level.stateAt(pos);

  /// `isValid`.
  bool get isValid {
    updateCachedState();
    return type.canCreatePoint(level, pos, cachedState);
  }

  /// `keepAlive`.
  void keepAlive() {}

  // -- Item transfer --------------------------------------------------------------------------

  ItemStorage? _pluginStorage() => ProcessingRuntime.instance.storage
      .pluginItemStorage(worldId, pos.toBlockPos());

  ItemHandler? _hostHandler() {
    final world = level.world;
    if (world == null) return null;
    return ItemHandlers.at(world, pos.toBlockPos());
  }

  /// `getHandler`/`insert`: the remainder of [stack].
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    if (stack.isEmpty) return stack;
    final plugin = _pluginStorage();
    if (plugin != null) {
      return ItemStorages.insertStacked(plugin, stack, simulate: simulate);
    }
    final handler = _hostHandler();
    if (handler == null) return stack;
    try {
      final hostStack = await HostStacks.write(stack);
      if (hostStack == null) return PStack.empty;
      final rest = await handler.insertStack(hostStack, simulate: simulate);
      hostStack.dispose();
      if (rest == null) return PStack.empty;
      final value = await HostStacks.read(rest);
      rest.dispose();
      return value;
    } finally {
      handler.dispose();
    }
  }

  /// `extract`.
  Future<PStack> extract(
    ArmBlockEntity arm,
    int slot,
    int amount,
    bool simulate,
  ) async {
    if (amount <= 0) return PStack.empty;
    final plugin = _pluginStorage();
    if (plugin != null) {
      if (slot < 0 || slot >= plugin.slots) return PStack.empty;
      return plugin.extract(slot, amount, simulate: simulate);
    }
    final handler = _hostHandler();
    if (handler == null) return PStack.empty;
    try {
      if (slot < 0 || slot >= handler.slotCount()) return PStack.empty;
      final taken = handler.take(slot, amount, simulate: simulate);
      if (taken == null) return PStack.empty;
      final value = await HostStacks.read(taken);
      taken.dispose();
      return value;
    } finally {
      handler.dispose();
    }
  }

  /// `getSlotCount`.
  int slotCount(ArmBlockEntity arm) {
    final plugin = _pluginStorage();
    if (plugin != null) return plugin.slots;
    final handler = _hostHandler();
    if (handler == null) return 0;
    try {
      return handler.slotCount();
    } finally {
      handler.dispose();
    }
  }

  // -- Serialization --------------------------------------------------------------------------

  /// `serialize(anchor)`: `{Type, Pos, Mode}` with the position relative to the arm.
  NbtMap serialize(Pos anchor) {
    final nbt = NbtMap()
      ..putString('Type', type.key)
      ..putIntArray('Pos', [
        pos.$1 - anchor.$1,
        pos.$2 - anchor.$2,
        pos.$3 - anchor.$3,
      ])
      ..putString('Mode', mode.javaName);
    return nbt;
  }

  /// `ArmInteractionPoint.deserialize`.
  static ArmInteractionPoint? deserialize(
    NbtMap nbt,
    ArmWorld level,
    Pos anchor,
    ArmInteractionPointType? Function(String key) typeOf,
  ) {
    final type = typeOf(nbt.getString('Type'));
    if (type == null) return null;
    final relative = nbt.getBlockPos('Pos');
    final pos = (
      anchor.$1 + relative.$1,
      anchor.$2 + relative.$2,
      anchor.$3 + relative.$3,
    );
    final state = level.stateAt(pos);
    if (!type.canCreatePoint(level, pos, state)) return null;
    final point = type.createPoint(level, pos, state);
    if (point == null) return null;
    point.mode = ArmPointMode.fromJavaName(nbt.getString('Mode'));
    return point;
  }

  /// `ArmInteractionPoint.transformPos`: moves the saved position of a point.
  static void transformPos(NbtMap nbt, StructureTransform transform) {
    final p = nbt.getBlockPos('Pos');
    final moved = transform.applyPosWithoutOffset(p);
    nbt.putIntArray('Pos', [moved.$1, moved.$2, moved.$3]);
  }

  @override
  String toString() => 'ArmInteractionPoint(${type.key}@$pos, ${mode.name})';
}

/// `ArmInteractionPointType`: a kind of block the arm can interact with.
abstract class ArmInteractionPointType {
  /// The key of the `create:arm_interaction_point_type` registry entry.
  final String key;

  const ArmInteractionPointType(this.key);

  bool canCreatePoint(ArmWorld level, Pos pos, BState state);

  ArmInteractionPoint? createPoint(ArmWorld level, Pos pos, BState state) =>
      ArmInteractionPoint(this, level, pos, state);

  int get priority => 0;
}

// -- Point subclasses -------------------------------------------------------------------------

/// `DepositOnlyArmInteractionPoint`.
class DepositOnlyArmInteractionPoint extends ArmInteractionPoint {
  DepositOnlyArmInteractionPoint(
    super.type,
    super.level,
    super.pos,
    super.cachedState,
  );

  @override
  void cycleMode() {}

  @override
  Future<PStack> extract(
    ArmBlockEntity arm,
    int slot,
    int amount,
    bool simulate,
  ) async => PStack.empty;

  @override
  int slotCount(ArmBlockEntity arm) => 0;
}

/// `TopFaceArmInteractionPoint`: the point sits on top of the block.
class TopFaceArmInteractionPoint extends ArmInteractionPoint {
  TopFaceArmInteractionPoint(
    super.type,
    super.level,
    super.pos,
    super.cachedState,
  );

  @override
  Vec3 get interactionPositionVector => (pos.$1 + .5, pos.$2 + 1, pos.$3 + .5);
}

/// `DepotPoint`: the items lie on the top face.
class DepotPoint extends ArmInteractionPoint {
  DepotPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Vec3 get interactionPositionVector =>
      (pos.$1 + .5, pos.$2 + 14 / 16, pos.$3 + .5);
}

/// `BeltPoint`: a belt segment; it locks the item it is about to take.
class BeltPoint extends DepotPoint {
  BeltPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  void keepAlive() {
    super.keepAlive();
    final behaviour = level
        .beAt(pos)
        ?.getBehaviour<TransportedItemStackHandlerBehaviour>();
    if (behaviour == null) return;
    var found = false;
    behaviour.handleProcessingOnAllItems((item) {
      if (found) return null;
      item.lockedExternally = true;
      found = true;
      return null;
    });
  }
}

/// `BlazeBurnerPoint`: a fuel acceptor (the blaze burner).
class BlazeBurnerPoint extends DepositOnlyArmInteractionPoint {
  BlazeBurnerPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    final be = level.beAt(pos);
    if (be case final FuelAcceptor acceptor) {
      return acceptor.tryInsertFuel(stack, simulate: simulate);
    }
    return stack;
  }
}

/// `CrafterPoint`: the arm feeds the crafter's slot from the front.
class CrafterPoint extends ArmInteractionPoint {
  CrafterPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Direction get interactionDirection {
    final facing = cachedState.dir('facing') ?? Direction.south;
    return facing.opposite;
  }

  @override
  Vec3 get interactionPositionVector {
    final d = interactionDirection;
    final center = super.interactionPositionVector;
    return (
      center.$1 + d.stepX * .5,
      center.$2 + d.stepY * .5,
      center.$3 + d.stepZ * .5,
    );
  }

  @override
  void updateCachedState() {
    final old = cachedState;
    super.updateCachedState();
    if (old != cachedState) {
      // The cached angles are client only.
    }
  }

  @override
  Future<PStack> extract(
    ArmBlockEntity arm,
    int slot,
    int amount,
    bool simulate,
  ) async {
    final be = level.beAt(pos);
    if (be is! MechanicalCrafterBlockEntity) return PStack.empty;
    be.allowExtraction();
    try {
      return await super.extract(arm, slot, amount, simulate);
    } finally {
      be.forbidExtraction();
    }
  }
}

/// `DeployerPoint`: the arm puts items into the deployer's hand from the front.
class DeployerPoint extends ArmInteractionPoint {
  DeployerPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Direction get interactionDirection {
    final facing = cachedState.dir('facing') ?? Direction.up;
    return facing.opposite;
  }

  @override
  Vec3 get interactionPositionVector {
    final d = interactionDirection;
    final center = super.interactionPositionVector;
    return (
      center.$1 + d.stepX * .65,
      center.$2 + d.stepY * .65,
      center.$3 + d.stepZ * .65,
    );
  }
}

/// `FunnelPoint`: a funnel; items go in from the funnel's mouth.
class FunnelPoint extends DepositOnlyArmInteractionPoint {
  FunnelPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Vec3 get interactionPositionVector {
    final facing = _funnelFacing(cachedState);
    final normal = facing == null ? (0, 0, 0) : facing.normal;
    return (
      pos.$1 + .5 - normal.$1 * .15,
      pos.$2 + .5 - normal.$2 * .15,
      pos.$3 + .5 - normal.$3 * .15,
    );
  }

  @override
  Direction get interactionDirection {
    final facing = _funnelFacing(cachedState);
    return facing == null ? Direction.up : facing.opposite;
  }

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    if (cachedState.flag('powered')) return stack;
    // Java asks the funnel's own `InvManipulationBehaviour` for the insertion (it is not an
    // item capability), with the funnel's filter (`FunnelBlockEntity.tryInsert`); the host's
    // item handlers know nothing about a funnel.
    final be = level.beAt(pos);
    if (be is! FunnelBlockEntity) return stack;
    return toPStack(await be.tryInsert(fromPStack(stack), simulate: simulate));
  }
}

/// `CampfirePoint`: only cookable items go onto a campfire.
class CampfirePoint extends DepositOnlyArmInteractionPoint {
  CampfirePoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    final recipes = sharedCraftingRecipes;
    if (recipes == null) return stack;
    try {
      if (recipes.matchCooking(stack.key, CookingType.campfire) == null) {
        return stack;
      }
    } on Object {
      return stack;
    }
    return super.insert(arm, stack, simulate);
  }
}

/// `ComposterPoint`: the composter's upper side takes items, the lower one gives compost.
class ComposterPoint extends ArmInteractionPoint {
  ComposterPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Vec3 get interactionPositionVector =>
      (pos.$1 + .5, pos.$2 + 13 / 16, pos.$3 + .5);

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    final world = level.world;
    if (world == null) return stack;
    final handler = ItemHandlers.at(
      world,
      pos.toBlockPos(),
      side: BlockDirection.up,
    );
    if (handler == null) return stack;
    try {
      final hostStack = await HostStacks.write(stack);
      if (hostStack == null) return PStack.empty;
      final rest = await handler.insertStack(hostStack, simulate: simulate);
      hostStack.dispose();
      if (rest == null) return PStack.empty;
      final value = await HostStacks.read(rest);
      rest.dispose();
      return value;
    } finally {
      handler.dispose();
    }
  }

  @override
  Future<PStack> extract(
    ArmBlockEntity arm,
    int slot,
    int amount,
    bool simulate,
  ) async {
    final world = level.world;
    if (world == null) return PStack.empty;
    final handler = ItemHandlers.at(
      world,
      pos.toBlockPos(),
      side: BlockDirection.down,
    );
    if (handler == null) return PStack.empty;
    try {
      if (slot < 0 || slot >= handler.slotCount()) return PStack.empty;
      final taken = handler.take(slot, amount, simulate: simulate);
      if (taken == null) return PStack.empty;
      final value = await HostStacks.read(taken);
      taken.dispose();
      return value;
    } finally {
      handler.dispose();
    }
  }

  @override
  int slotCount(ArmBlockEntity arm) => 2;
}

/// `JukeboxPoint`: a music disc goes in, and only when the jukebox is empty.
class JukeboxPoint extends TopFaceArmInteractionPoint {
  JukeboxPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  int slotCount(ArmBlockEntity arm) => 1;

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    // `stack.get(DataComponents.JUKEBOX_PLAYABLE) == null`
    if (!_isPlayable(stack)) return stack;
    if (cachedState.flag('has_record')) return stack;
    final container = _jukeboxContainer();
    if (container == null) return stack;
    final current = container.getStack(slot: 0);
    if (current != null && await current.getCount() > 0) return stack;

    // `remainder.split(1)`: one disc goes in, the rest is for the arm.
    final remainder = stack.withCount(stack.count - 1);
    if (!simulate) {
      final one = await HostStacks.write(stack.withCount(1));
      if (one == null) return stack;
      await container.setStack(slot: 0, stack: one);
      _setHasRecord(true);
    }
    return remainder;
  }

  @override
  Future<PStack> extract(
    ArmBlockEntity arm,
    int slot,
    int amount,
    bool simulate,
  ) async {
    if (!cachedState.flag('has_record')) return PStack.empty;
    final container = _jukeboxContainer();
    if (container == null) return PStack.empty;
    final stack = container.getStack(slot: 0);
    if (stack == null) return PStack.empty;
    final value = await HostStacks.read(stack);
    if (value.isEmpty) return PStack.empty;

    final taken = value.withCount(amount < value.count ? amount : value.count);
    if (!simulate) {
      final left = value.count - taken.count;
      await container.setStack(
        slot: 0,
        stack: left <= 0 ? null : await HostStacks.write(value.withCount(left)),
      );
      _setHasRecord(left > 0);
    }
    return taken;
  }

  /// The jukebox's container (`JukeboxBlockEntity.getTheItem` / `setTheItem`): the record is
  /// its single slot. `null` when the block entity is not a jukebox (or the world is gone).
  ContainerBlockEntity? _jukeboxContainer() {
    final world = level.world;
    if (world == null) return null;
    final be = world.getBlockEntity(pos: pos.toBlockPos());
    if (be is! BlockEntityTypeJukeboxBlockEntity) return null;
    return be.value.getContainer();
  }

  /// `JukeboxBlock.HAS_RECORD` after the record changed (Java's `setTheItem` writes the state).
  void _setHasRecord(bool hasRecord) {
    if (cachedState.flag('has_record') == hasRecord) return;
    cachedState = cachedState.setValue('has_record', hasRecord ? 'true' : 'false');
    final world = level.world;
    if (world == null) return;
    final id = BlockStates.setValue(
      world.getBlockStateId(pos: pos.toBlockPos()),
      'has_record',
      hasRecord ? 'true' : 'false',
    );
    unawaited(
      world.setBlockState(
        pos: pos.toBlockPos(),
        state: id,
        updateFlags: BlockUpdateFlags.normal,
      ),
    );
  }
}

/// `RespawnAnchorPoint`: glowstone charges the anchor.
class RespawnAnchorPoint extends DepositOnlyArmInteractionPoint {
  RespawnAnchorPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Vec3 get interactionPositionVector => (pos.$1 + .5, pos.$2 + 1, pos.$3 + .5);

  @override
  Future<PStack> insert(ArmBlockEntity arm, PStack stack, bool simulate) async {
    if (stack.key != 'minecraft:glowstone') return stack;
    final charge = cachedState.intValue('charge');
    if (charge >= 4) return stack;
    if (!simulate) {
      final world = level.world;
      if (world != null) {
        final id = BlockStates.setValue(
          world.getBlockStateId(pos: pos.toBlockPos()),
          'charge',
          '${charge + 1}',
        );
        await world.setBlockState(
          pos: pos.toBlockPos(),
          state: id,
          updateFlags: BlockUpdateFlags.normal,
        );
      }
      cachedState = cachedState.setValue('charge', '${charge + 1}');
    }
    return stack.withCount(stack.count - 1);
  }
}

/// `CrushingWheelPoint`: items go onto the wheels' top.
class CrushingWheelPoint extends DepositOnlyArmInteractionPoint {
  CrushingWheelPoint(super.type, super.level, super.pos, super.cachedState);

  @override
  Vec3 get interactionPositionVector => (pos.$1 + .5, pos.$2 + 1, pos.$3 + .5);
}

/// The `facing` of a funnel block (`FunnelBlock.getFunnelFacing`): `null` for the upward one.
Direction? _funnelFacing(BState state) => state.dir('facing');

/// `stack.get(DataComponents.JUKEBOX_PLAYABLE) != null`: a music disc. The component is only
/// readable when the host sends it, so the item name is the fallback.
bool _isPlayable(PStack stack) =>
    stack.hasComponent('minecraft:jukebox_playable') ||
    stack.key.startsWith('minecraft:music_disc_');

/// Drops the remainder at the point (helper for points that spill items).
Future<void> dropAtPoint(ArmWorld level, Pos pos, PStack stack) async {
  final world = level.world;
  if (world == null || stack.isEmpty) return;
  await dropPStack(world, (pos.$1 + .5, pos.$2 + .5, pos.$3 + .5), stack);
}
