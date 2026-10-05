/// The omnitool's right click, independent of the host: which block
/// transformers it tries and in what order.
library;

/// The block transformers of the game (`minecraft:block_transformer` registry
/// entries) that the omnitool applies.
abstract final class Transformers {
  static const axe = 'minecraft:axe';
  static const hoe = 'minecraft:hoe';
  static const shovel = 'minecraft:shovel';
}

/// Applies a block transformer to the block that was clicked, with the damage,
/// sound and particles the dedicated tool would have. Implemented by the host
/// adapter.
abstract interface class BlockTransformerPort {
  /// Tries [transformer] and returns whether it changed the block.
  bool apply(String transformer);
}

/// The order the omnitool tries transformers in: the axe first, then the hoe
/// and the shovel, swapped while sneaking (on dirt both apply, so sneaking
/// makes a path instead of farmland).
List<String> omnitoolOrder({required bool sneaking}) => [
  Transformers.axe,
  if (sneaking) Transformers.shovel else Transformers.hoe,
  if (sneaking) Transformers.hoe else Transformers.shovel,
];

/// Runs the omnitool's `useOn`: returns the transformer that applied, or
/// `null` if none did and the click should go on as usual.
String? useOmnitool(BlockTransformerPort port, {required bool sneaking}) {
  for (final transformer in omnitoolOrder(sneaking: sneaking)) {
    if (port.apply(transformer)) return transformer;
  }
  return null;
}
