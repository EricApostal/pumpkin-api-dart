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
