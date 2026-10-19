// `TransformableBlock` / `TransformableBlockEntity` and the registries of the contraption
// transform API (pure). The registries themselves live in the contraptions module
// (`contraptions/core/structure_transform.dart`); this file is the public entry point and adds the
// Java interface names.
import '../../contraptions/core/nbt_map.dart';
import '../../contraptions/core/structure_transform.dart';
import '../block_state.dart';

export '../../contraptions/core/structure_transform.dart'
    show
        BlockEntityTransformer,
        BlockTransformer,
        MovedBlockTransformers,
        StructureTransform;

/// `TransformableBlock`: a block that transforms its state when a contraption moves it.
abstract interface class TransformableBlock {
  BState transform(BState state, StructureTransform transform);
}

/// `TransformableBlockEntity`: a block entity that transforms its saved data when a contraption
/// moves it. The port hands the saved NBT rather than the block entity object.
abstract interface class TransformableBlockEntity {
  void transform(NbtMap nbt, StructureTransform transform);
}

/// `MovedBlockTransformerRegistries`: the registries behind [TransformableBlock] /
/// [TransformableBlockEntity], keyed by block key and block entity type key.
abstract final class MovedBlockTransformerRegistries {
  /// `BLOCK_TRANSFORMERS`.
  static Map<String, BlockTransformer> get blocks =>
      MovedBlockTransformers.blocks;

  /// `BLOCK_ENTITY_TRANSFORMERS`.
  static Map<String, BlockEntityTransformer> get blockEntities =>
      MovedBlockTransformers.blockEntities;

  /// Registers a block transformer.
  static void registerBlock(String blockKey, BlockTransformer transformer) =>
      MovedBlockTransformers.blocks[blockKey] = transformer;

  /// Registers a block entity transformer.
  static void registerBlockEntity(
    String blockEntityTypeKey,
    BlockEntityTransformer transformer,
  ) => MovedBlockTransformers.blockEntities[blockEntityTypeKey] = transformer;

  /// Removes every registration (tests and reloads).
  static void clear() {
    MovedBlockTransformers.blocks.clear();
    MovedBlockTransformers.blockEntities.clear();
  }
}
