// W3: the assembly helper (flood fill, transform, mass movement) and the pure
// math it is built on. Runs on the VM.
import 'package:create/src/api/block_state.dart' show BState;
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A chunk host that also serves block states to the assembly helper.
final class AssemblyChunkHost extends FakeChunkHost implements AssemblyBlockHost, AssemblyEntityHost {
  final Map<(int, int, int), BState> states = {};
  final Map<(int, int, int), Map<String, Object?>> blockEntities = {};
  final List<AssemblyEntity> entities = [];
  final List<String> notifications = [];

  AssemblyChunkHost(super.level);

  @override
  BState blockStateAt(int x, int y, int z) => states[(x, y, z)] ?? BState.air;

  @override
  void setBlockStateAt(int x, int y, int z, BState state) {
    if (state.isAir) {
      states.remove((x, y, z));
    } else {
      states[(x, y, z)] = state;
    }
  }

  @override
  Map<String, Object?>? blockEntityDataAt(int x, int y, int z) => blockEntities[(x, y, z)];

  @override
  void setBlockEntityDataAt(int x, int y, int z, Map<String, Object?> data) =>
      blockEntities[(x, y, z)] = data;

  @override
  void removeBlockEntityAt(int x, int y, int z) => blockEntities.remove((x, y, z));

  @override
  void notifyBlockChanged(int x, int y, int z, BState oldState, BState newState) =>
      notifications.add('$x,$y,$z:${newState.key}');

  @override
  List<AssemblyEntity> entitiesIn(BoundingBox3dc bounds) => entities;
}

final class FakeAssemblyEntity implements AssemblyEntity {
  @override
  Vector3d position;

  @override
  BoundingBox3ic? supportBox;

  FakeAssemblyEntity(this.position, [this.supportBox]);

  @override
  void setPosition(Vector3d value) => position = value;
}

void main() {
  late FakeLevel level;
  late AssemblyChunkHost host;
  late ServerSubLevelContainer container;

  setUp(() {
    level = FakeLevel();
    host = AssemblyChunkHost(level);
    container = ServerSubLevelContainer(level, host, 3, 4, SubLevelContainer.defaultOrigin, SubLevelContainer.defaultOrigin);
    SubLevelContainer.register(container);
  });

  tearDown(() => SubLevelContainer.unregister(level));

  group('gatherConnectedBlocks', () {
    test('gathers a 3x3x3 cube and its bounds', () {
      for (var x = 0; x < 3; x++) {
        for (var y = 0; y < 3; y++) {
          for (var z = 0; z < 3; z++) {
            host.states[(x, y, z)] = const BState('minecraft:stone');
          }
        }
      }

      final result = SubLevelAssemblyHelper.gatherConnectedBlocks((1, 1, 1), level, 1000, null);
      expect(result.assemblyState, GatherState.success);
      expect(result.blocks, hasLength(27));
      expect(result.boundingBox!.minX, 0);
      expect(result.boundingBox!.maxX, 2);
    });

    test('stops at the block limit', () {
      for (var x = 0; x < 5; x++) {
        host.states[(x, 0, 0)] = const BState('minecraft:stone');
      }

      final result = SubLevelAssemblyHelper.gatherConnectedBlocks((0, 0, 0), level, 3, null);
      expect(result.assemblyState, GatherState.tooManyBlocks);
      expect(result.checkedBlocks, 4);
      expect(result.blocks, isNull);
    });

    test('an air origin gathers nothing', () {
      final result = SubLevelAssemblyHelper.gatherConnectedBlocks((0, 0, 0), level, 10, null);
      expect(result.assemblyState, GatherState.noBlocks);
    });

    test('connects edges but not corners', () {
      host.states[(0, 0, 0)] = const BState('minecraft:stone');
      // Diagonal neighbour: shares only a corner.
      host.states[(1, 1, 1)] = const BState('minecraft:stone');

      final result = SubLevelAssemblyHelper.gatherConnectedBlocks((0, 0, 0), level, 10, null);
      expect(result.assemblyState, GatherState.success);
      expect(result.blocks, {(0, 0, 0)});
    });

    test('honours the frontier predicate', () {
      host.states[(0, 0, 0)] = const BState('minecraft:stone');
      host.states[(1, 0, 0)] = const BState('minecraft:dirt');

      final result = SubLevelAssemblyHelper.gatherConnectedBlocks(
        (0, 0, 0),
        level,
        10,
        (origin, originState, pos, state, direction) => state.key == 'minecraft:stone',
      );
      expect(result.blocks, {(0, 0, 0)});
    });
  });

  group('AssemblyTransform', () {
    test('identity moves blocks to the resulting anchor', () {
      final transform = AssemblyTransform(
        (10, 20, 30),
        (100, 20, 30),
        0,
        Rotation.none,
        level,
      );

      expect(transform.applyBlock((10, 20, 30)), (100, 20, 30));
      expect(transform.applyBlock((11, 20, 30)), (101, 20, 30));
      expect(transform.applyBlock((10, 21, 30)), (100, 21, 30));
    });

    test('a quarter turn rotates around the anchor', () {
      final transform = AssemblyTransform(
        (0, 0, 0),
        (0, 0, 0),
        1,
        Rotation.clockwise90,
        level,
      );

      // `Vec3.yRot(90°)` maps +X onto -Z, the same rotation the Java
      // `AssemblyTransform` applies.
      final moved = transform.applyBlock((1, 0, 0));
      expect(moved.$1, 0);
      expect(moved.$3, -1);
    });

    test('rotates a facing property', () {
      final transform = AssemblyTransform((0, 0, 0), (0, 0, 0), 0, Rotation.clockwise90, level);
      final rotated = transform.applyState(
        const BState('minecraft:furnace', {'facing': 'north'}),
      );
      expect(rotated['facing'], 'east');
    });

    test('swaps the axis property on a quarter turn', () {
      final transform = AssemblyTransform((0, 0, 0), (0, 0, 0), 0, Rotation.clockwise90, level);
      final rotated = transform.applyState(
        const BState('minecraft:oak_log', {'axis': 'x'}),
      );
      expect(rotated['axis'], 'z');
    });

    test('leaves the axis alone on a half turn', () {
      final transform = AssemblyTransform((0, 0, 0), (0, 0, 0), 0, Rotation.clockwise180, level);
      final rotated = transform.applyState(
        const BState('minecraft:oak_log', {'axis': 'x'}),
      );
      expect(rotated['axis'], 'x');
    });
  });

  group('assembleBlocks', () {
    test('moves the blocks into the plot and allocates a server sub-level', () {
      host.states[(5, 64, 5)] = const BState('minecraft:stone');

      final subLevel = SubLevelAssemblyHelper.assembleBlocks(
        level,
        (5, 64, 5),
        [(5, 64, 5)],
        BoundingBox3i.values(4, 63, 4, 6, 65, 6),
      );

      expect(subLevel, isA<ServerSubLevel>());
      expect(host.states.containsKey((5, 64, 5)), isFalse);
      expect(container.getLoadedCount(), 1);
      // The pose starts at the anchor and keeps the plot centre as the
      // rotation point (no mass tracker yet).
      expect(subLevel.logicalPose.position().x, closeTo(5.0, 1e-9));
      expect(subLevel.logicalPose.position().y, closeTo(64.0, 1e-9));
      final centre = subLevel.getPlot().getCenterBlock();
      expect(subLevel.logicalPose.rotationPoint().x, closeTo(centre.$1 + 0.5, 1e-9));
    });

    test('notifies the moved block once', () {
      host.states[(5, 64, 5)] = const BState('minecraft:stone');
      SubLevelAssemblyHelper.assembleBlocks(
        level,
        (5, 64, 5),
        [(5, 64, 5)],
        BoundingBox3i.values(4, 63, 4, 6, 65, 6),
      );
      expect(
        host.notifications,
        contains(contains(':minecraft:stone')),
        reason: 'the destination block change is notified',
      );
    });

    test('moves a hanging entity whose support block moved', () {
      host.states[(5, 64, 5)] = const BState('minecraft:stone');
      final entity = FakeAssemblyEntity(
        Vector3d(5.5, 64.5, 5.5),
        BoundingBox3i.values(5, 64, 5, 5, 64, 5),
      );
      host.entities.add(entity);

      SubLevelAssemblyHelper.assembleBlocks(
        level,
        (5, 64, 5),
        [(5, 64, 5)],
        BoundingBox3i.values(4, 63, 4, 6, 65, 6),
      );

      // The entity moved with the block (the plot centre is far away).
      expect(entity.position.x, isNot(closeTo(5.5, 1e-6)));
    });

    test('calls the assembly listener', () {
      host.states[(5, 64, 5)] = const BState('minecraft:stone');
      final listener = _RecordingListener();
      SubLevelAssemblyHelper.registerListener('minecraft:stone', listener);
      addTearDown(() => SubLevelAssemblyHelper.unregisterListener('minecraft:stone'));

      SubLevelAssemblyHelper.assembleBlocks(
        level,
        (5, 64, 5),
        [(5, 64, 5)],
        BoundingBox3i.values(4, 63, 4, 6, 65, 6),
      );

      expect(listener.before, hasLength(1));
      expect(listener.after, hasLength(1));
      expect(listener.before.single.$1, (5, 64, 5));
    });
  });
}

final class _RecordingListener implements BlockSubLevelAssemblyListener {
  final List<((int, int, int), (int, int, int))> before = [];
  final List<((int, int, int), (int, int, int))> after = [];

  @override
  void beforeMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    (int, int, int) oldPos,
    (int, int, int) newPos,
  ) => before.add((oldPos, newPos));

  @override
  void afterMove(
    SableLevel originLevel,
    SableLevel resultingLevel,
    BState newState,
    (int, int, int) oldPos,
    (int, int, int) newPos,
  ) => after.add((oldPos, newPos));
}
