// `BeltSlicer` (host): the wrench and belt connector interactions on an existing belt. Ported
// from `content/kinetics/belt/BeltSlicer.java` (the client-side hover feedback is omitted).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, setBlockState;
import '../../api/kinetics.dart' show KState;
import '../../common/direction.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../items/item_codec.dart';
import '../runtime.dart';
import 'belt_block_entity.dart';
import 'belt_geometry.dart';
import 'transported_item.dart';

/// `BeltSlicer.useWrench`: shortens or splits the belt under the wrench.
Future<BlockUseResult> useWrench(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos pos,
  BState state,
  Player player,
  Direction face,
  (double, double, double) cursor,
) async {
  final controllerBE = _segment(rt, worldId, pos)?.controllerBE;
  if (controllerBE == null) return BlockUseResult.tryEmptyHand;
  if (state.flag('casing') && face != Direction.up)
    return BlockUseResult.tryEmptyHand;
  if (state.beltPart == BeltPart.pulley && face.axis != Axis.y)
    return BlockUseResult.tryEmptyHand;

  final beltLength = controllerBE.beltLength;
  if (beltLength == 2) return BlockUseResult.fail;

  final beltVector = beltVectorPos(state);
  final part = state.beltPart;
  var chain = getBeltChain(_getter(world), controllerBE.p);
  final creative = player.isCreative;
  final hit = (pos.x + cursor.$1, pos.y + cursor.$2, pos.z + cursor.$3);

  // Shorten from the end.
  if (hoveringEnd(state, pos, hit)) {
    for (final at in chain) {
      final belt = _segment(rt, worldId, at);
      if (belt == null) continue;
      belt.detachKinetics();
      belt.invalidateItemHandler();
      belt.beltLength = 0;
    }

    final inventory = controllerBE.getInventory();
    final next = part == BeltPart.end ? pos - beltVector : pos + beltVector;
    final replacedState = _stateAt(rt, worldId, next);
    final segmentBE = _segment(rt, worldId, next);
    await _switch(
      rt,
      world,
      worldId,
      next,
      withWater(
        world,
        state.setFlag('casing', segmentBE?.casing != BeltCasing.none),
        next,
      ),
    );
    await setBlockState(world, pos, BState.air, flags: BlockUpdateFlags.normal);

    if (!creative &&
        replacedState.isBelt &&
        replacedState.beltPart == BeltPart.pulley) {
      await _give(player, 'create:shaft', 1);
    }

    // Eject overshooting items.
    if (part == BeltPart.end && inventory != null) {
      final toEject = [
        for (final t in List.of(inventory.items))
          if (t.beltPosition > beltLength - 1) t,
      ];
      for (final t in toEject) {
        await inventory.eject(t);
        inventory.items.remove(t);
      }
    }

    // Transfer the items to the new controller.
    if (part == BeltPart.start && segmentBE != null && inventory != null) {
      controllerBE.clearInventory();
      segmentBE.clearInventory();
      segmentBE.setController(next);
      for (final t in List.of(inventory.items)) {
        t.beltPosition -= 1;
        if (t.beltPosition <= 0) {
          await _drop(world, (pos.x + .5, pos.y + 11 / 16, pos.z + .5), t);
        } else {
          segmentBE.getInventory()?.addItem(t);
        }
      }
    }
    return BlockUseResult.success;
  }

  final segmentBE = _segment(rt, worldId, pos);
  if (segmentBE == null) return BlockUseResult.tryEmptyHand;

  // Split in half.
  final hitSegment = segmentBE.index;
  final centerOf = pos.center;
  final subtract = (
    hit.$1 - centerOf.$1,
    hit.$2 - centerOf.$2,
    hit.$3 - centerOf.$3,
  );
  final towardPositive =
      subtract.$1 * beltVector.$1 +
          subtract.$2 * beltVector.$2 +
          subtract.$3 * beltVector.$3 >
      0;
  final next = !towardPositive ? pos - beltVector : pos + beltVector;

  if (hitSegment == 0 || (hitSegment == 1 && !towardPositive))
    return BlockUseResult.fail;
  if (hitSegment == beltLength - 1 ||
      (hitSegment == beltLength - 2 && towardPositive))
    return BlockUseResult.fail;

  // Non-creative players cannot split belts (the Java path only refunds the searched items and
  // then returns FAIL).
  if (!creative) return BlockUseResult.fail;

  for (final at in chain) {
    final belt = _segment(rt, worldId, at);
    if (belt == null) continue;
    belt.detachKinetics();
    belt.invalidateItemHandler();
    belt.beltLength = 0;
  }

  final inventory = controllerBE.getInventory();
  await _switch(
    rt,
    world,
    worldId,
    pos,
    state.setValue('part', towardPositive ? 'end' : 'start'),
  );
  final nextState = _stateAt(rt, worldId, next);
  await _switch(
    rt,
    world,
    worldId,
    next,
    nextState.setValue('part', towardPositive ? 'start' : 'end'),
  );
  rt.playSound(world, pos, 'minecraft:block.wool.hit', volume: .5, pitch: 2.3);

  // Transfer the items to the new controller.
  final newController = towardPositive
      ? _segment(rt, worldId, next)
      : segmentBE;
  if (newController != null && inventory != null) {
    newController.clearInventory();
    newController.setController(newController.p);
    for (final t in List.of(inventory.items)) {
      final newPosition =
          t.beltPosition - hitSegment - (towardPositive ? 1 : 0);
      if (newPosition <= 0) continue;
      t.beltPosition = newPosition;
      inventory.items.remove(t);
      newController.getInventory()?.addItem(t);
    }
  }

  return BlockUseResult.success;
}

/// `BeltSlicer.useConnector`: extends the belt or merges it with the belt next to it.
Future<BlockUseResult> useConnector(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos pos,
  BState state,
  Player player,
  (double, double, double) cursor,
) async {
  final controllerBE = _segment(rt, worldId, pos)?.controllerBE;
  if (controllerBE == null) return BlockUseResult.tryEmptyHand;

  final beltLength = controllerBE.beltLength;
  if (beltLength == rt.maxBeltLength) return BlockUseResult.fail;

  final beltVector = beltVectorPos(state);
  final part = state.beltPart;
  final facing = state.beltFacing;
  var chain = getBeltChain(_getter(world), controllerBE.p);
  final creative = player.isCreative;
  final hit = (pos.x + cursor.$1, pos.y + cursor.$2, pos.z + cursor.$3);

  if (!hoveringEnd(state, pos, hit)) return BlockUseResult.tryEmptyHand;

  final next = part == BeltPart.start ? pos - beltVector : pos + beltVector;
  BeltBlockEntity? mergedController;
  var mergedBeltLength = 0;

  // Merge belts / extend at the end.
  final nextState = _stateAt(rt, worldId, next);
  final getter = _getter(world);
  if (!getter.canBeReplaced(next)) {
    if (!nextState.isBelt) return BlockUseResult.fail;
    if (!beltStatesCompatible(state, nextState)) return BlockUseResult.fail;

    mergedController = _segment(rt, worldId, next)?.controllerBE;
    if (mergedController == null) return BlockUseResult.fail;
    if (mergedController.beltLength + beltLength > rt.maxBeltLength)
      return BlockUseResult.fail;

    mergedBeltLength = mergedController.beltLength;

    final shouldFlip = facing != nextState.beltFacing;
    final color = controllerBE.dye;
    for (final at in getBeltChain(getter, mergedController.p)) {
      final belt = _segment(rt, worldId, at);
      if (belt == null) continue;
      belt.detachKinetics();
      belt.invalidateItemHandler();
      belt.beltLength = 0;
      belt.dye = color;
      if (shouldFlip) {
        final flipped = flipBelt(_stateAt(rt, worldId, at));
        await setBlockState(world, at, flipped);
      }
    }

    // Reverse the items.
    final mergedInventory = mergedController.getInventory();
    if (shouldFlip && mergedInventory != null) {
      for (final t in mergedInventory.items) {
        t.beltPosition = mergedBeltLength - t.beltPosition;
        t.prevBeltPosition = mergedBeltLength - t.prevBeltPosition;
      }
    }

    chain = getBeltChain(getter, mergedController.p);
  }

  for (final at in chain) {
    final belt = _segment(rt, worldId, at);
    if (belt == null) continue;
    belt.detachKinetics();
    belt.invalidateItemHandler();
    belt.beltLength = 0;
  }

  final inventory = controllerBE.getInventory();
  await _switch(rt, world, worldId, pos, state.setValue('part', 'middle'));

  if (mergedController == null) {
    // Attach at the end.
    await setBlockState(
      world,
      next,
      withWater(world, state.setFlag('casing', false), next),
    );
    final segmentBE = _segment(rt, worldId, next);
    segmentBE?.dye = controllerBE.dye;
    rt.playSound(
      world,
      pos,
      'minecraft:block.wool.place',
      volume: .5,
      pitch: 1,
    );

    // Transfer the items to the new controller.
    if (part == BeltPart.start && segmentBE != null && inventory != null) {
      segmentBE.setController(next);
      for (final t in List.of(inventory.items)) {
        t.beltPosition += 1;
        segmentBE.getInventory()?.addItem(t);
      }
    }
  } else {
    // Merge with the other belt.
    final mergedInventory = mergedController.getInventory();
    rt.playSound(
      world,
      pos,
      'minecraft:block.wool.hit',
      volume: .5,
      pitch: 1.3,
    );
    final segmentBE = _segment(rt, worldId, next);
    final mergedState = state
        .setFlag(
          'casing',
          segmentBE != null && segmentBE.casing != BeltCasing.none,
        )
        .setValue('part', 'middle');
    await _switch(rt, world, worldId, next, mergedState);

    if (!creative) {
      await _give(player, 'create:shaft', 2);
      await _give(player, 'create:belt_connector', 1);
    }

    for (final at in getBeltChain(getter, controllerBE.p)) {
      _segment(rt, worldId, at)?.invalidateItemHandler();
    }

    // Transfer the items to the other controller.
    var search = controllerBE.p;
    for (var i = 0; i < 10000; i++) {
      final searchState = _stateAt(rt, worldId, search);
      if (!searchState.isBelt) break;
      if (searchState.beltPart != BeltPart.start) {
        search = search - beltVector;
        continue;
      }

      final newController = _segment(rt, worldId, search);

      if (newController != null &&
          newController != controllerBE &&
          inventory != null) {
        newController.setController(search);
        controllerBE.clearInventory();
        for (final t in List.of(inventory.items)) {
          t.beltPosition += mergedBeltLength;
          newController.getInventory()?.addItem(t);
        }
      }

      if (newController != null &&
          newController != mergedController &&
          mergedInventory != null) {
        newController.setController(search);
        mergedController.clearInventory();
        for (final t in List.of(mergedInventory.items)) {
          if (newController == controllerBE) t.beltPosition += beltLength;
          newController.getInventory()?.addItem(t);
        }
      }

      break;
    }
  }

  return BlockUseResult.success;
}

// -- Helpers ---------------------------------------------------------------------------------

BeltBlockEntity? _segment(ConveyanceRuntime rt, String worldId, Pos pos) =>
    rt.typedAt<BeltBlockEntity>(worldId, pos);

BState _stateAt(ConveyanceRuntime rt, String worldId, Pos pos) =>
    rt.stateAt(worldId, pos);

BlockGetter _getter(World world) => HostBlockGetter(world);

Future<void> _switch(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos pos,
  BState state,
) async {
  final kinetics = rt.kinetics;
  if (kinetics != null) {
    await kinetics.switchToBlockState(
      worldId,
      pos.toBlockPos(),
      KState(state.key, state.props),
    );
    return;
  }
  await setBlockState(world, pos, state);
}

Future<void> _give(Player player, String key, int count) async {
  final stack = ItemStack.create(registryKey: key, count: count);
  final left = await player.give(stack);
  if (left != null) {
    final world = player.getWorld();
    await world.dropItem(player.getPosition(), left);
    world.dispose();
  }
}

Future<void> _drop(
  World world,
  (double, double, double) at,
  TransportedItemStack t,
) async {
  if (t.stack.isEmpty) return;
  await ItemCodec.drop(world, at, t.stack);
}
