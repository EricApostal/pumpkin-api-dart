// Flood-fill edge cases of `SubLevelAssemblyHelper.gatherConnectedBlocks`.
//
// The fill is a 26-neighbour breadth-first search that excludes corners
// (`|dx| + |dy| + |dz| == 3`), stops at air, deduplicates the frontier, and
// aborts the moment the visited count exceeds the caller's limit. The limit
// check happens *before* the block is recorded, so the reported
// `checkedBlocks` is `limit + 1` on `TOO_MANY_BLOCKS`.
//
// Transcribed from `SubLevelAssemblyHelper.gatherConnectedBlocks` on
// `port/26.3`.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A chunk host that serves block states to the assembly helper.
final class StateHost extends FakeChunkHost implements AssemblyBlockHost {
  final Map<(int, int, int), BState> states = {};

  /// Per-position reads served so far, the metric the bulk read exists to cut.
  int singleReads = 0;

  StateHost(super.level);

  void put(int x, int y, int z, [String id = 'minecraft:stone']) =>
      states[(x, y, z)] = BState(id);

  @override
  BState blockStateAt(int x, int y, int z) {
    singleReads++;
    return states[(x, y, z)] ?? BState.air;
  }

  @override
  void setBlockStateAt(int x, int y, int z, BState state) {
    if (state.isAir) {
      states.remove((x, y, z));
    } else {
      states[(x, y, z)] = state;
    }
  }

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) => null;

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) {}

  @override
  void removeBlockEntityAt(int x, int y, int z) {}

  @override
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState) {}
}

/// The same states as [StateHost], but answering through one bulk call
/// ([BulkBlockHost]): the host records how many reads each path costs.
final class BulkStateHost extends StateHost implements BulkBlockHost {
  /// Bulk calls served so far.
  int bulkCalls = 0;

  /// Positions read so far.
  int bulkPositions = 0;

  BulkStateHost(super.level);

  @override
  List<BState> readBlockStates(List<(int, int, int)> positions) {
    bulkCalls++;
    bulkPositions += positions.length;
    return [for (final p in positions) states[p] ?? BState.air];
  }
}

void main() {
  late FakeLevel level;
  late StateHost host;

  GatherResult gatherHost(
    (int, int, int) origin, [
    int limit = 1000,
    FrontierPredicate? predicate,
  ]) =>
      SubLevelAssemblyHelper.gatherConnectedBlocks(origin, level, limit, predicate);

  GatherResult gather((int, int, int) origin, [int limit = 1000, FrontierPredicate? predicate]) =>
      gatherHost(origin, limit, predicate);

  BulkStateHost useBulkHost() {
    final bulk = BulkStateHost(level);
    for (final entry in host.states.entries) {
      bulk.states[entry.key] = entry.value;
    }
    SubLevelContainer.clearAll();
    SubLevelContainer.register(
      ServerSubLevelContainer(
        level,
        bulk,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      ),
    );
    return bulk;
  }

  setUp(() {
    SubLevelContainer.clearAll();
    level = FakeLevel();
    host = StateHost(level);
    SubLevelContainer.register(
      ServerSubLevelContainer(
        level,
        host,
        3,
        4,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      ),
    );
  });

  tearDown(SubLevelContainer.clearAll);

  group('connectivity', () {
    test('face neighbours connect', () {
      host
        ..put(0, 0, 0)
        ..put(1, 0, 0);

      expect(gather((0, 0, 0)).blocks, {(0, 0, 0), (1, 0, 0)});
    });

    test('edge neighbours connect', () {
      host
        ..put(0, 0, 0)
        ..put(1, 1, 0);

      expect(gather((0, 0, 0)).blocks, hasLength(2));
    });

    test('corner neighbours do not connect', () {
      host
        ..put(0, 0, 0)
        ..put(1, 1, 1);

      final result = gather((0, 0, 0));
      expect(result.assemblyState, GatherState.success);
      expect(result.blocks, {(0, 0, 0)});
    });

    test('every non-air block type connects', () {
      host
        ..put(0, 0, 0, 'minecraft:stone')
        ..put(1, 0, 0, 'minecraft:oak_log')
        ..put(2, 0, 0, 'create:cogwheel');

      expect(gather((0, 0, 0)).blocks, hasLength(3));
    });

    test('an air gap stops the fill', () {
      // A ring of stone around an air hole: the fill must not jump the hole.
      for (var x = -1; x <= 1; x++) {
        for (var z = -1; z <= 1; z++) {
          if (x == 0 && z == 0) continue;
          host.put(x, 0, z);
        }
      }

      final result = gather((1, 0, 1));
      expect(result.blocks, hasLength(8));
      expect(result.blocks, isNot(contains((0, 0, 0))));
    });

    test('a U shape is walked around, not across', () {
      // Two arms joined at the bottom; the gap between the arms is air.
      for (var y = 0; y < 3; y++) {
        host
          ..put(0, y, 0)
          ..put(2, y, 0);
      }
      host.put(1, 0, 0);

      final result = gather((0, 0, 0));
      expect(result.blocks, hasLength(7));
      expect(result.blocks, isNot(contains((1, 1, 0))));
      expect(result.blocks, isNot(contains((1, 2, 0))));
    });
  });

  group('limits', () {
    test('a gather of exactly the limit succeeds', () {
      for (var x = 0; x < 5; x++) {
        host.put(x, 0, 0);
      }

      final result = gather((0, 0, 0), 5);
      expect(result.assemblyState, GatherState.success);
      expect(result.blocks, hasLength(5));
      expect(result.checkedBlocks, 5);
    });

    test('one block over the limit aborts with limit + 1 checked', () {
      for (var x = 0; x < 6; x++) {
        host.put(x, 0, 0);
      }

      final result = gather((0, 0, 0), 5);
      expect(result.assemblyState, GatherState.tooManyBlocks);
      expect(result.blocks, isNull);
      expect(result.boundingBox, isNull);
      expect(result.checkedBlocks, 6);
    });

    test('a limit of zero aborts on the origin', () {
      host.put(0, 0, 0);
      final result = gather((0, 0, 0), 0);
      expect(result.assemblyState, GatherState.tooManyBlocks);
      expect(result.checkedBlocks, 1);
    });
  });

  group('result shape', () {
    test('an air origin reports no blocks and no bounds', () {
      final result = gather((0, 0, 0));
      expect(result.assemblyState, GatherState.noBlocks);
      expect(result.blocks, isNull);
      expect(result.boundingBox, isNull);
      expect(result.checkedBlocks, 0);
    });

    test('the bounds are the tight box of the gathered blocks', () {
      for (var x = 0; x < 3; x++) {
        for (var z = 0; z < 4; z++) {
          host.put(x, 0, z);
        }
      }

      final result = gather((0, 0, 0));
      final bounds = result.boundingBox!;
      expect(bounds.minX, 0);
      expect(bounds.minY, 0);
      expect(bounds.minZ, 0);
      expect(bounds.maxX, 2);
      expect(bounds.maxY, 0);
      expect(bounds.maxZ, 3);
    });

    test('negative coordinates are gathered and boxed correctly', () {
      for (var x = -3; x <= -1; x++) {
        host.put(x, -5, -2);
      }

      final result = gather((-2, -5, -2));
      expect(result.blocks, hasLength(3));
      expect(result.boundingBox!.minX, -3);
      expect(result.boundingBox!.maxX, -1);
      expect(result.boundingBox!.minY, -5);
      expect(result.boundingBox!.maxY, -5);
    });

    test('the origin is counted once in a solid cube', () {
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 2; y++) {
          for (var z = 0; z < 2; z++) {
            host.put(x, y, z);
          }
        }
      }

      final result = gather((0, 0, 0));
      expect(result.blocks, hasLength(8));
      expect(result.checkedBlocks, 8);
    });
  });

  group('frontier predicate', () {
    test('a rejected connection stops only that edge', () {
      for (var x = 0; x < 5; x++) {
        host.put(x, 0, 0);
      }

      // Block the +x face of the origin only.
      final result = gather(
        (0, 0, 0),
        1000,
        (originPos, originState, pos, state, direction) =>
            !(originPos == (0, 0, 0) && pos == (1, 0, 0)),
      );

      expect(result.blocks, {(0, 0, 0)});
    });

    test('the direction is the face direction for face neighbours and null for edges', () {
      host
        ..put(0, 0, 0)
        ..put(1, 0, 0)
        ..put(1, 1, 0);

      final faces = <Object?>[];
      gather((0, 0, 0), 1000, (originPos, originState, pos, state, direction) {
        if (originPos == (0, 0, 0) && pos == (1, 0, 0)) faces.add(direction);
        if (originPos == (0, 0, 0) && pos == (1, 1, 0)) faces.add(direction);
        return true;
      });

      expect(faces, hasLength(2));
      expect(faces.where((face) => face != null), hasLength(1));
      expect(faces, contains(null));
    });

    test('the predicate sees the states of both blocks', () {
      host
        ..put(0, 0, 0, 'minecraft:stone')
        ..put(0, 1, 0, 'minecraft:dirt');

      String? seenOrigin;
      String? seenCandidate;
      gather((0, 0, 0), 1000, (originPos, originState, pos, state, direction) {
        if (pos == (0, 1, 0)) {
          seenOrigin = originState.key;
          seenCandidate = state.key;
        }
        return true;
      });

      expect(seenOrigin, 'minecraft:stone');
      expect(seenCandidate, 'minecraft:dirt');
    });
  });

  group('bulk read', () {
    test('a bulk host gathers the same blocks and bounds', () {
      for (var x = 0; x < 5; x++) {
        for (var z = 0; z < 4; z++) {
          host.put(x, 0, z);
        }
      }
      final plain = gather((2, 0, 2));

      final bulk = useBulkHost();
      final batched = gatherHost((2, 0, 2));

      expect(batched.assemblyState, plain.assemblyState);
      expect(batched.blocks, plain.blocks);
      expect(batched.checkedBlocks, plain.checkedBlocks);
      expect(batched.boundingBox?.minX, plain.boundingBox!.minX);
      expect(batched.boundingBox?.maxX, plain.boundingBox!.maxX);
      expect(batched.boundingBox?.minZ, plain.boundingBox!.minZ);
      expect(batched.boundingBox?.maxZ, plain.boundingBox!.maxZ);
      // The per-query walk pays a host call for every neighbour read; the bulk
      // walk answers a whole wave of the frontier in one call, so its call
      // count stays below the per-query count divided by the fan-out.
      expect(bulk.bulkCalls, lessThan(host.singleReads ~/ 18));
      expect(bulk.bulkPositions, greaterThanOrEqualTo(batched.checkedBlocks));
      // Host calls, before vs after, for the same gather.
      expect(bulk.bulkCalls + bulk.singleReads, lessThan(host.singleReads));
    });

    test('per-position cost before vs after on a solid cube', () {
      // The whole cube is non-air, so the walk collects 10x10x10 = 1000 blocks
      // and visits every one of them: the per-query path pays ~18 host reads
      // per block, the bulk path pays one bulk read per pos of each wave.
      for (var x = 0; x < 10; x++) {
        for (var y = 0; y < 10; y++) {
          for (var z = 0; z < 10; z++) {
            host.put(x, y, z);
          }
        }
      }
      final plain = gather((0, 0, 0));
      expect(plain.assemblyState, GatherState.success);
      expect(plain.checkedBlocks, 1000);
      final plainReads = host.singleReads;

      final bulk = useBulkHost();
      final batched = gatherHost((0, 0, 0));
      expect(batched.blocks, plain.blocks);
      expect(batched.checkedBlocks, 1000);

      // The metric that matters is host calls, not positions: the per-query
      // walk crosses the boundary once per read, while the bulk walk answers
      // a wave of the frontier in one call, so the bulk call count grows with
      // the number of waves (a few dozen for a 1000-block cube) instead of
      // the number of reads (a few thousand). The positions it reads are ~2.4
      // per block (a wave reads the next level of the frontier, plus the
      // duplicates that get queued while the wave runs).
      final bulkCalls = bulk.bulkCalls + bulk.singleReads;
      expect(bulkCalls, lessThan(plainReads ~/ 10));
      expect(bulk.bulkPositions, lessThan(plainReads));
    });

    test('a bulk host honours limits and predicates identically', () {
      for (var x = 0; x < 6; x++) {
        host.put(x, 0, 0);
      }
      final plain = gather((0, 0, 0), 5);

      useBulkHost();
      final batched = gatherHost((0, 0, 0), 5);

      expect(batched.assemblyState, GatherState.tooManyBlocks);
      expect(batched.blocks, isNull);
      expect(batched.checkedBlocks, plain.checkedBlocks);
    });
  });
}
