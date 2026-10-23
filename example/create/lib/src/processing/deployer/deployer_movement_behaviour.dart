// `DeployerMovementBehaviour`: the deployer on a contraption uses its held item on whatever the
// contraption moves it against.
//
// Ported from `content/kinetics/deployer/DeployerMovementBehaviour.java`. The schematic printer
// (`AllItems.SCHEMATIC` filter) is not ported: the schematics module owns it and the host has no
// schematic placement here, so a schematic filter simply does nothing.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/advancements.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../contraptions/core/movement.dart';
import '../../contraptions/mounted/mounted_contraption.dart';
import '../../contraptions/storage/stacks.dart';
import '../common/stack.dart';
import '../crafter/machine_support.dart' show dropPStack;
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import 'deployer_actor_player.dart';
import 'deployer_filter.dart';
import 'deployer_handler.dart';
import 'deployer_types.dart';

/// The deployer as a contraption actor.
class DeployerMovementBehaviour extends MovementBehaviour {
  const DeployerMovementBehaviour();

  Direction _facing(MovementContext context) =>
      context.state.dir('facing') ?? Direction.north;

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final f = _facing(context);
    return (f.stepX * 2.0, f.stepY * 2.0, f.stepZ * 2.0);
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
    if (world == null) return;
    final player = actorPlayer(context, world);
    if (player == null) return;

    await _tryGrabbingItem(context, player);
    final mode = actorModeOf(context);
    final held = await readActorHand(player);
    if (mode == DeployerMode.use &&
        !DeployerHandler.shouldActivate(held, world, pos, null)) {
      return;
    }

    final before = world.getBlockStateId(pos: pos.toBlockPos());
    await _activate(context, pos, player, mode, world);
    // `activate(context, pos, player, mode); checkForTrackPlacementAdvancement(context, player);`
    // (`DeployerMovementBehaviour.java:82-83`): the flag was set by `DeployerHandler.activate`
    // when the item use placed a track; the port reads the placed block instead.
    _checkForTrackPlacementAdvancement(context, world, pos, before);
    await _tryDisposeOfExcess(context, player);
  }

  /// `checkForTrackPlacementAdvancement` (`DeployerMovementBehaviour.java:120-124`):
  /// `SELF_DEPLOYING` goes to the owner recorded in the captured block entity data, on a cart or
  /// carriage contraption only. In Java the gate is `player.placedTracks`, set by
  /// `DeployerHandler.activate` when the used item was a track block item; the port tests the
  /// target block directly, which is the same event (`AllBlockTags.TRACKS`).
  void _checkForTrackPlacementAdvancement(
    MovementContext context,
    World world,
    Pos pos,
    int stateBefore,
  ) {
    final after = world.getBlockStateId(pos: pos.toBlockPos());
    if (after == stateBefore) return;
    final rt = ProcessingRuntime.instance;
    final key = world.getBlock(pos: pos.toBlockPos()).name;
    if (!rt.tags.blockHasTag(key, 'create:tracks')) return;

    final contraption = context.contraption;
    // `instanceof MountedContraption || instanceof CarriageContraption`
    // (`AllContraptionTypes.CARRIAGE` is the port's carriage contraption).
    if (contraption is! MountedContraption &&
        contraption.typeId != 'create:carriage') {
      return;
    }
    final data = context.blockEntityData;
    if (data == null || !data.contains('Owner')) return;
    final owner = actorOwnerId(data);
    if (owner == null) return;
    final advancements = rt.services.find<CreateAdvancements>();
    final player = advancements?.playerByUuid(owner);
    if (player == null) return;
    unawaited(advancements!.award(player, AllAdvancements.selfDeploying));
  }

  /// Continues a punch that started on an earlier position.
  @override
  Future<void> tick(MovementContext context) async {
    if (!context.stall) return;
    if (!context.data.contains('BreakingPos')) {
      context.stall = false;
      return;
    }

    final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
    if (world == null) return;
    final player = actorPlayer(context, world);
    if (player == null) return;

    final timer = context.data.getInt('Timer');
    if (timer < 20) {
      context.data.putInt('Timer', timer + 1);
      return;
    }

    context.data.remove('Timer');
    final pos = context.data.getBlockPos('BreakingPos');
    await _activate(context, pos, player, actorModeOf(context), world);
    await _tryDisposeOfExcess(context, player);
  }

  @override
  void cancelStall(MovementContext context) {
    super.cancelStall(context);
    context.data.remove('BreakingPos');
    context.data.remove('Timer');
    final player = context.temporaryData;
    if (player is Player) unawaited(player.stopBreaking());
  }

  @override
  Future<void> stopMoving(MovementContext context) async {
    cancelStall(context);
    final player = context.temporaryData;
    if (player is! Player) return;
    await saveActorPlayer(context, player);
  }

  @override
  bool disableBlockEntityRendering() => true;

  Future<void> _activate(
    MovementContext context,
    Pos pos,
    Player player,
    DeployerMode mode,
    World world,
  ) async {
    final facing = _facing(context);
    final facingVec = context.rotation(facing.unitVec3);
    final position = context.position;
    if (position == null) return;
    final vec = position - facingVec * 2;

    final rotation = DeployerHandler.rotationFromVector(facingVec);
    FakePlayerActions(player)
        .moveTo(world, vec, yaw: rotation.$1, pitch: rotation.$2);

    final breaking = context.data.contains('BreakingPos')
        ? context.data.getBlockPos('BreakingPos')
        : null;
    final next = await DeployerHandler.activate(
      player,
      world,
      vec,
      pos,
      facingVec,
      mode,
      breakingPos: breaking,
    );
    if (next == null) {
      context.data.remove('BreakingPos');
      context.stall = false;
    } else {
      context.data.putBlockPos('BreakingPos', next);
      context.stall = true;
    }

    saveActorHeld(context, await readActorHand(player));
  }

  /// `tryGrabbingItem`: takes one item matching the filter out of the contraption's storage.
  Future<void> _tryGrabbingItem(MovementContext context, Player player) async {
    if ((await readActorHand(player)).isNotEmpty) return;
    final filter = actorFilterOf(context);
    if (filter.key == 'create:schematic') return;

    final extracted = ItemSlotsHelper.extract(
      context.contraption.storage.allItems,
      (stack) => deployerFilterTest(
        filter,
        PStack(stack.item, stack.count),
        context.worldId,
      ),
      1,
    );
    if (extracted.isEmpty) return;

    final stack = PStack(extracted.item, extracted.count);
    await setActorHand(player, stack);
    saveActorHeld(context, stack);
  }

  /// `tryDisposeOfExcess`: everything but the filtered main hand item leaves the fake player.
  Future<void> _tryDisposeOfExcess(
    MovementContext context,
    Player player,
  ) async {
    final filter = actorFilterOf(context);
    final inventory = player.getInventory();
    final storage = inventory.storage;
    final selected = inventory.getSelectedSlot();

    for (var slot = 0; slot < storage.getSize(); slot++) {
      final item = storage.getItem(slot: slot);
      if (item == null) continue;
      final stack = await HostStacks.read(item);
      item.dispose();
      if (stack.isEmpty) continue;
      if (slot == selected &&
          deployerFilterTest(filter, stack, context.worldId)) {
        continue;
      }
      await _collectOrDrop(context, stack);
      await storage.setItem(slot: slot, item: null);
    }
    saveActorHeld(context, await readActorHand(player));
  }

  /// `collectOrDropItem`: into the contraption's storage, the remainder as an item entity.
  Future<void> _collectOrDrop(MovementContext context, PStack stack) async {
    if (stack.isEmpty) return;
    var rest = StoredStack(stack.key, stack.count);
    rest = ItemSlotsHelper.insert(context.contraption.storage.allItems, rest);
    if (rest.isEmpty) return;
    final world = ProcessingRuntime.instance.worlds.byId(context.worldId);
    final position = context.position;
    if (world == null || position == null) return;
    await dropPStack(world, position, PStack(rest.item, rest.count));
  }
}
