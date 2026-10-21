// `SingleBlockEntityEdgePoint` (pure): an edge point that is attached to exactly one block entity.
import '../../common/pos.dart';
import '../graph/dimension_palette.dart';
import '../util/ctag.dart';
import 'track_edge_point.dart';

abstract class SingleBlockEntityEdgePoint extends TrackEdgePoint {
  /// The dimension key of the block entity's level (`getLevel().dimension()`,
  /// `minecraft:overworld`), the value the graph packet and the saved data carry. It is *not* the
  /// block entity's world id (`World.getId()`, the folder name `world`).
  String blockEntityDimension = overworldId;

  /// `null` until a block entity attached.
  Pos? blockEntityPos;

  Pos? getBlockEntityPos() => blockEntityPos;

  String getBlockEntityDimension() => blockEntityDimension;

  @override
  void blockEntityAdded(Object blockEntity, bool front) {
    final info = EdgePointHooks.describe(blockEntity);
    blockEntityPos = info.pos;
    blockEntityDimension = info.dimension;
  }

  @override
  void blockEntityRemoved(Pos blockEntityPos, bool front) {
    removeFromAllGraphs();
  }

  @override
  void invalidate(Object? level) {
    final pos = blockEntityPos;
    if (pos != null) invalidateAt(level, blockEntityDimension, pos);
  }

  @override
  bool canMerge() => false;

  @override
  void read(CTag nbt, bool migration, DimensionPalette dimensions) {
    super.read(nbt, migration, dimensions);
    if (migration) return;
    blockEntityPos = nbt.getBlockPos('BlockEntityPos');
    blockEntityDimension = dimensions.decode(nbt.contains('BlockEntityDimension') ? nbt.getInt('BlockEntityDimension') : -1);
  }

  @override
  void write(CTag nbt, DimensionPalette dimensions) {
    super.write(nbt, dimensions);
    nbt.putBlockPos('BlockEntityPos', blockEntityPos ?? posZero);
    nbt.putInt('BlockEntityDimension', dimensions.encode(blockEntityDimension));
  }
}
