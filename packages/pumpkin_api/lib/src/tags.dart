import 'bindings.g.dart' as generated;

/// Tag membership queries (`world.wit`). `tag` is a name like
/// `minecraft:logs` or `create:wrenches`; the `#` prefix and the `minecraft:`
/// namespace are optional. They see vanilla tags, datapack tags and the tags
/// plugins registered. Unknown keys and tags are not in the tag (`false`).
///
/// ```dart
/// if (Tags.block('oak_log', 'logs')) { /* ... */ }
/// ```
abstract final class Tags {
  /// Whether the block [blockKey] is in [tag].
  static bool block(String blockKey, String tag) =>
      generated.world.blockHasTag(blockKey: blockKey, tag: tag);

  /// Whether the block of the state [stateId] is in [tag].
  static bool blockState(int stateId, String tag) =>
      generated.world.blockStateHasTag(stateId: stateId, tag: tag);

  /// Whether the item [itemKey] is in [tag].
  static bool item(String itemKey, String tag) =>
      generated.world.itemHasTag(itemKey: itemKey, tag: tag);

  /// Whether the fluid [fluidKey] is in [tag].
  static bool fluid(String fluidKey, String tag) =>
      generated.world.fluidHasTag(fluidKey: fluidKey, tag: tag);

  /// Whether the entity type [entityTypeKey] is in [tag].
  static bool entityType(String entityTypeKey, String tag) =>
      generated.world.entityTypeHasTag(entityTypeKey: entityTypeKey, tag: tag);
}
