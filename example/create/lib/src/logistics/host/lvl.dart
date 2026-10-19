// A Create flavoured view of a host `World` for the logistics blocks: block states by `Pos`,
// redstone reads, block writes. Cheap to create; holds nothing.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/util.dart' hide pos;

/// Block state data of a position.
typedef StateInfo = ({String key, Map<String, String> properties});

final class Lvl {
  final World world;

  const Lvl(this.world);

  String get id => world.getId();

  bool isLoaded(Pos pos) => world.isLoaded(pos: pos.toBlockPos());

  int stateId(Pos pos) => world.getBlockStateId(pos: pos.toBlockPos());

  /// The block key and properties at [pos].
  StateInfo? info(Pos pos) => BlockStates.info(stateId(pos));

  String blockKey(Pos pos) => info(pos)?.key ?? 'minecraft:air';

  bool canBeReplaced(Pos pos) => world.getBlockState(pos: pos.toBlockPos()).replaceable;

  /// `BlockState.isFaceSturdy(level, pos, face)`.
  bool isFaceSturdy(Pos pos, Direction face) {
    final s = world.getBlockState(pos: pos.toBlockPos());
    return switch (face) {
      Direction.down => s.downSideSolid,
      Direction.up => s.upSideSolid,
      Direction.north => s.northSideSolid,
      Direction.south => s.southSideSolid,
      Direction.west => s.westSideSolid,
      Direction.east => s.eastSideSolid,
    };
  }

  /// `level.hasNeighborSignal(pos)`.
  Future<bool> hasNeighborSignal(Pos pos) => world.hasRedstoneNeighborSignal(pos.toBlockPos());

  /// `level.getBestNeighborSignal(pos)`.
  Future<int> bestNeighborSignal(Pos pos) => world.bestNeighborSignal(pos.toBlockPos());

  /// `level.getSignal(pos.relative(d), d)`.
  Future<int> signalFrom(Pos reader, Direction d) => world.redstonePower(reader.toBlockPos(), d.toHost());

  Future<void> setState(Pos pos, int stateId, {bool neighbors = false}) => world.setBlockState(
    pos: pos.toBlockPos(),
    state: stateId,
    updateFlags: neighbors ? BlockUpdateFlags.normal : BlockUpdateFlags.clientsOnly,
  );

  /// `state.setValue(...)` of the block at [pos]; nothing happens when the block lacks the properties.
  Future<void> setProps(Pos pos, Map<String, String> values, {bool neighbors = false}) async {
    final current = stateId(pos);
    final next = BlockStates.setValues(current, values);
    if (next == current) return;
    await setState(pos, next, neighbors: neighbors);
  }

  Future<void> updateNeighbors(Pos pos) => world.notifyNeighbors(pos.toBlockPos());

  Future<bool> destroyBlock(Pos pos, {bool drop = true}) => world.breakBlock(pos.toBlockPos(), drop: drop);

  int get gameTime => world.getWorldAge();
}

void spawn(Future<void> Function() f) => unawaited(f());
