// Throwaway benchmark: assembly cost of Contraption.searchMovedStructure on the Dart VM.
//
// A cube of slime blocks is the realistic "big glued machine": every face between two slime
// blocks sticks, exactly like a glued structure, and it needs no glue entity.
//
// `_MapLevel` counts every `stateAt`/`isLoaded` as a host read (a wasm boundary crossing on the
// real server) and, when `cache` is set, serves repeats inside a batch from a map, the way
// `HostBlockGetter` does.
import 'dart:collection';

import 'package:create/src/api/block_state.dart';
import 'package:create/src/common/common.dart';
import 'package:create/src/contraptions/core/contraption.dart';
import 'package:create/src/contraptions/core/level.dart';
import 'package:create/src/contraptions/core/structure_info.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox;

int reads = 0;
int pops = 0;

final class _MapLevel extends ContraptionLevel {
  final Map<Pos, BState> blocks;
  final bool cache;

  _MapLevel(this.blocks, {required this.cache});

  int _depth = 0;
  final Map<Pos, BState> _states = {};

  @override
  void beginBatch() => _depth++;

  @override
  void endBatch() {
    if (--_depth == 0) _states.clear();
  }

  @override
  String get worldId => 'test:world';
  @override
  ContraptionSettings get settings => DefaultContraptionSettings();

  @override
  BState stateAt(Pos p) {
    if (cache && _depth > 0) {
      final hit = _states[p];
      if (hit != null) return hit;
      reads++;
      return _states[p] = blocks[p] ?? BState.air;
    }
    reads++;
    return blocks[p] ?? BState.air;
  }

  @override
  bool isLoaded(Pos p) {
    reads++;
    return true;
  }

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
}

final class _Bench extends Contraption {
  final List<Pos> initial;
  _Bench(this.initial);

  @override
  bool moveBlock(
    ContraptionLevel level,
    Direction? forcedDirection,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    pops++;
    return super.moveBlock(level, forcedDirection, frontier, visited);
  }

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

Future<void> run(String label, Map<Pos, BState> blocks, {required bool cache}) async {
  final level = _MapLevel(blocks, cache: cache);
  reads = 0;
  pops = 0;
  final c = _Bench([blocks.keys.first]);
  final watch = Stopwatch()..start();
  var ok = false;
  try {
    ok = await c.assemble(level, (0, 0, 0));
  } catch (_) {
    ok = false;
  }
  watch.stop();
  final n = c.blocks.length;
  print(
    '${cache ? 'batched' : 'per-read'} $label: blocks=$n ok=$ok '
    'assemble=${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
    'hostReads=$reads pops=$pops '
    'reads/block=${(reads / (n == 0 ? 1 : n)).toStringAsFixed(1)}',
  );
}

Future<void> main() async {
  const slime = BState('minecraft:slime_block');

  Map<Pos, BState> cube(int sx, int sy, int sz) {
    final blocks = <Pos, BState>{};
    for (var x = 1; x <= sx; x++) {
      for (var y = 0; y < sy; y++) {
        for (var z = 0; z < sz; z++) {
          blocks[(x, y, z)] = slime;
        }
      }
    }
    return blocks;
  }

  final cases = {
    'slime 4x4x4 (64)': cube(4, 4, 4),
    'slime 6x6x6 (216)': cube(6, 6, 6),
    'slime 10x5x10 (500)': cube(10, 5, 10),
  };
  for (final entry in cases.entries) {
    await run(entry.key, entry.value, cache: false);
    await run(entry.key, entry.value, cache: true);
  }
}
