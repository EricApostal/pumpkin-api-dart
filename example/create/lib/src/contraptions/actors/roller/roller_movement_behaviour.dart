// `RollerMovementBehaviour`: the mechanical roller breaks the blocks above the ground it drives
// over and paves the surface with the material of its filter.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/block_state.dart';
import '../../../api/blocks.dart' show setBlockState;
import '../../../api/damage.dart' show CreateDamage;
import '../../../common/common.dart';
import '../../../common/host_bridge.dart';
import '../../core/level.dart';
import '../../core/movement.dart';
import '../../core/nbt_map.dart';
import '../../pulley/pulley_contraption.dart';
import '../../storage/stacks.dart';
import '../actor_runtime.dart';
import '../block_breaking_movement_behaviour.dart';
import 'pave_task.dart';
import 'roller_block.dart';

/// `PaveResult`.
enum _PaveResult { fail, pass, success }

/// `RollerMovementBehaviour`.
final class RollerMovementBehaviour extends BlockBreakingMovementBehaviour {
  const RollerMovementBehaviour();

  @override
  bool isActive(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    // `!(context.contraption instanceof PulleyContraption)`: a rope pulley drags the roller
    // through the blocks it hangs in, so it must not break them (`RollerMovementBehaviour.java:69-72`).
    return super.isActive(context) &&
        context.contraption is! PulleyContraption &&
        VecHelper.isVecPointingTowards(context.relativeMotion, facing);
  }

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final facing = context.state.dir('facing') ?? Direction.north;
    return facing.unitVec3 * .45 - (0.0, 2.0, 0.0);
  }

  @override
  double getBlockBreakingSpeed(MovementContext context) =>
      clampDouble(super.getBlockBreakingSpeed(context) * 1.5, 1 / 128, 16);

  @override
  String? getDamageSourceKey() => CreateDamage.roller.key;

  @override
  bool canBreak(ContraptionLevel level, Pos breakingPos, BState state) {
    for (final side in Direction.values) {
      if (level.stateHasTag(
        level.stateAt(breakingPos.relative(side)),
        'minecraft:portals',
      )) {
        return false;
      }
    }
    return super.canBreak(level, breakingPos, state) &&
        !level.stateCollisionEmpty(state) &&
        !level.stateHasTag(state, 'create:tracks');
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;
    if (!context.level.isRedstoneConductor(pos))
      await damageEntities(context, pos, world);

    final positionsToBreak = getPositionsToBreak(context, pos);
    if (positionsToBreak.isEmpty) {
      await triggerPaver(context, pos);
      return;
    }

    Pos? argMax;
    var max = -1.0;
    for (final toBreak in positionsToBreak) {
      final hardness = world.getBlock(pos: toBreak.toBlockPos()).hardness;
      if (hardness < max) continue;
      max = hardness;
      argMax = toBreak;
    }

    if (argMax == null) {
      await triggerPaver(context, pos);
      return;
    }

    context.data.putBlockPos('ReferencePos', pos);
    context.data.putBlockPos('BreakingPos', argMax);
    context.stall = true;
  }

  @override
  Future<void> onBlockBroken(
    MovementContext context,
    Pos pos,
    BState brokenState,
  ) async {
    await super.onBlockBroken(context, pos, brokenState);
    if (!context.data.contains('ReferencePos')) return;

    final referencePos = context.data.getBlockPos('ReferencePos');
    for (final otherPos in getPositionsToBreak(context, referencePos)) {
      if (otherPos != pos) await destroyBlock(context, otherPos);
    }

    await triggerPaver(context, referencePos);
    context.data.remove('ReferencePos');
  }

  @override
  Future<void> destroyBlock(MovementContext context, Pos breakingPos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;
    final state = context.level.stateAt(breakingPos);
    final noHarvest =
        context.level.stateHasTag(state, 'minecraft:needs_iron_tool') ||
        context.level.stateHasTag(state, 'minecraft:needs_stone_tool') ||
        context.level.stateHasTag(state, 'minecraft:needs_diamond_tool');

    await BlockHelper.destroyBlockWith(world, breakingPos, 1, (stack) async {
      if (noHarvest || actorRandom.nextBool()) return;
      await collectOrDropHost(context, stack);
    });
    await super.destroyBlock(context, breakingPos);
  }

  /// `getPositionsToBreak`: the blocks above the ground the roller may break. The train profile
  /// needs the train's track graph, which belongs to the trains module; without a carriage
  /// contraption the visited column is used.
  List<Pos> getPositionsToBreak(MovementContext context, Pos visitedPos) {
    final positions = <Pos>[];
    if (getMode(context) != RollingMode.tunnelPave) return positions;

    var startingY = 1;
    final toPaveWith = getStateToPaveWith(context);
    if (!toPaveWith.isAir) {
      final filter = getFilter(context);
      final held = ItemSlotsHelper.extract(
        context.contraption.storage.allItems,
        (stack) => _filterMatches(filter, stack),
        1,
        simulate: true,
      );
      if (held.isNotEmpty) startingY = 0;
    }

    for (var i = startingY; i <= 2; i++) {
      final target = visitedPos.aboveBy(i);
      if (testBreakerTarget(context, target, i)) positions.add(target);
    }
    return positions;
  }

  /// `testBreakerTarget`.
  bool testBreakerTarget(MovementContext context, Pos target, int columnY) {
    final stateToPaveWith = getStateToPaveWith(context);
    final slab = getStateToPaveWithAsSlab(context);
    final stateAbove = context.level.stateAt(target);
    if (columnY == 0 && stateAbove.key == stateToPaveWith.key) return false;
    if (slab != null && columnY == 1 && stateAbove.key == slab.key)
      return false;
    return canBreak(context.level, target, stateAbove);
  }

  /// `createHeightProfileForTracks`: the roller's track paving needs the carriage's travelling
  /// point and track graph, which the trains module owns; the actor only paves the visited column.
  PaveTask? createHeightProfileForTracks(MovementContext context) => null;

  /// `triggerPaver`.
  Future<void> triggerPaver(MovementContext context, Pos pos) async {
    final stateToPaveWith = getStateToPaveWith(context);
    final slab = getStateToPaveWithAsSlab(context);
    final mode = getMode(context);

    if (mode != RollingMode.tunnelPave && stateToPaveWith.isAir) return;

    final profile = createHeightProfileForTracks(context);

    final paveSet = <(Pos, bool)>[];
    if (profile == null) {
      paveSet.add((pos, false));
    } else {
      for (final coords in profile.keys()) {
        final height = profile.get(coords) ?? 0;
        final shouldPlaceSlab = height > height.floor() + .45;
        final target = (coords.$1, height.floor(), coords.$2);
        paveSet.add((target, shouldPlaceSlab));
      }
    }
    if (paveSet.isEmpty) return;

    var paveResult = _PaveResult.pass;
    var yOffset = 0;
    final fillDepth = actors?.rollerFillDepth ?? 12;

    while (paveResult == _PaveResult.pass) {
      if (yOffset > fillDepth) {
        paveResult = _PaveResult.fail;
        break;
      }

      final currentLayer = <(Pos, bool)>{};
      if (mode == RollingMode.wideFill) {
        for (final anchor in paveSet) {
          final radius = (yOffset + 1) ~/ 2;
          for (var i = -radius; i <= radius; i++) {
            for (var j = -radius; j <= radius; j++) {
              if ((i.abs() + j.abs()) <= radius) {
                currentLayer.add((anchor.$1.offset(i, -yOffset, j), anchor.$2));
              }
            }
          }
        }
      } else {
        for (final anchor in paveSet) {
          currentLayer.add((anchor.$1.belowBy(yOffset), anchor.$2));
        }
      }

      var completelyBlocked = true;
      var anyBlockPlaced = false;

      for (final current in currentLayer) {
        if (slab != null && yOffset == 0 && current.$2) {
          await tryFill(context, current.$1.above, slab);
        }
        paveResult = await tryFill(context, current.$1, stateToPaveWith);
        if (paveResult != _PaveResult.fail) completelyBlocked = false;
        if (paveResult == _PaveResult.success) anyBlockPlaced = true;
      }

      if (anyBlockPlaced) {
        paveResult = _PaveResult.success;
      } else if (!completelyBlocked || yOffset == 0) {
        paveResult = _PaveResult.pass;
      }

      if (paveResult == _PaveResult.success && _isFalling(stateToPaveWith))
        paveResult = _PaveResult.pass;
      if (paveResult != _PaveResult.pass) break;
      if (mode == RollingMode.tunnelPave) break;

      yOffset++;
    }

    if (paveResult == _PaveResult.success) {
      context.data.putInt('WaitingTicks', 2);
      context.data.putBlockPos('LastPos', pos);
      context.stall = true;
    }
  }

  /// `tryFill`.
  Future<_PaveResult> tryFill(
    MovementContext context,
    Pos targetPos,
    BState toPlace,
  ) async {
    final world = actors?.worldOf(context);
    if (world == null || !context.level.isLoaded(targetPos))
      return _PaveResult.fail;
    final existing = context.level.stateAt(targetPos);
    if (existing.key == toPlace.key) return _PaveResult.pass;
    if (!context.level.stateHasTag(existing, 'minecraft:leaves') &&
        !context.level.stateReplaceable(existing) &&
        (!context.level.stateCollisionEmpty(existing) ||
            context.level.stateHasTag(existing, 'minecraft:portals'))) {
      return _PaveResult.fail;
    }

    final filter = getFilter(context);
    final held = ItemSlotsHelper.extract(
      context.contraption.storage.allItems,
      (stack) => _filterMatches(filter, stack),
      1,
    );
    if (held.isEmpty) return _PaveResult.fail;

    await setBlockState(world, targetPos, toPlace);
    return _PaveResult.success;
  }

  /// `getMode`.
  RollingMode getMode(MovementContext context) =>
      RollingMode.of(context.blockEntityData?.getInt('ScrollValue') ?? 0);

  /// `getStateToPaveWith(context)`.
  BState getStateToPaveWith(MovementContext context) =>
      stateToPaveWith(getFilter(context));

  /// `getStateToPaveWith(itemStack)`: the double slab state of the filter's block.
  static BState stateToPaveWith(StoredStack stack) {
    if (stack.isEmpty) return BState.air;
    final block = BlockRegistry.of(stack.item);
    if (block == null) return BState.air;
    var state = BState(block.name, block.defaultState.propertyMap);
    if (state.has('type')) state = state.setValue('type', 'double');
    return state;
  }

  /// `getStateToPaveWithAsSlab`: the bottom slab of the filter's block, `null` if there is none.
  BState? getStateToPaveWithAsSlab(MovementContext context) {
    final state = getStateToPaveWith(context);
    if (state.isAir) return null;
    if (state.has('type')) return state.setValue('type', 'bottom');

    final path = state.key;
    final candidates = <String>[
      '${path}_slab',
      if (path.endsWith('s')) '${path.substring(0, path.length - 1)}_slab',
      if (path.endsWith('planks')) '${path.substring(0, path.length - 7)}_slab',
    ];
    for (final candidate in candidates) {
      final block = BlockRegistry.of(candidate);
      if (block == null) continue;
      return BState(block.name, block.defaultState.propertyMap);
    }
    return null;
  }

  /// The filter of the roller (`getFilterFromBE`), read from its block entity data.
  static StoredStack getFilter(MovementContext context) {
    final value = context.blockEntityData?['Filter'];
    if (value == null) return StoredStack.empty;
    return StoredStack.fromNbt(NbtMap.of(value));
  }

  /// `FilterItemStack.test`: an empty filter accepts everything.
  static bool _filterMatches(StoredStack filter, StoredStack stack) =>
      filter.isEmpty || stack.sameItemSameComponents(filter);

  static bool _isFalling(BState state) =>
      state.key.startsWith('minecraft:') &&
      (state.key.contains('sand') ||
          state.key == 'minecraft:gravel' ||
          state.key.endsWith('_concrete_powder'));
}
