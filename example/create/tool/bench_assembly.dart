// Throwaway benchmark: assembly cost of Contraption.searchMovedStructure on the Dart VM.
import 'dart:collection';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

int stateAtCalls = 0;

final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;
  _MapLevel(this.blocks);

  @override
  String get worldId => 'test:world';
  @override
  ContraptionSettings get settings => DefaultContraptionSettings();
  @override
  BState stateAt(Pos p) {
    stateAtCalls++;
    return blocks[p] ?? BState.air;
  }

  @override
  bool isLoaded(Pos p) => true;
  @override
  bool isFaceSturdy(Pos p, Direction face) => !stateCollisionEmpty(stateAt(p));
  @override
  List<BlockBox> collisionBoxes(Pos p) => stateCollisionBoxes(stateAt(p));
  @override
  bool supportShapeEmpty(Pos p) => stateCollisionEmpty(stateAt(p));
  @override
  bool canBeReplaced(Pos p) => stateReplaceable(stateAt(p));
  @override
  bool hasTag(Pos p, String tag) => false;
  @override
  bool isWater(Pos p) => false;
  @override
  bool isOutsideBuildHeight(Pos p) => false;
  @override
  int get minY => -64;
  @override
  CapturedBlockEntity? blockEntityAt(Pos p) => null;
  @override
  PushReaction pushReaction(BState state) => PushReaction.normal;
  @override
  bool isUnbreakable(BState state) => false;
  @override
  bool stateHasTag(BState state, String tag) => false;
  @override
  bool stateCollisionEmpty(BState state) => state.isAir;
  @override
  bool stateReplaceable(BState state) => state.isAir;
  @override
  List<BlockBox> stateCollisionBoxes(BState state) =>
      state.isAir ? const [] : const [BlockBox(0, 0, 0, 1, 1, 1)];
  @override
  List<GlueRef> gluesIn(Aabb area) =>
      glue == null ? const [] : [GlueRef(1, glue!)];
  Aabb? glue;
}

final class _Bench extends Contraption {
  final List<Pos> initial;
  _Bench(this.initial);
  @override
  bool addToInitialFrontier(
    ContraptionLevel level,
    Pos pos,
    Direction? forcedDirection,
    Queue<Pos> frontier,
  ) {
    frontier.addAll(initial);
    return true;
  }
}

Future<void> run(String label, Map<Pos, BState> blocks, List<Pos> initial) async {
  final level = _MapLevel(blocks)..glue = Aabb(-1, -1, -1, 64, 64, 64);
  stateAtCalls = 0;
  final c = _Bench(initial);
  final watch = Stopwatch()..start();
  var ok = false;
  try {
    ok = await c.assemble(level, (0, 0, 0));
  } catch (e) {
    ok = false;
  }
  watch.stop();
  final n = c.blocks.length;
  print(
    '$label: blocks=$n ok=$ok '
    'assemble=${(watch.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms '
    'stateAt=$stateAtCalls us/block=${(watch.elapsedMicroseconds / (n == 0 ? 1 : n)).toStringAsFixed(1)}',
  );
}

Future<void> main() async {
  const stone = BState('minecraft:stone');
  const shaft = BState('create:shaft', {'axis': 'y'});

  // The anchor block stays in the world; the frontier starts at its neighbour.
  for (final size in [4, 6, 8]) {
    final blocks = <Pos, BState>{};
    for (var x = 1; x <= size; x++) {
      for (var y = 0; y < size; y++) {
        for (var z = 0; z < size; z++) {
          blocks[(x, y, z)] = stone;
        }
      }
    }
    await run('cube${size}x${size}x$size', blocks, [(1, 0, 0)]);
  }

  // A realistic machine: a 40x40 plate of shafts.
  final plate = <Pos, BState>{};
  for (var x = 1; x <= 40; x++) {
    for (var z = 0; z < 40; z++) {
      plate[(x, 0, z)] = shaft;
    }
  }
  await run('shaftplate40x40', plate, [(1, 0, 0)]);
  // Same plate, but the search starts at the far corner: worst case for the frontier.
  await run('shaftplate40x40-corner', plate, [(40, 0, 39)]);

  // A 2000-block corridor: long and thin, the frontier stays small.
  final corridor = <Pos, BState>{};
  for (var x = 1; x <= 2000; x++) {
    corridor[(x, 0, 0)] = stone;
  }
  await run('corridor2000', corridor, [(1, 0, 0)]);
}
