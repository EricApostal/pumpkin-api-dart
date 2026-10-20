// Throwaway benchmark: assembly cost of Contraption.searchMovedStructure on the Dart VM.
//
// `_MapLevel` models the host the way `HostBlockGetter` does: every `stateAt`/`isLoaded` is a
// wasm boundary crossing, counted as `reads`, and `beginBatch`/`endBatch` let it serve repeats
// from a cache exactly like `HostBlockGetter` does.
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
  final List<GlueRef> glues;

  _MapLevel(this.blocks, this.glues, {required this.cache});

  int _depth = 0;
  final Map<Pos, BState> _states = {};
  final Map<Pos, bool> _loaded = {};

  @override
  void beginBatch() => _depth++;

  @override
  void endBatch() {
    if (--_depth == 0) {
      _states.clear();
      _loaded.clear();
    }
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
    if (cache && _depth > 0) {
      final hit = _loaded[p];
      if (hit != null) return hit;
      reads++;
      return _loaded[p] = true;
    }
    reads++;
    return true;
  }

  @override
  List<GlueRef> gluesIn(Aabb area) => glues;
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
  static final Set<Pos> _seen = {};
  _MapLevel? _lvl;

  @override
  bool moveBlock(
    ContraptionLevel level,
    Direction? forcedDirection,
    Queue<Pos> frontier,
    Set<Pos> visited,
  ) {
    pops++;
    final before = frontier.toList();
    final r = super.moveBlock(level, forcedDirection, frontier, visited);
    if (pops > 90000 && pops < 90004) {
      final added = frontier.where((p) => !before.contains(p)).toList();
      print('pop $pops ${before.first} added=$added visited=${visited.length}');
    }
    return r;
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

Future<void> run(
  String label,
  Map<Pos, BState> blocks, {
  required bool cache,
}) async {
  // Super glue on every block of the structure: the faces between them are glued, the air
  // around them is not (that is what a player's glue placement looks like).
  final glues = <GlueRef>[
    for (final (i, p) in blocks.keys.indexed) GlueRef(i, Aabb.ofBlock(p)),
  ];
  final level = _MapLevel(blocks, glues, cache: cache);
  reads = 0;
  pops = 0;
  final c = _Bench([blocks.keys.first]).._lvl = level;
  final watch = Stopwatch()..start();
  var ok = false;
  try {
    ok = await c.assemble(level, (0, 0, 0));
  } catch (_) {
    ok = false;
  }
  watch.stop();
  final n = c.blocks.length;
  print('distinct popped positions: ${_Bench._seen.length}');
  print(
    '${cache ? 'cached  ' : 'uncached'} $label: blocks=$n ok=$ok '
    'assemble=${(watch.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms '
    'hostReads=$reads pops=$pops '
    'reads/block=${(reads / (n == 0 ? 1 : n)).toStringAsFixed(1)}',
  );
}

Future<void> main() async {
  const stone = BState('minecraft:stone');
  const shaft = BState('create:shaft', {'axis': 'y'});

  Map<Pos, BState> cube(int sx, int sy, int sz, BState state) {
    final blocks = <Pos, BState>{};
    for (var x = 1; x <= sx; x++) {
      for (var y = 0; y < sy; y++) {
        for (var z = 0; z < sz; z++) {
          blocks[(x, y, z)] = state;
        }
      }
    }
    return blocks;
  }

  final cases = {
    'cube10x5x10 (500 stone)': cube(10, 5, 10, stone),
    'plate16x4x16 (1024 shafts)': cube(16, 4, 16, shaft),
    'cube6x6x6 (216 stone)': cube(6, 6, 6, stone),
  };
  for (final entry in cases.entries) {
    await run(entry.key, entry.value, cache: false);
    await run(entry.key, entry.value, cache: true);
  }
}
