// A thin, Create flavoured view of a host `World` for the redstone blocks: block
// states by `Pos`, the redstone reads of `Level` (`getSignal`, `hasNeighborSignal`,
// ...), block writes with the vanilla update flags and scheduled ticks.
//
// Java -> host mapping used everywhere in this module:
//  * `level.getSignal(pos.relative(d), d)`      -> [Lvl.signalFrom] (pos, d)
//  * `level.getDirectSignal(pos.relative(d), d)` -> [Lvl.directSignalFrom] (pos, d)
//  * `Block.UPDATE_CLIENTS` (2) / `UPDATE_ALL` (3) -> [Lvl.setState] without / with `neighbors`
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;

/// Block state data of a position.
typedef StateInfo = ({String key, Map<String, String> properties});

/// A host [World] seen with Create's types. Cheap to create; holds the world only
/// for as long as the caller keeps its own handle valid.
final class Lvl {
  final World world;

  const Lvl(this.world);

  String get id => world.getId();

  bool isLoaded(Pos pos) => world.isLoaded(pos: pos.toBlockPos());

  /// The state id at [pos].
  int stateId(Pos pos) => world.getBlockStateId(pos: pos.toBlockPos());

  /// The block key and properties at [pos].
  StateInfo? info(Pos pos) => BlockStates.info(stateId(pos));

  /// The block key at [pos] (`minecraft:air` when unknown).
  String blockKey(Pos pos) => info(pos)?.key ?? 'minecraft:air';

  /// `BlockState.canBeReplaced()` of the state at [pos].
  bool canBeReplaced(Pos pos) => world.getBlockState(pos: pos.toBlockPos()).replaceable;

  /// Whether the top of the block at [pos] can carry a rigid block
  /// (`Block.canSupportRigidBlock`).
  bool canSupportRigid(Pos pos) {
    final s = world.getBlockState(pos: pos.toBlockPos());
    return s.upSideSolid || s.upCenterSolid;
  }

  // -- Redstone reads ------------------------------------------------------------------

  /// `level.getSignal(pos.relative(d), d)`: the power [reader] receives from the
  /// neighbour on side [d].
  Future<int> signalFrom(Pos reader, Direction d) => world.redstonePower(reader.toBlockPos(), d.toHost());

  /// `level.getDirectSignal(pos.relative(d), d)`.
  Future<int> directSignalFrom(Pos reader, Direction d) => world.directRedstonePower(reader.toBlockPos(), d.toHost());

  /// `level.hasNeighborSignal(pos)`.
  Future<bool> hasNeighborSignal(Pos pos) => world.hasRedstoneNeighborSignal(pos.toBlockPos());

  /// `level.getBestNeighborSignal(pos)`.
  Future<int> bestNeighborSignal(Pos pos) => world.bestNeighborSignal(pos.toBlockPos());

  /// `level.getDirectSignalTo(pos)`: the strongest direct signal reaching [pos].
  Future<int> directSignalTo(Pos pos) async {
    var best = 0;
    for (final d in Direction.values) {
      final s = await directSignalFrom(pos, d);
      if (s > best) best = s;
      if (best >= 15) break;
    }
    return best;
  }

  /// The best of `getSignal` over all six sides of [pos]
  /// (`max(level.getSignal(pos.relative(d), d))`).
  Future<int> maxSignalAround(Pos pos) async {
    var power = 0;
    for (final d in Direction.values) {
      final s = await signalFrom(pos, d);
      if (s > power) power = s;
    }
    return power;
  }

  /// `getPower` of the redstone link and the nixie tube: the strongest signal around [pos].
  /// Java reads every neighbour twice, once from its own side and once as if looking from above
  /// (the second read lets blocks that only answer for the `UP` side count); [facing] is the
  /// block's `facing`: the block behind it is skipped in the second loop.
  Future<int> linkStylePower(Pos pos, Direction facing) async {
    var power = await maxSignalAround(pos);
    for (final d in Direction.values) {
      if (facing.opposite == d) continue;
      final s = await signalFrom(pos.relative(d), Direction.up);
      if (s > power) power = s;
    }
    return power;
  }

  // -- Writes --------------------------------------------------------------------------

  /// `level.setBlock(pos, state, flags)`: [neighbors] is flag 1 (`UPDATE_NEIGHBORS`);
  /// clients are always notified (flag 2).
  Future<void> setState(Pos pos, int stateId, {bool neighbors = false}) => world.setBlockState(
    pos: pos.toBlockPos(),
    state: stateId,
    updateFlags: neighbors ? BlockUpdateFlags.normal : BlockUpdateFlags.clientsOnly,
  );

  /// `state.setValue(...)` of the block at [pos], written with `UPDATE_CLIENTS` or `UPDATE_ALL`.
  /// Does nothing when the block has none of the properties.
  Future<void> setProps(Pos pos, Map<String, String> values, {bool neighbors = false}) async {
    final current = stateId(pos);
    final next = BlockStates.setValues(current, values);
    if (next == current) return;
    await setState(pos, next, neighbors: neighbors);
  }

  /// `level.updateNeighborsAt(pos, block)`.
  Future<void> updateNeighbors(Pos pos) => world.notifyNeighbors(pos.toBlockPos());

  /// `level.scheduleTick(pos, block, delay, priority)`.
  void scheduleTick(Pos pos, int delay, {TickPriority priority = TickPriority.normal}) =>
      world.scheduleBlockTick(pos: pos.toBlockPos(), delayTicks: delay.clamp(0, 255), priority: priority);

  /// `level.destroyBlock(pos, drop)`.
  Future<bool> destroyBlock(Pos pos, {bool drop = true}) => world.breakBlock(pos.toBlockPos(), drop: drop);

  /// `level.getGameTime()`.
  int get gameTime => world.getWorldAge();

  /// Plays a lever click like `level.playSound(null, pos, SoundEvents.LEVER_CLICK, BLOCKS, volume, pitch)`.
  void playLeverClick(Pos pos, double volume, double pitch) => world.playSound(
    sound: Sound.blockLeverClick,
    category: SoundCategory.blocks,
    pos: pos.center,
    volume: volume,
    pitch: pitch,
  );
}

/// Fire and forget: runs [f] and logs nothing (errors surface as uncaught errors of the
/// callback, which the host logs).
void spawn(Future<void> Function() f) => unawaited(f());
