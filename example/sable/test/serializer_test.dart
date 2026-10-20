// Serialization: the tag layout of a sub-level, and a full save/load round trip
// through a server container.
import 'package:sable/sable.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeLevel level;
  late FakeChunkHost chunks;
  late ServerSubLevelContainer container;

  setUp(() {
    level = FakeLevel();
    chunks = FakeChunkHost(level);
    container = ServerSubLevelContainer(level, chunks, 3, 4, 10000, 10000);
    SubLevelContainer.register(container);
  });

  tearDown(() => SubLevelContainer.unregister(level));

  ServerSubLevel newSubLevel({String uuid = '00000000-0000-4000-8000-000000000001'}) {
    final pose = Pose3d()..position().set(100, 64, -50);
    final subLevel = container.allocateSubLevel(uuid, 0, 0, pose) as ServerSubLevel;
    final plot = subLevel.getPlot();
    final global = plot.toGlobal((0, 0));
    plot.newChunk(global, FakeChunk(global, {(0, 0, 0): 'minecraft:stone', (2, 1, 3): 'minecraft:oak_planks'}), false);
    subLevel.updateBoundingBox();
    return subLevel;
  }

  test('serialize writes the Java tag layout', () {
    final subLevel = newSubLevel();
    subLevel.setName('Boat');
    subLevel.setUserDataTag({'owner': 'steve'});

    final tag = SubLevelSerializer.serialize(subLevel, const []);
    expect(tag['uuid'], isA<List<int>>());
    expect(tag['plot'], isA<Map<String, Object?>>());
    expect(tag['pose'], isA<Map<String, Object?>>());
    expect(tag['world_bounds'], isA<Map<String, Object?>>());
    expect(tag['display_name'], 'Boat');
    expect(tag['user_data'], {'owner': 'steve'});
    expect(tag.containsKey('loading_dependencies'), isFalse);
  });

  test('the serialized pose is recentred on the centre of mass', () {
    final subLevel = newSubLevel();
    // No mass tracker (physics is W3), so the origin is the rotation point.
    final tag = SubLevelSerializer.serialize(subLevel, const []);
    final pose = SableNbt.readPose3d(tag['pose']);
    expect(pose.rotationPoint().x, 0);
    expect(pose.position().x, subLevel.logicalPose.position().x);
  });

  test('fromData reads identity, pose and dependencies', () {
    final subLevel = newSubLevel();
    final data = SubLevelSerializer.toData(subLevel, [
      subLevel.uniqueId,
      '00000000-0000-4000-8000-000000000002',
    ]);

    expect(data.uuid, subLevel.uniqueId);
    expect(data.relations, ['00000000-0000-4000-8000-000000000002']);
    expect(data.pose.position().x, 100);

    final parsed = SubLevelSerializer.fromData(data.fullTag)!;
    expect(parsed.uuid, subLevel.uniqueId);
    expect(parsed.bounds.minX, subLevel.boundingBox.minX);
    expect(parsed.pose.position().z, -50);
  });

  test('fullyLoad rebuilds the sub-level in another container', () {
    final subLevel = newSubLevel();
    subLevel.setName('Boat');
    subLevel.setUserDataTag({'owner': 'steve'});
    final data = SubLevelSerializer.toData(subLevel, const []);

    final otherLevel = FakeLevel();
    final otherChunks = FakeChunkHost(otherLevel);
    final other = ServerSubLevelContainer(otherLevel, otherChunks, 3, 4, 10000, 10000);
    SubLevelContainer.register(other);
    addTearDown(() => SubLevelContainer.unregister(otherLevel));

    final loaded = SubLevelSerializer.fullyLoad(other, data)!;
    expect(loaded.uniqueId, subLevel.uniqueId);
    expect(loaded.name, 'Boat');
    expect(loaded.getUserDataTag(), {'owner': 'steve'});
    expect(loaded.logicalPose.position().x, 100);
    expect(loaded.logicalPose.position().y, 64);
    expect(loaded.getPlot().getBoundingBox().minX, subLevel.getPlot().getBoundingBox().minX);
    expect(loaded.getPlot().getLoadedChunks().length, 1);
  });

  test('fullyLoad rejects a zero-area plot', () {
    final subLevel = newSubLevel();
    final data = SubLevelSerializer.toData(subLevel, const []);
    // Drop the chunks from the tag: the loaded plot has no bounds.
    (data.fullTag['plot'] as Map<String, Object?>)['chunks'] = <String, Object?>{};

    final otherLevel = FakeLevel();
    final other = ServerSubLevelContainer(otherLevel, FakeChunkHost(otherLevel), 3, 4, 10000, 10000);
    SubLevelContainer.register(other);
    addTearDown(() => SubLevelContainer.unregister(otherLevel));

    expect(SubLevelSerializer.fullyLoad(other, data), isNull);
    expect(other.getLoadedCount(), 0);
  });

  test('a sub-level without a UUID cannot be serialized as data', () {
    final subLevel = newSubLevel();
    final data = SubLevelSerializer.toData(subLevel, const []);
    expect(SubLevelSerializer.fromData({'plot': <String, Object?>{}}), isNull);
    expect(data.uuid, isNotEmpty);
  });
}
