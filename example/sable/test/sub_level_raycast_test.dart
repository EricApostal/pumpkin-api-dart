// The block ray the `/sable` selector's `@v` walks over the plot chunks: pure,
// so it runs on the VM (Java: `Entity.pick` over a sub-level's blocks).
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeLevel level;
  late FakeChunkHost host;
  late ServerSubLevelContainer container;

  setUp(() {
    level = FakeLevel();
    host = FakeChunkHost(level);
    container = ServerSubLevelContainer(
      level,
      host,
      3,
      4,
      SubLevelContainer.defaultOrigin,
      SubLevelContainer.defaultOrigin,
    );
    SubLevelContainer.register(container);
  });

  tearDown(() => SubLevelContainer.unregister(level));

  ServerSubLevel spawn(String name) {
    final subLevel =
        container.allocateNewSubLevel(Pose3d()) as ServerSubLevel;
    subLevel.setName(name);
    return subLevel;
  }

  /// A sub-level with one stone block at the centre of its plot.
  (ServerSubLevel, (int, int, int)) spawnWithStone(String name) {
    final subLevel = spawn(name);
    final plot = subLevel.getPlot();
    final center = plot.getCenterBlock();
    final chunkPos = (center.$1 >> 4, center.$3 >> 4);
    plot.newEmptyChunk(chunkPos);
    final chunk = plot.getChunk(plot.toLocal(chunkPos))! as FakeChunk;
    chunk.blocks[(center.$1 & 15, center.$2, center.$3 & 15)] = 'minecraft:stone';
    return (subLevel, center);
  }

  group('lookVector', () {
    test('yaw 0 and pitch 0 look along +z', () {
      final look = SubLevelRaycast.lookVector(0, 0);
      expect(look.x, closeTo(0, 1e-12));
      expect(look.y, closeTo(0, 1e-12));
      expect(look.z, closeTo(1, 1e-12));
    });

    test('pitch 90 looks straight down', () {
      final look = SubLevelRaycast.lookVector(0, 90);
      expect(look.x, closeTo(0, 1e-12));
      expect(look.y, closeTo(-1, 1e-12));
      expect(look.z, closeTo(0, 1e-12));
    });

    test('is a unit vector at an angle', () {
      final look = SubLevelRaycast.lookVector(37, -21);
      expect(look.length, closeTo(1, 1e-12));
    });
  });

  group('pick', () {
    test('finds the block the ray meets, and the sub-level holding it', () {
      final (subLevel, center) = spawnWithStone('ship');

      final hit = SubLevelRaycast.pick(
        container,
        Vector3d(center.$1 + 0.5, center.$2 + 4.0, center.$3 + 0.5),
        SubLevelRaycast.lookVector(0, 90),
        10,
      );

      expect(hit, isNotNull);
      expect(hit!.subLevel.uniqueId, subLevel.uniqueId);
      expect(hit.blockPos, center);
      expect(hit.distance, closeTo(3.5, 0.5));
    });

    test('skips air, and reports nothing past the distance', () {
      final (_, center) = spawnWithStone('ship');

      final above = Vector3d(center.$1 + 0.5, center.$2 + 4.0, center.$3 + 0.5);
      expect(
        SubLevelRaycast.pick(container, above, SubLevelRaycast.lookVector(0, 90), 2),
        isNull,
      );
      expect(
        SubLevelRaycast.pick(container, above, SubLevelRaycast.lookVector(0, -90), 100),
        isNull,
      );
    });

    test('ignores a plot whose chunks were never loaded', () {
      final subLevel = spawn('empty');
      final center = subLevel.getPlot().getCenterBlock();

      expect(
        SubLevelRaycast.pick(
          container,
          Vector3d(center.$1 + 0.5, center.$2 + 4.0, center.$3 + 0.5),
          SubLevelRaycast.lookVector(0, 90),
          10,
        ),
        isNull,
      );
    });

    test('reports nothing for a ray outside every plot', () {
      spawnWithStone('ship');

      expect(
        SubLevelRaycast.pick(
          container,
          Vector3d(0.5, 100.0, 0.5),
          SubLevelRaycast.lookVector(0, 90),
          100,
        ),
        isNull,
      );
    });

    test('a zero direction or distance reports nothing', () {
      spawnWithStone('ship');
      final start = Vector3d(0.5, 100, 0.5);
      expect(SubLevelRaycast.pick(container, start, Vector3d(), 10), isNull);
      expect(
        SubLevelRaycast.pick(container, start, SubLevelRaycast.lookVector(0, 90), 0),
        isNull,
      );
    });
  });
}