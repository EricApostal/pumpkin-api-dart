// The minimum of the sub-level model a physics test needs: a level, a chunk
// host that is never asked anything, and a container, so a `ServerSubLevel` can
// be constructed. `example/sable/test/support.dart` has richer versions of the
// same doubles; they are not importable from another package.
//
// Pure: no host imports.
import 'package:sable/sable.dart';

/// A level with no chunks and no biome data.
final class TestLevel implements SableLevel {
  @override
  final String dimensionId;

  @override
  bool isClientSide = false;

  @override
  int minY = -64;

  @override
  int maxY = 320;

  @override
  int gameTime = 0;

  @override
  int get sectionsCount => (maxY - minY) >> 4;

  @override
  String? biomeAt(int x, int y, int z) => null;

  TestLevel([this.dimensionId = 'sable_jolt:test']);
}

/// A chunk host that refuses every call: the physics tests never load plots.
final class TestChunkHost implements PlotChunkHost {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('TestChunkHost.${invocation.memberName}');
}

/// A container that only exists so `SubLevelContainer.of(level)` succeeds.
final class TestContainer extends SubLevelContainer {
  TestContainer(SableLevel level, PlotChunkHost chunkHost)
    : super(
        level,
        chunkHost,
        SubLevelContainer.defaultLogSizeLength,
        SubLevelContainer.defaultLogPlotSize,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );

  @override
  SubLevel createSubLevel(int globalPlotX, int globalPlotZ, Pose3d pose, String uuid) =>
      throw UnsupportedError(
        'TestContainer.createSubLevel: physics tests construct ServerSubLevel '
        'directly.',
      );
}

/// A container that can allocate sub-levels, for the tests that need a section
/// to be resolved through the plot grid (`SubLevelContainer.getPlot`) rather
/// than through an explicit runtime id.
final class TestServerContainer extends SubLevelContainer {
  TestServerContainer(SableLevel level, PlotChunkHost chunkHost)
    : super(
        level,
        chunkHost,
        SubLevelContainer.defaultLogSizeLength,
        SubLevelContainer.defaultLogPlotSize,
        SubLevelContainer.defaultOrigin,
        SubLevelContainer.defaultOrigin,
      );

  /// The sub-levels handed out by [createSubLevel], in allocation order.
  final List<ServerSubLevel> allocated = [];

  @override
  SubLevel createSubLevel(int globalPlotX, int globalPlotZ, Pose3d pose, String uuid) {
    final subLevel = ServerSubLevel(
      level,
      globalPlotX,
      globalPlotZ,
      pose,
      runtimeId: 100 + allocated.length,
    );
    // `ServerSubLevelContainer.createSubLevel` applies the allocated uuid
    // (`server_sub_level_container.dart:176`); the container reads
    // `subLevel.uniqueId` straight after this returns.
    subLevel.setUniqueId(uuid);
    allocated.add(subLevel);
    return subLevel;
  }
}
