// `dev.ryanhcode.sable.sublevel.plot.PlotChunkHolder`: a chunk that lives inside
// a `LevelPlot`, plus the local bounding box of its non-air blocks.
//
// The Java class extends `ChunkHolder` (it *is* the holder the chunk map knows
// about). The port keeps the part that matters to the model — the chunk, its
// position and its block bounds — and leaves the chunk-map plumbing to the
// host (`host/sub_level_host.dart`).
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../host/sub_level_host.dart';
import '../plot/heat/heat_data_chunk_section.dart';

/// A chunk holder for chunks that live inside a `LevelPlot`.
final class PlotChunkHolder {
  /// The chunk itself.
  final PlotChunk chunk;

  /// The global chunk position.
  final (int, int) pos;

  BoundingBox3i? _boundingBox;

  /// The splitting heat map of each section, by section y
  /// (`PlotChunkHolder.getHeatSection`).
  final Map<int, HeatDataChunkSection> heatSections = {};

  /// Wraps [chunk]; builds the bounding box when the chunk is not empty.
  PlotChunkHolder(this.chunk, this.pos) {
    if (!chunk.hasOnlyAir) buildBoundingBox();
  }

  /// `PlotChunkHolder.create(level, pos, lightEngine, chunk)`.
  static PlotChunkHolder create(PlotChunk chunk, (int, int) pos) => PlotChunkHolder(chunk, pos);

  /// The global chunk position.
  (int, int) get chunkPos => pos;

  /// The chunk.
  PlotChunk get levelChunk => chunk;

  /// `ChunkHolder.getPos()`.
  (int, int) getPos() => pos;

  /// `ChunkHolder.getChunk()`.
  PlotChunk getChunk() => chunk;

  /// The local bounding box of the non-air blocks, or `null` for an empty chunk.
  BoundingBox3i? getBoundingBox() => _boundingBox;

  /// Rebuilds the bounding box by scanning every block of every non-empty
  /// section (the Java `buildBoundingBox`; a TODO there too).
  void buildBoundingBox() {
    _boundingBox = null;
    for (var i = 0; i < chunk.sectionsCount; i++) {
      if (chunk.sectionHasOnlyAir(i)) continue;
      final sectionMinY = chunk.sectionMinY(i);
      for (var x = 0; x < 16; x++) {
        for (var y = 0; y < 16; y++) {
          for (var z = 0; z < 16; z++) {
            if (chunk.blockAt(x, y + sectionMinY, z) == 'minecraft:air') continue;
            final box = _boundingBox;
            if (box == null) {
              _boundingBox = BoundingBox3i.values(x, y + sectionMinY, z, x, y + sectionMinY, z);
            } else {
              box.expandToValues(x, y + sectionMinY, z);
            }
          }
        }
      }
    }
  }

  /// `handleBlockChange`: grows the box for a placed block, rebuilds it for a
  /// removed block on the boundary.
  void handleBlockChange(int x, int y, int z, String oldBlock, String newBlock) {
    final wasAir = oldBlock == 'minecraft:air';
    final isAir = newBlock == 'minecraft:air';

    if (wasAir && !isAir) {
      final box = _boundingBox;
      if (box == null) {
        _boundingBox = BoundingBox3i.values(x, y, z, x, y, z);
      } else {
        box.expandToValues(x, y, z);
      }
    } else if (!wasAir && isAir) {
      final box = _boundingBox;
      if (box != null &&
          (box.minX == x ||
              box.maxX == x ||
              box.minY == y ||
              box.maxY == y ||
              box.minZ == z ||
              box.maxZ == z)) {
        buildBoundingBox();
      }
    }
  }

  /// The heat map of the section at [sectionY], or `null` when the section has
  /// none yet.
  HeatDataChunkSection? getHeatSection(int sectionY) => heatSections[sectionY];

  /// Sets the heat map of the section at [sectionY].
  void setHeatSection(int sectionY, HeatDataChunkSection section) =>
      heatSections[sectionY] = section;

  @override
  String toString() => 'PlotChunkHolder[${pos.$1}, ${pos.$2}, bounds=$_boundingBox]';
}
