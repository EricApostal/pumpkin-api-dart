// Host side of the sliding doors: applying the pure door actions and the redstone check.
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/direction.dart' as d;
import '../common/host_bridge.dart';
import '../common/pos.dart';
import 'door.dart';
import 'runtime.dart';

final math.Random _random = math.Random();

/// `Level.hasNeighborSignal` for a set of positions, resolved up front (the pure door logic asks
/// synchronously, the host answers asynchronously).
Future<Set<Pos>> poweredAround(World world, Pos pos, BState state) async {
  final result = <Pos>{};
  final lower = state['half'] == 'lower';
  final hinge = state['hinge'] ?? 'left';
  final facing = state.dir('facing');
  final candidates = <Pos>{pos, pos.relative(lower ? d.Direction.up : d.Direction.down)};
  if (facing != null) {
    final other = otherDoorPos(pos, hinge, facing);
    candidates
      ..add(other)
      ..add(other.relative(lower ? d.Direction.up : d.Direction.down));
  }
  for (final p in candidates) {
    if (await world.hasRedstoneNeighborSignal(p.toBlockPos())) result.add(p);
  }
  return result;
}

/// Writes the changes of a door action and plays its sound.
Future<void> applyDoorAction(DecorationRuntime rt, World world, DoorAction action) async {
  final level = HostBlockGetter(world);
  for (final (p, s) in action.changes) {
    await setBlockState(world, p, s);
    // The other half of the door follows through `updateShape`; set it as well so it does not
    // depend on the host's shape update order.
    final otherPos = p.relative(s['half'] == 'lower' ? d.Direction.up : d.Direction.down);
    final other = level.stateAt(otherPos);
    if (other.key == s.key && other['half'] != s['half']) {
      final synced = s.setValue('half', other['half']!);
      if (synced != other) await setBlockState(world, otherPos, synced);
    }
  }
  final sound = action.sound;
  if (sound != null) {
    rt.playSound(world, sound.$1, sound.$2 ? doorOpenSound : doorCloseSound, pitch: _random.nextDouble() * 0.1 + 0.9);
  }
}

/// `SlidingDoorBlock.neighborChanged` for the door at [pos] (called by the update hook and, one
/// tick after placing, by the block entity).
Future<void> slidingDoorNeighborChange(
  DecorationRuntime rt,
  World world,
  Pos pos, {
  required bool sourceIsSameBlock,
}) async {
  // `defaultBlockState().is(pBlock)`: the other half of the door changed, nothing to do.
  if (sourceIsSameBlock) return;
  final level = HostBlockGetter(world);
  final state = level.stateAt(pos);
  if (!slidingDoorKeys.contains(state.key)) return;
  final lower = state['half'] == 'lower';
  final be = rt.store.at(world.getId(), (lower ? pos : pos.below).toBlockPos());
  final deferred = be is DoorDeferrable && (be as DoorDeferrable).deferUpdate;
  final powered = await poweredAround(world, pos, state);
  final action = slidingDoorNeighborChanged(
    level,
    pos,
    state,
    sourceIsSameBlock: sourceIsSameBlock,
    deferUpdate: deferred,
    hasNeighborSignal: powered.contains,
  );
  await applyDoorAction(rt, world, action);
}

/// Implemented by the sliding door block entity: whether the redstone check is postponed.
abstract interface class DoorDeferrable {
  bool get deferUpdate;
}
