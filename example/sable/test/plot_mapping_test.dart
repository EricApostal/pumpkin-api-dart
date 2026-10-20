// The plot yard: plot/chunk coordinate mapping, the distant origin, occupancy
// and sub-level allocation. All of it is pure, so this runs on the VM.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeLevel level;
  late FakeChunkHost chunks;
  late TestContainer container;

  setUp(() {
    level = FakeLevel();
    chunks = FakeChunkHost(level);
    container = TestContainer(level, chunks, 3, 4);
    SubLevelContainer.register(container);
  });

  tearDown(() => SubLevelContainer.unregister(level));

  group('plot coordinates', () {
    test('the plot yard starts at the distant origin', () {
      expect(SubLevelContainer.defaultOrigin, 10000);
      expect(SubLevelContainer.defaultLogPlotSize, 7);
      expect(SubLevelContainer.defaultLogSizeLength, 7);
    });

    test('local and global chunk positions round trip', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();

      expect(plot.plotPos, (10000, 10000));
      expect(plot.toGlobal((0, 0)), (10000 << 4, 10000 << 4));
      expect(plot.toGlobal((3, 5)), ((10000 << 4) + 3, (10000 << 4) + 5));
      expect(plot.toLocal(plot.toGlobal((7, 9))), (7, 9));
    });

    test('chunk min/max and center of a plot', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();

      expect(plot.getChunkMin(), (10000 << 4, 10000 << 4));
      expect(plot.getChunkMax(), ((10001 << 4) - 1, (10001 << 4) - 1));
      expect(plot.getCenterChunk(), ((10000 << 4) + 8, (10000 << 4) + 8));
      expect(plot.getCenterBlock(), ((10000 << 4) + 8) * 16 + 8);
    });

    test('contains uses block coordinates of the plot', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();

      final minBlock = 10000 << (4 + 4);
      expect(plot.contains(minBlock.toDouble(), minBlock.toDouble()), isTrue);
      expect(plot.contains((minBlock + 255).toDouble(), (minBlock + 255).toDouble()), isTrue);
      expect(plot.contains((minBlock - 1).toDouble(), minBlock.toDouble()), isFalse);
      expect(plot.contains((minBlock + 256).toDouble(), minBlock.toDouble()), isFalse);
    });

    test('local chunk indices are z << logSize | x', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();
      expect(plot.indexOf((0, 0)), 0);
      expect(plot.indexOf((1, 0)), 1);
      expect(plot.indexOf((0, 1)), 16);
      expect(plot.indexOf((3, 2)), 35);
      expect(plot.hasLocal((15, 15)), isTrue);
      expect(plot.hasLocal((16, 0)), isFalse);
      expect(plot.getChunkHolder((-1, 0)), isNull);
    });
  });

  group('container bounds', () {
    test('accepts chunks inside the yard and rejects outside', () {
      final originChunk = 10000 << 4;
      expect(container.inBounds(originChunk, originChunk), isTrue);
      expect(container.inBounds(originChunk + 8 * 16 - 1, originChunk + 8 * 16 - 1), isTrue);
      expect(container.inBounds(originChunk - 1, originChunk), isFalse);
      expect(container.inBounds(originChunk + 8 * 16, originChunk), isFalse);
      expect(container.inBoundsBlock((originChunk << 4, 0, originChunk << 4)), isTrue);
    });

    test('getPlot maps a global chunk to its plot', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();
      final global = plot.toGlobal((2, 3));
      expect(container.getPlot(global.$1, global.$2), same(plot));
      expect(container.getPlot(global.$1 + 1, global.$2), same(plot));
      expect(container.getPlotAt(global), same(plot));
      expect(container.getPlot(0, 0), isNull);
    });
  });

  group('allocation', () {
    test('allocates the first empty plot and marks occupancy', () {
      final first = container.allocateNewSubLevel(Pose3d());
      expect(first.getPlot().plotPos, (10000, 10000));
      expect(container.getIndex(0, 0), 0);
      expect(container.getOccupancy().get(0), isTrue);
      expect(container.getLoadedCount(), 1);

      final second = container.allocateNewSubLevel(Pose3d());
      expect(second.getPlot().plotPos, (10001, 10000));
      expect(container.getIndex(1, 0), 1);
    });

    test('a plot cannot be allocated twice', () {
      container.allocateNewSubLevel(Pose3d());
      expect(() => container.allocateSubLevel('u', 0, 0, Pose3d()), throwsArgumentError);
      expect(() => container.allocateSubLevel('u', -1, 0, Pose3d()), throwsArgumentError);
    });

    test('lookup by uuid and by local coordinate', () {
      final subLevel = container.allocateSubLevel('00000000-0000-4000-8000-000000000001', 2, 3, Pose3d());
      expect(container.getSubLevel(2, 3), same(subLevel));
      expect(container.getSubLevelById('00000000-0000-4000-8000-000000000001'), same(subLevel));
      expect(container.getSubLevel(0, 0), isNull);
      expect(container.getSubLevel(99, 0), isNull);
    });

    test('removal clears occupancy only for REMOVED', () {
      final subLevel = container.allocateSubLevel('a', 0, 0, Pose3d());
      container.removeSubLevel(0, 0, SubLevelRemovalReason.unloaded);
      expect(container.getOccupancy().get(container.getIndex(0, 0)), isTrue);
      expect(container.getLoadedCount(), 0);

      final other = container.allocateSubLevel('b', 0, 0, Pose3d());
      expect(other, isNot(same(subLevel)));
      container.removeSubLevel(0, 0, SubLevelRemovalReason.removed);
      expect(container.getOccupancy().get(container.getIndex(0, 0)), isFalse);
    });

    test('observers see add, remove and tick', () {
      final observer = _RecordingObserver();
      container.addObserver(observer);

      final subLevel = container.allocateNewSubLevel(Pose3d());
      expect(observer.added, [subLevel]);

      container.tick();
      expect(observer.ticks, 1);

      container.removeSubLevelAt(subLevel, SubLevelRemovalReason.removed);
      expect(observer.removed, [(subLevel, SubLevelRemovalReason.removed)]);
    });
  });

  group('plot chunks and bounds', () {
    test('a chunk holder builds its local bounds and the plot unions them', () {
      final subLevel = container.allocateNewSubLevel(Pose3d()) as TestSubLevel;
      final plot = subLevel.getPlot();
      final global = plot.toGlobal((0, 0));

      final chunk = FakeChunk(global, {(2, 3, 4): 'minecraft:stone', (5, 1, 6): 'minecraft:dirt'});
      plot.newChunk(global, chunk, false);

      final holder = plot.getChunkHolder((0, 0))!;
      expect(holder.getBoundingBox()!.minX, 2);
      expect(holder.getBoundingBox()!.maxX, 5);
      expect(holder.getBoundingBox()!.minY, 1);
      expect(holder.getBoundingBox()!.maxY, 3);
      expect(holder.getBoundingBox()!.minZ, 4);
      expect(holder.getBoundingBox()!.maxZ, 6);

      // The plot bounds are in global yard coordinates.
      final bounds = plot.getBoundingBox();
      expect(bounds.minX, (global.$1 << 4) + 2);
      expect(bounds.maxX, (global.$1 << 4) + 5);
      expect(bounds.minZ, (global.$2 << 4) + 4);
      expect(bounds.maxZ, (global.$2 << 4) + 6);
      expect(subLevel.boundsChanges, 1);
    });

    test('block changes grow and shrink the chunk bounds', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();
      final global = plot.toGlobal((0, 0));
      final chunk = FakeChunk(global, {(1, 1, 1): 'minecraft:stone'});
      plot.newChunk(global, chunk, false);

      final holder = plot.getChunkHolder((0, 0))!;
      holder.handleBlockChange(4, 4, 4, 'minecraft:air', 'minecraft:stone');
      expect(holder.getBoundingBox()!.maxX, 4);

      holder.handleBlockChange(4, 4, 4, 'minecraft:stone', 'minecraft:air');
      expect(holder.getBoundingBox()!.maxX, 1);
    });

    test('global bounds follow the pose', () {
      final subLevel = container.allocateNewSubLevel(Pose3d());
      final plot = subLevel.getPlot();
      final global = plot.toGlobal((0, 0));
      plot.newChunk(global, FakeChunk(global, {(0, 0, 0): 'minecraft:stone', (1, 1, 1): 'minecraft:stone'}), false);

      subLevel.updateBoundingBox();
      expect(subLevel.boundingBox.minX, (global.$1 << 4).toDouble());
      expect(subLevel.boundingBox.maxX, (global.$1 << 4) + 2.0);

      subLevel.pose.position().set(100, 50, -25);
      subLevel.updateBoundingBox();
      expect(subLevel.boundingBox.minX, (global.$1 << 4) + 100.0);
      expect(subLevel.boundingBox.minY, 50.0);
      expect(subLevel.boundingBox.minZ, (global.$2 << 4) - 25.0);
    });

    test('queryIntersecting filters by the global bounds', () {
      final near = container.allocateNewSubLevel(Pose3d());
      final far = container.allocateNewSubLevel(Pose3d());
      near.updateBoundingBox();
      far.updateBoundingBox();

      final query = BoundingBox3d.full(
        near.boundingBox.minX - 1,
        near.boundingBox.minY - 1,
        near.boundingBox.minZ - 1,
        near.boundingBox.maxX + 1,
        near.boundingBox.maxY + 1,
        near.boundingBox.maxZ + 1,
      );
      expect(container.queryIntersecting(query), contains(near));
    });
  });
}

final class _RecordingObserver with SubLevelObserver {
  final List<SubLevel> added = [];
  final List<(SubLevel, SubLevelRemovalReason)> removed = [];
  int ticks = 0;

  @override
  void onSubLevelAdded(SubLevel subLevel) => added.add(subLevel);

  @override
  void onSubLevelRemoved(SubLevel subLevel, SubLevelRemovalReason reason) =>
      removed.add((subLevel, reason));

  @override
  void tick(SubLevelContainer subLevels) => ticks++;
}
