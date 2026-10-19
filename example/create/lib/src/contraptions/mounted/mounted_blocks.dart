// `CartAssemblerBlock` and its `minecart_anchor` companion: the block definition, the rail type it
// stands in for, and the actions a passing cart and the wrench trigger.
//
// Java: `content/contraptions/mounted/{CartAssemblerBlock,CartAssemblerBlockItem}`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/wrenchable.dart';
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../core/blocks.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../core/level.dart';
import 'cart_assemble_rail_type.dart';
import 'cart_assembler_block_entity.dart';
import 'minecart_contraption_item.dart' show shrinkHeld;
import 'mounted_contraption.dart';
import 'mounted_shapes.dart';

/// The cart assembler and the anchor it becomes inside a contraption.
List<CreateBlock> buildMountedBlocks() => [
  manifestBlock(
    'cart_assembler',
    blockEntityType: 'create:cart_assembler',
    behavior: cartAssemblerBehavior(),
    // `CartAssemblerBlock.getShape` (the outline) follows the rail axis. Its `getCollisionShape`
    // is empty for a minecart, the player shape for a player and a full block for everything
    // else; the entity-dependent answer is `onEntityCollisionShape` in the behavior, the
    // registered collision stays the full cube.
    shapeRules: cartAssemblerShapeRules(),
  ),
  // `MinecartAnchorBlock.getShape` is `Shapes.empty()`: invisible. Its collision stays the
  // default full block of a stone block; the anchor only ever exists inside a contraption.
  manifestBlock('minecart_anchor', selectionShape: BlockShape.empty),
];

/// The cart assembler reacts to a cart passing through it: the entity is queued, the rail type
/// switches with an item, and the block only exists on a rail (the item places it).
BlockBehavior cartAssemblerBehavior() => BlockBehavior(
  // `getCollisionShape`: a minecart passes through the assembler, a player stands on the
  // player collision shape, every other entity collides with the full block. The registered
  // collision shape stays the full cube; this hook replaces it per entity.
  onEntityCollisionShape: (server, e) => cartAssemblerCollisionForEntity(
    HostBlockGetter.stateOfId(e.stateIndex)['shape'],
    e.entityType,
  ),
  onEntityCollision: (server, e) async {
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    final level = ActuatorHosts.levelOf(e.targetWorld.getId());
    if (level == null) return;
    final cart = _cartAt(level, pos, e.entityId);
    if (cart == null || !cart.canAssemble) return;
    final be = ActuatorRuntime.maybe?.store.at(e.targetWorld.getId(), e.pos);
    if (be is CartAssemblerBlockEntity) be.queueAssembly(cart);
  },
  // `neighborChanged`: follow the redstone signal.
  onNeighborUpdate: (server, e) async {
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    if (state.key != cartAssemblerKey) return;
    final powered = await e.targetWorld.hasNeighborSignal(pos: e.pos);
    if (state.flag('powered') == powered) return;
    await setBlockState(
      e.targetWorld,
      (e.pos.x, e.pos.y, e.pos.z),
      state.setFlag('powered', powered),
      flags: {BlockFlagsFlag.notifyListeners},
    );
  },
  // `useItemOn`: the held rail item becomes the assembler's rail type.
  onUseWithItem: (server, e) async {
    final state = HostBlockGetter.stateOfId(e.stateIndex);
    if (state.key != cartAssemblerKey) return BlockUseResult.pass;
    final current = CartAssembleRailType.byName(state['rail_type']);

    final String held;
    try {
      held = await e.item.getRegistryKey();
    } on Object {
      return BlockUseResult.pass;
    }
    if (held == current.blockKey) return BlockUseResult.pass;

    CartAssembleRailType? next;
    for (final type in CartAssembleRailType.values) {
      if (type.blockKey == held) next = type;
    }
    if (next == null) return BlockUseResult.pass;

    final world = e.targetWorld;
    final pos = (e.pos.x, e.pos.y, e.pos.z);
    world.playCustomSound(
      soundName: 'minecraft:entity.item.pickup',
      category: SoundCategory.players,
      pos: (pos.$1 + .5, pos.$2 + .5, pos.$3 + .5),
      volume: 1,
      pitch: 1,
    );
    await setBlockState(
      world,
      pos,
      state.setValue('rail_type', next.serializedName),
    );

    if (e.player.getGamemode() != GameMode.creative) {
      await shrinkHeld(e.player, e.hand, e.item);
      await e.player.give(
        ItemStack.create(registryKey: current.blockKey, count: 1),
      );
    }
    return BlockUseResult.success;
  },
  // `canSurvive` is false: the item replaces a rail, the block is never placed on its own.
  onCanPlace: (server, e) => false,
);

/// The cart at [pos] with [entityId], `null` when it is not loaded.
MinecartRef? _cartAt(ContraptionLevel level, Pos pos, int entityId) {
  for (final cart in level.minecartsAt(pos)) {
    if (cart.id == entityId) return cart;
  }
  return null;
}

/// `CartAssemblerBlockItem.tryPlaceAssembler`: placing the item on a straight rail replaces the
/// rail with the assembler, keeping the rail's type and shape.
Future<bool> useCartAssemblerItem(
  Server server,
  PlayerUseBlockEventData e,
) async {
  if (e.cancelled) return false;

  final String itemKey;
  try {
    itemKey = await e.item.getRegistryKey();
  } on Object {
    return false;
  }
  if (itemKey != cartAssemblerKey) return false;

  final world = e.player.getWorld();
  final pos = e.blockPos.toPos();
  final railState = HostBlockGetter(world).stateAt(pos);

  CartAssembleRailType? type;
  for (final t in CartAssembleRailType.values) {
    if (t.matches(railState)) type = t;
  }
  if (type == null) return false;

  final shape = railState['shape'];
  if (shape != 'east_west' && shape != 'north_south') return false;

  // `ControllerRailBlock.BACKWARDS` when the rail has it, else the player's motion direction.
  final backwards = railState.props.containsKey('backwards')
      ? railState.flag('backwards')
      : Direction.fromYRot(e.player.getYaw()).axisDirection ==
            AxisDirection.positive;

  // `newState` is the assembler's default state with the rail shape, type and backwards flag;
  // `POWERED` and `WATERLOGGED` stay at their defaults (`false`).
  await setBlockState(
    world,
    pos,
    BState(cartAssemblerKey, {
      'shape': shape!,
      'rail_type': type.serializedName,
      'backwards': '$backwards',
    }),
  );
  world.playCustomSound(
    soundName: 'minecraft:block.stone.place',
    category: SoundCategory.blocks,
    pos: (pos.$1 + .5, pos.$2 + .5, pos.$3 + .5),
    volume: 1,
    pitch: 1,
  );
  if (e.player.getGamemode() != GameMode.creative) {
    await shrinkHeld(e.player, e.hand, e.item);
  }
  return true;
}

/// `CartAssemblerBlock.onWrenched` / `onSneakWrenched`.
Wrenchable cartAssemblerWrenchable() => CallbackWrenchable(
  // `rotate(CLOCKWISE_90)`: the rail shape turns a quarter, then the block below updates.
  onWrenchedOverride: (c) async {
    final pos = (c.pos.x, c.pos.y, c.pos.z);
    final state = HostBlockGetter(c.world).stateAt(pos);
    if (state.key != cartAssemblerKey) return WrenchResult.pass;
    final shape = state['shape'] == 'north_south' ? 'east_west' : 'north_south';
    await setBlockState(
      c.world,
      pos,
      state.setValue('shape', shape),
      flags: BlockUpdateFlags.normal,
    );
    await c.world.updateNeighbors(
      pos: BlockPos(x: pos.$1, y: pos.$2 - 1, z: pos.$3),
      sourceBlock: cartAssemblerKey,
    );
    return WrenchResult.success;
  },
  // `onSneakWrenched`: the assembler turns back into its rail.
  onSneakOverride: (c) async {
    final pos = (c.pos.x, c.pos.y, c.pos.z);
    final state = HostBlockGetter(c.world).stateAt(pos);
    if (state.key != cartAssemblerKey) return WrenchResult.pass;

    if (c.player.getGamemode() != GameMode.creative) {
      await c.player.give(
        ItemStack.create(registryKey: cartAssemblerKey, count: 1),
      );
    }
    await setBlockState(
      c.world,
      pos,
      CartAssembleRailType.byName(state['rail_type']).railState(state),
      flags: BlockUpdateFlags.normal,
    );
    return WrenchResult.success;
  },
);
