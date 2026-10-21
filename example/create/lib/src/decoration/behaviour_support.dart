// Helpers shared by the block behaviours of the decoration module.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import '../core/blocks.dart';
import 'runtime.dart';

/// `index of [state]` in the layout of [block], or `null` when a value is outside the block's domain.
///
/// Use this for a `update-shape` answer: the hook answers with a state index *of the block*, never
/// with a global state id (see [stateIndexIn]).
int? stateIndexOf(CreateBlock block, BState state) => stateIndexIn(block.layout, state);

/// The `update-shape` answer for a change from [before] to [after]: `null` keeps the state; the
/// state becoming air is handled by the caller (see [scheduleBreak]).
int? shapeAnswer(CreateBlock block, BState before, BState after) {
  if (after == before) return null;
  if (after.isAir) return null;
  return stateIndexOf(block, after);
}

/// The first value of a placement event (`oldStateId`) says the block was already there with only
/// its state changed.
bool isFreshPlacement(DecorationRuntime rt, String blockKey, int? oldStateId) {
  if (oldStateId == null) return true;
  return BlockStates.blockKey(oldStateId) != blockKey;
}

/// Whether the placement logic of a block should run for a `placed` event: the block was freshly put
/// there (not just a state change of itself), and for a placement by a player only once, in the
/// `player-placed` event that carries the player (the host first fires the plain `placed` event).
bool shouldFixPlacement(DecorationRuntime rt, String blockKey, int? oldStateId, Uuid? player, Pos pos) {
  if (!isFreshPlacement(rt, blockKey, oldStateId)) return false;
  if (player == null && rt.playerPlacementPending(pos)) return false;
  return true;
}

/// Block ticks the host runs after one tick: used to emulate "`updateShape` returned air" (the host's
/// update-shape hook can only choose another state of the same block) and the survival checks.
void scheduleBreak(World world, Pos pos, {int ticks = 1}) {
  world.scheduleBlockTick(pos: pos.toBlockPos(), delayTicks: ticks, priority: TickPriority.normal);
}

/// `Level.destroyBlock(pos, true)`.
Future<void> breakWithDrops(World world, Pos pos) async {
  await world.destroyBlock(pos: pos.toBlockPos(), drop: true, player: null, withParticles: true);
}

/// `Level.hasNeighborSignal`.
Future<bool> hasNeighborSignal(World world, Pos pos) => world.hasRedstoneNeighborSignal(pos.toBlockPos());

/// The waterlogged flag the placement at [pos] should have (`replacedFluidState.is(Fluids.WATER)`).
bool placedInWater(World world, Pos pos) => HostBlockGetter(world).isWater(pos);

/// Does the work of `onPlaced` for a state fix: writes [fixed] if it differs from [placed].
Future<void> fixPlacedState(World world, Pos pos, BState placed, BState fixed) async {
  if (fixed != placed && !fixed.isAir) await setBlockState(world, pos, fixed);
}

/// The block `Direction` of an event direction.
d.Direction dirOf(BlockDirection x) => d.Direction.values[x.index];

/// The three outcomes of an item use that the hooks return.
const BlockUseResult useSuccess = BlockUseResult.success;
const BlockUseResult usePass = BlockUseResult.pass;
const BlockUseResult useTryEmpty = BlockUseResult.tryEmptyHand;
const BlockUseResult useFail = BlockUseResult.fail;
