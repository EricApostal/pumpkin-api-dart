// The interfaces of Create's schematic requirement API (pure): the Java names modules implement
// instead of filling the registries (`SpecialBlockItemRequirement`,
// `SpecialBlockEntityItemRequirement`, `SpecialEntityItemRequirement`). The registries themselves
// are [SchematicRequirements] in the schematics module.
import '../../schematics/item_requirement.dart';
import '../block_state.dart';

/// `SpecialBlockItemRequirement`: a block's own placement requirement. [nbt] is the block entity
/// data (binary NBT) or `null`.
abstract interface class SpecialBlockItemRequirement {
  ItemRequirement getRequiredItems(BState state, List<int>? nbt);
}

/// `SpecialBlockEntityItemRequirement`: extra items the block entity needs, added to the block's
/// requirement.
abstract interface class SpecialBlockEntityItemRequirement {
  ItemRequirement getRequiredItems(BState state);
}

/// `SpecialEntityItemRequirement`: the requirement of an entity.
abstract interface class SpecialEntityItemRequirement {
  ItemRequirement getRequiredItems();
}

/// `SchematicRequirementRegistries`: the registries modules fill instead of implementing the
/// interfaces above. They are the maps of the schematics module's [SchematicRequirements]
/// service (`ctx.services.require<SchematicHooks>().requirements`).
final class SchematicRequirementRegistries {
  /// `BLOCKS`.
  final Map<String, BlockRequirement> blocks;

  /// `BLOCK_ENTITIES`.
  final Map<String, BlockEntityRequirement> blockEntities;

  /// `ENTITIES`.
  final Map<String, EntityRequirement> entities;

  /// A fresh set of registries (for tests).
  SchematicRequirementRegistries({
    Map<String, BlockRequirement>? blocks,
    Map<String, BlockEntityRequirement>? blockEntities,
    Map<String, EntityRequirement>? entities,
  }) : blocks = blocks ?? {},
       blockEntities = blockEntities ?? {},
       entities = entities ?? {};

  /// The registries behind [requirements].
  factory SchematicRequirementRegistries.of(
    SchematicRequirements requirements,
  ) => SchematicRequirementRegistries(
    blocks: requirements.blocks,
    blockEntities: requirements.blockEntities,
    entities: requirements.entities,
  );

  /// `BLOCKS.register(block, requirement)`.
  void registerBlock(String blockKey, BlockRequirement requirement) =>
      blocks[blockKey] = requirement;

  /// `BLOCK_ENTITIES.register(type, requirement)`.
  void registerBlockEntity(
    String blockEntityTypeKey,
    BlockEntityRequirement requirement,
  ) => blockEntities[blockEntityTypeKey] = requirement;

  /// `ENTITIES.register(type, requirement)`.
  void registerEntity(String entityTypeKey, EntityRequirement requirement) =>
      entities[entityTypeKey] = requirement;
}
