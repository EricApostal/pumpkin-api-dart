// The outline of the cart assembler (`AllShapes.CART_ASSEMBLER`), the collision shape it gives a
// player (`AllShapes.CART_ASSEMBLER_PLAYER_COLLISION`) and the shape rules that pick the outline
// from the rail axis.
//
// Java: `CartAssemblerBlock.getShape` returns `AllShapes.CART_ASSEMBLER.get(getRailAxis(state))`.
// The shaper is built with `VoxelShaper.forHorizontalAxis`, which authors the shape for a
// north-south rail and rotates it a quarter turn for an east-west one. Boxes are in block units,
// the comments give the `Block.box` arguments in 1/16 of a block.
import 'package:pumpkin_api/pumpkin_api_core.dart' show BlockBox, BlockShape, ShapeRule;

/// `AllShapes.CART_ASSEMBLER` for a north-south rail (the authored shape): the plate on top and
/// the frame below it, which overhangs the block by 2/16 on both sides across the track.
const List<BlockBox> cartAssemblerShapeNorthSouth = [
  // shape(0, 12, 0, 16, 16, 16)
  BlockBox(0, 0.75, 0, 1, 1, 1),
  // add(-2, 0, 1, 18, 14, 15)
  BlockBox(-0.125, 0, 0.0625, 1.125, 0.875, 0.9375),
];

/// `AllShapes.CART_ASSEMBLER` for an east-west rail: the authored shape turned a quarter turn, so
/// the frame overhangs along z instead of x.
const List<BlockBox> cartAssemblerShapeEastWest = [
  BlockBox(0, 0.75, 0, 1, 1, 1),
  // the quarter turn of add(-2, 0, 1, 18, 14, 15)
  BlockBox(0.0625, 0, -0.125, 0.9375, 0.875, 1.125),
];

/// `CartAssemblerBlock.getShape` as shape rules, one per rail axis.
List<ShapeRule> cartAssemblerShapeRules() => [
  ShapeRule(
    when: const {'shape': 'north_south'},
    selectionShape: BlockShape.boxes(cartAssemblerShapeNorthSouth),
  ),
  ShapeRule(
    when: const {'shape': 'east_west'},
    selectionShape: BlockShape.boxes(cartAssemblerShapeEastWest),
  ),
];

/// `AllShapes.CART_ASSEMBLER_PLAYER_COLLISION` for a north-south rail: the full block with 1/16
/// cut off both faces across the track, so a player still stands on the assembler.
const List<BlockBox> cartAssemblerPlayerCollisionNorthSouth = [
  // shape(0, 0, 1, 16, 16, 15)
  BlockBox(0, 0, 0.0625, 1, 1, 0.9375),
];

/// `AllShapes.CART_ASSEMBLER_PLAYER_COLLISION` for an east-west rail: the same shape turned a
/// quarter turn.
const List<BlockBox> cartAssemblerPlayerCollisionEastWest = [
  BlockBox(0.0625, 0, 0, 0.9375, 1, 1),
];

/// What the cart assembler collides with (`CartAssemblerBlock.getCollisionShape`).
enum CartAssemblerCollider {
  /// An `AbstractMinecart`: `Shapes.empty()`, the cart rides through the block.
  minecart,

  /// A `Player`: [cartAssemblerPlayerCollisionNorthSouth] or its quarter turn.
  player,

  /// Every other entity: `Shapes.block()`.
  other,
}

/// The entity types of `AbstractMinecart` (the host sends the entity type key as
/// `minecraft:<resource name>`).
const Set<String> minecartEntityTypes = {
  'minecraft:minecart',
  'minecraft:chest_minecart',
  'minecraft:furnace_minecart',
  'minecraft:hopper_minecart',
  'minecraft:tnt_minecart',
  'minecraft:command_block_minecart',
  'minecraft:spawner_minecart',
};

/// `entity instanceof AbstractMinecart`, `entity instanceof Player` and everything else, for an
/// entity type key from the host.
CartAssemblerCollider cartAssemblerColliderFor(String entityType) {
  if (minecartEntityTypes.contains(entityType)) {
    return CartAssemblerCollider.minecart;
  }
  if (entityType == 'minecraft:player') return CartAssemblerCollider.player;
  return CartAssemblerCollider.other;
}

/// `CartAssemblerBlock.getCollisionShape` for the entity type key the host sends
/// (`minecraft:minecart`) on a rail with [railShape]: the answer of `onEntityCollisionShape`.
List<BlockBox> cartAssemblerCollisionForEntity(
  String? railShape,
  String entityType,
) => cartAssemblerCollisionBoxes(
  railShape,
  cartAssemblerColliderFor(entityType),
);

/// `CartAssemblerBlock.getCollisionShape` for [collider] on a rail with [railShape]
/// (`north_south` / `east_west`). A minecart gets no boxes; the block's registered full cube is
/// what [CartAssemblerCollider.other] means. Like `getRailAxis`, anything but `north_south` is
/// the east-west shape.
List<BlockBox> cartAssemblerCollisionBoxes(
  String? railShape,
  CartAssemblerCollider collider,
) => switch (collider) {
  CartAssemblerCollider.minecart => const [],
  CartAssemblerCollider.player =>
    railShape == 'north_south'
        ? cartAssemblerPlayerCollisionNorthSouth
        : cartAssemblerPlayerCollisionEastWest,
  CartAssemblerCollider.other => const [BlockBox.unit],
};
