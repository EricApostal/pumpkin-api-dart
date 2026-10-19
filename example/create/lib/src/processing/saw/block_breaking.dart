// `BlockBreakingKineticBlockEntity` (host side): the kinetic machines that grind through the
// block in front of them (the mechanical drill and the horizontal saw). Ported from
// `content/kinetics/base/BlockBreakingKineticBlockEntity.java`; the contraption half is
// `contraptions/actors/block_breaking_movement_behaviour.dart`.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart' hide pos;
import '../../common/host_bridge.dart';
import '../support/kinetics_bridge.dart';

/// `NEXT_BREAKER_ID`: the negative break progress ids the machines of this part use.
int _nextBreakerId = 0;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

final Random _random = Random();

/// `DrillBlock.getDamage`: the damage a saw or drill deals at [speed] RPM (1..10).
double kineticDamage(double speed) {
  final s = speed.abs();
  final sub1 = (s / 16) < 2 ? s / 16 : 2.0;
  final sub2 = (s / 32) < 4 ? s / 32 : 4.0;
  final sub3 = (s / 64) < 4 ? s / 64 : 4.0;
  return (sub1 + sub2 + sub3).clamp(1.0, 10.0);
}

/// [BlockBehavior] with the hooks the kinetic builder does not expose (`onEntityCollision`,
/// `onLandedUpon`), keeping every hook it set.
BlockBehavior withBlockHooks(
  BlockBehavior b, {
  FutureOr<void> Function(
    Server server,
    CustomBlockEntityCollisionEventData event,
  )?
  onEntityCollision,
  FutureOr<double> Function(Server server, CustomBlockLandedEventData event)?
  onLandedUpon,
}) => BlockBehavior(
  onNeighborUpdate: b.onNeighborUpdate,
  onPlaced: b.onPlaced,
  onStateReplaced: b.onStateReplaced,
  onBroken: b.onBroken,
  onScheduledTick: b.onScheduledTick,
  onRandomTick: b.onRandomTick,
  onEntityCollision: onEntityCollision ?? b.onEntityCollision,
  onEntityStep: b.onEntityStep,
  onCanPlace: b.onCanPlace,
  onUpdateShape: b.onUpdateShape,
  onWeakPower: b.onWeakPower,
  onStrongPower: b.onStrongPower,
  onComparatorOutput: b.onComparatorOutput,
  onShape: b.onShape,
  onUse: b.onUse,
  onUseWithItem: b.onUseWithItem,
  onUseWithoutItem: b.onUseWithoutItem,
  onAttack: b.onAttack,
  onCloneItem: b.onCloneItem,
  onPlayerWillDestroy: b.onPlayerWillDestroy,
  onFriction: b.onFriction,
  onSpeedFactor: b.onSpeedFactor,
  onJumpFactor: b.onJumpFactor,
  canEntityDestroy: b.canEntityDestroy,
  isPathfindable: b.isPathfindable,
  canConnectRedstone: b.canConnectRedstone,
  onLandedUpon: onLandedUpon ?? b.onLandedUpon,
  soundType: b.soundType,
  onFireSpread: b.onFireSpread,
  redstoneOutput: b.redstoneOutput,
  comparatorOutput: b.comparatorOutput,
  priority: b.priority,
);

/// The base of the mechanical drill and the horizontal saw.
abstract class BlockBreakingKineticBlockEntity extends KineticBlockEntity {
  BlockBreakingKineticBlockEntity(super.worldId, super.pos);

  /// `ticksUntilNextProgress`: ticks until the next bit of progress, `-1` when the next block
  /// should start from scratch.
  int ticksUntilNextProgress = 0;

  /// `destroyProgress`: 0..10.
  int destroyProgress = 0;

  /// `breakerId`: a unique negative id (the host has no break progress overlay to send it to).
  final int breakerId = -(_nextBreakerId++ + 1);

  /// `breakingPos`.
  Pos? breakingPos;

  /// `getBreakingPos`.
  Pos getBreakingPos();

  /// `shouldRun`.
  bool shouldRun() => true;

  /// `destroyNextTick`.
  void destroyNextTick() => ticksUntilNextProgress = 1;

  @override
  void lazyTick() {
    super.lazyTick();
    if (ticksUntilNextProgress == -1) destroyNextTick();
  }

  @override
  void onSpeedChanged(double previousSpeed) {
    super.onSpeedChanged(previousSpeed);
    if (destroyProgress == -1) destroyNextTick();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('Progress', destroyProgress);
    tag.putInt('NextTick', ticksUntilNextProgress);
    final bp = breakingPos;
    if (bp != null) NbtHelper.writeBlockPos(tag, 'Breaking', bp);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    destroyProgress = tag.getInt('Progress') ?? 0;
    ticksUntilNextProgress = tag.getInt('NextTick') ?? 0;
    breakingPos = tag.containsKey('Breaking')
        ? NbtHelper.readBlockPos(tag, 'Breaking')
        : null;
    super.read(tag, clientPacket: clientPacket);
  }

  @override
  void tick() {
    super.tick();

    final w = world;
    if (w == null || !shouldRun() || speed == 0) return;

    final bp = breakingPos = getBreakingPos();
    if (ticksUntilNextProgress < 0) return;
    if (ticksUntilNextProgress-- > 0) return;

    final blockPos = bp.toBlockPos();
    final state = w.getBlockState(pos: blockPos);
    final hardness = state.hardness;
    if (!canBreakState(state, hardness)) {
      destroyProgress = 0;
      return;
    }

    final breakSpeed = getBreakSpeed();
    final gain = hardness <= 0
        ? 10 - destroyProgress
        : _clampInt((breakSpeed / hardness).toInt(), 1, 10 - destroyProgress);
    destroyProgress += gain;

    if (destroyProgress >= 10) {
      unawaited(onBlockBrokenState(state));
      destroyProgress = 0;
      ticksUntilNextProgress = -1;
      return;
    }

    ticksUntilNextProgress = hardness <= 0
        ? 0
        : (hardness / breakSpeed).toInt();
  }

  /// `canBreak(stateToBreak, blockHardness)`.
  bool canBreakState(BlockState stateToBreak, double blockHardness) =>
      isBreakable(
        liquid: stateToBreak.isLiquid,
        air: stateToBreak.isAir,
        hardness: blockHardness,
        nonBreakable: Tags.block(
          stateToBreak.blockName,
          'create:non_breakable',
        ),
      );

  /// `BlockBreakingKineticBlockEntity.isBreakable`.
  static bool isBreakable({
    required bool liquid,
    required bool air,
    required double hardness,
    required bool nonBreakable,
  }) => !(liquid || air || hardness == -1 || nonBreakable);

  /// `onBlockBroken`: the block is destroyed and its drops become item entities at its centre.
  Future<void> onBlockBrokenState(BlockState stateToBreak) async {
    final w = world;
    final bp = breakingPos;
    if (w == null || bp == null) return;
    final centre = VecHelper.offsetRandomly(bp.center, _random, .125);
    await BlockHelper.destroyBlockWith(w, bp, 1, (stack) async {
      await w.dropItem(centre, stack, pickupDelay: 10);
    });
  }

  /// `getBreakSpeed`.
  double getBreakSpeed() => (speed / 100).abs();
}
