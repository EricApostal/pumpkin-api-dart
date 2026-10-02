import 'bindings.g.dart';
import 'registry.dart';

/// Custom world generation, run for every new chunk in four phases. Override
/// the phases you need and attach the generator with [WorldGeneration.setGenerator].
///
/// Coordinates passed to the [ChunkBuffer] are local to the chunk: `0..15` for
/// x and z.
abstract class ChunkGenerator {
  /// Step 1: assign biomes across the chunk column.
  void generateBiomes(ChunkBuffer chunk) {}

  /// Step 2: generate the basic terrain shape.
  void generateNoise(ChunkBuffer chunk) {}

  /// Step 3: apply surface rules, like grass, sand and stone layers.
  void generateSurface(ChunkBuffer chunk) {}

  /// Step 4: populate with features, structures, decorations and ores.
  void generateFeatures(ChunkBuffer chunk) {}
}

final chunkGenerators = HandlerRegistry<ChunkGenerator>();

/// Registers [generator] and returns its id, for use with
/// `World.setChunkGenerator`.
int registerChunkGenerator(ChunkGenerator generator) =>
    chunkGenerators.add(generator);

extension WorldGeneration on World {
  /// Generates new chunks of this world with [generator].
  void setGenerator(ChunkGenerator generator) {
    setChunkGenerator(generatorId: registerChunkGenerator(generator));
  }
}

/// Shortcuts for [ChunkBuffer]. Its position and size (`x`, `z`, `minY`,
/// `height`) are properties of the buffer itself.
extension ChunkBufferApi on ChunkBuffer {
  /// Sets the block state at chunk-local `(x, y, z)`.
  void setBlock(int x, int y, int z, int stateId) =>
      setBlockStateId(x: x, y: y, z: z, stateId: stateId);

  /// The block state at chunk-local `(x, y, z)`.
  int getBlock(int x, int y, int z) => getBlockStateId(x: x, y: y, z: z);
}
