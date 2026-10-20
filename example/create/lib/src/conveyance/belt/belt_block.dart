// The `create:belt` block: its definition (from the manifest, with one shape rule per state) and
// the server hooks of `BeltBlock.java` (dying, casing, package / hand / shaft use, the chain
// teardown, item entities on the belt).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show setBlockState;
import '../../api/kinetics.dart' show KState;
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/blocks.dart';
import '../../kinetics/block_factory.dart' show createBlockFromManifest;
import '../items/item_codec.dart';
import '../items/item_data.dart';
import '../behaviours/belt_interfaces.dart' show TransportedResult;
import '../runtime.dart';
import '../shapes.dart';
import 'belt_block_entity.dart';
import 'belt_connector_item.dart' show beltConnectorKey;
import 'belt_geometry.dart';
import 'belt_slicer_host.dart';

/// The `create:belt` block.
CreateBlock buildBeltBlock() {
  return createBlockFromManifest(
    'belt',
    blockEntityType: 'create:belt',
    placement: [
      // `BeltBlock extends HorizontalKineticBlock`: `getHorizontalDirection().getOpposite()`.
      PlacementRule.horizontalFacing('facing', opposite: true),
      PlacementRule.inWater('waterlogged'),
    ],
    shapeRules: const [],
    behavior: BlockBehavior(
      onShape: _shape,
      onUse: _use,
      onNeighborUpdate: _neighborUpdate,
      onEntityCollision: _entityCollision,
      onStateReplaced: _stateReplaced,
      onPlayerWillDestroy: _playerWillDestroy,
      onCloneItem: _cloneItem,
    ),
  );
}

/// The belt's shape depends on facing, slope, part and casing, which is 160 combinations: too many
/// for the host's 64 static shape rules. It is computed per state through the dynamic shape hook
/// (the host caches it per position; every state write invalidates the cache).
FutureOr<List<BlockBox>?> _shape(Server server, CustomBlockShapeEventData e) {
  if (!ConveyanceRuntime.loaded) return null;
  final block = ConveyanceRuntime.i.blocks[e.block];
  if (block == null) return null;
  final state = BState(e.block, block.stateOf(e.stateIndex));
  return e.kind == BlockShapeKind.collision
      ? BeltShapes.getCollisionShape(state)
      : BeltShapes.getShape(state);
}

BState _stateAt(ConveyanceRuntime rt, String worldId, Pos pos) =>
    rt.stateAt(worldId, pos);

BeltBlockEntity? _segment(ConveyanceRuntime rt, String worldId, Pos pos) =>
    rt.typedAt<BeltBlockEntity>(worldId, pos);

// -- Use --------------------------------------------------------------------------------------

Future<BlockUseResult> _use(Server server, CustomBlockUseEventData e) async {
  if (!ConveyanceRuntime.loaded) return BlockUseResult.pass;
  final rt = ConveyanceRuntime.i;
  final world = e.targetWorld;
  final worldId = rt.ctx.worlds.touch(world);
  final pos = e.pos.toPos();
  final state = BState(
    'create:belt',
    rt.blocks['create:belt']!.stateOf(e.stateIndex),
  );
  final player = e.player;

  if (e.sneaking) return BlockUseResult.tryEmptyHand;

  final String? key = e.withItem ? await _itemKey(e.item) : null;
  final isWrench = key == 'create:wrench';
  final isConnector = key == beltConnectorKey;
  final isShaft = key == 'create:shaft';
  final isHand = key == null || key == airKey;
  final dye = key == null ? null : _dyeColor(key);
  final isWater = key == 'minecraft:water_bucket';

  if (dye != null || isWater) {
    final belt = _segment(rt, worldId, pos);
    if (belt != null && belt.applyColor(dye)) return BlockUseResult.success;
    return BlockUseResult.tryEmptyHand;
  }

  if (isConnector) {
    return useConnector(rt, world, worldId, pos, state, player, e.cursor);
  }
  if (isWrench) {
    return useWrench(
      rt,
      world,
      worldId,
      pos,
      state,
      player,
      e.face.toDirection(),
      e.cursor,
    );
  }

  final belt = _segment(rt, worldId, pos);
  if (belt == null) return BlockUseResult.tryEmptyHand;

  if (key != null && isPackageKey(key)) {
    final value = await ItemCodec.read(e.item);
    final handler = belt.itemHandler;
    if (handler == null) return BlockUseResult.tryEmptyHand;
    final remainder = await handler.insert(0, value);
    if (remainder.isEmpty) {
      await _consumeOne(player, e);
      return BlockUseResult.success;
    }
  }

  if (isHand) {
    final controller = belt.controllerBE;
    final inv = controller?.getInventory();
    if (inv == null) return BlockUseResult.tryEmptyHand;
    var success = false;
    inv.applyToEachWithin(belt.index + .5, .55, (t) {
      unawaited(ItemCodec.giveToPlayer(player, t.stack));
      success = true;
      return TransportedResult.removeItem();
    });
    if (success) {
      world.playSound(
        sound: Sound.entityItemPickup,
        category: SoundCategory.players,
        pos: (pos.x + .5, pos.y + .5, pos.z + .5),
        volume: .2,
        pitch: 1 + sharedRandom.nextDouble(),
      );
      return BlockUseResult.success;
    }
  }

  if (isShaft) {
    if (state.beltPart != BeltPart.middle) return BlockUseResult.tryEmptyHand;
    await _consumeOne(player, e);
    await _switch(
      rt,
      world,
      worldId,
      pos,
      state.setValue('part', BeltPart.pulley.name),
    );
    return BlockUseResult.success;
  }

  if (key == 'create:brass_casing') {
    belt.setCasingType(BeltCasing.brass);
    belt.updateCoverProperty();
    world.playSound(
      sound: Sound.blockMetalPlace,
      category: SoundCategory.blocks,
      pos: (pos.x + .5, pos.y + .5, pos.z + .5),
      volume: .5,
      pitch: .8,
    );
    return BlockUseResult.success;
  }
  if (key == 'create:andesite_casing') {
    belt.setCasingType(BeltCasing.andesite);
    belt.updateCoverProperty();
    world.playSound(
      sound: Sound.blockStonePlace,
      category: SoundCategory.blocks,
      pos: (pos.x + .5, pos.y + .5, pos.z + .5),
      volume: .5,
      pitch: .8,
    );
    return BlockUseResult.success;
  }

  return BlockUseResult.tryEmptyHand;
}

Future<String?> _itemKey(ItemStack stack) async {
  try {
    if (await stack.getCount() <= 0) return null;
    return await stack.getRegistryKey();
  } on Object {
    return null;
  }
}

/// The dye colour name of a dye item (`minecraft:red_dye` -> `RED`), `null` for other items.
String? _dyeColor(String key) {
  if (!key.startsWith('minecraft:') || !key.endsWith('_dye')) return null;
  final name = key.substring('minecraft:'.length, key.length - '_dye'.length);
  return switch (name) {
    'white' ||
    'orange' ||
    'magenta' ||
    'light_blue' ||
    'yellow' ||
    'lime' ||
    'pink' ||
    'gray' ||
    'light_gray' ||
    'cyan' ||
    'purple' ||
    'blue' ||
    'brown' ||
    'green' ||
    'red' ||
    'black' => name.toUpperCase(),
    _ => null,
  };
}

Future<void> _consumeOne(Player player, CustomBlockUseEventData e) async {
  final held = player.getItemInHand(hand: e.hand);
  if (held == null) return;
  final count = await held.getCount();
  if (count <= 1) {
    await player.setItemInHand(hand: e.hand, stack: null);
  } else {
    await held.setCount(count: count - 1);
    // `getItemInHand` is a copy: the decremented count only exists once it is written back.
    await player.setItemInHand(hand: e.hand, stack: held);
  }
}

// -- Neighbours, entities, removal, clone ----------------------------------------------------

Future<void> _neighborUpdate(
  Server server,
  CustomBlockNeighborUpdateEventData e,
) async {
  if (!ConveyanceRuntime.loaded) return;
  final rt = ConveyanceRuntime.i;
  final worldId = rt.ctx.worlds.touch(e.targetWorld);
  _segment(rt, worldId, e.pos.toPos())?.updateCoverProperty();
}

Future<void> _entityCollision(
  Server server,
  CustomBlockEntityCollisionEventData e,
) async {
  if (!ConveyanceRuntime.loaded) return;
  final rt = ConveyanceRuntime.i;
  final world = e.targetWorld;
  final worldId = rt.ctx.worlds.touch(world);
  final pos = e.pos.toPos();
  final state = BState(
    'create:belt',
    rt.blocks['create:belt']!.stateOf(e.stateIndex),
  );
  if (!canTransportObjects(state)) return;

  final belt = _segment(rt, worldId, pos);
  if (belt == null) return;

  final entity = world.getEntityById(id: e.entityId);
  if (entity == null) return;
  try {
    if (entity.isItem()) {
      await belt.absorbItemEntity(entity);
    } else {
      // `BeltBlock.entityInside` stores the passenger on the *controller*
      // (`BeltBlock.java:225-234`); the collided segment is not ticked
      // (`BeltBlockEntity.java:130`, `if (!isController()) return;`), so a passenger remembered
      // by the segment would never move.
      final controller = belt.controllerBE;
      if (controller == null) {
        rt.log.error('CV01DBG collision pos=$pos id=${e.entityId} no-controller');
        return;
      }
      final (x, y, z) = entity.getPosition();
      final added = controller.entityEntered(
        e.entityId,
        pos,
        KState('create:belt', state.props),
        (x.floor(), y.floor(), z.floor()),
      );
      rt.log.error(
        'CV01DBG collision pos=$pos id=${e.entityId} controller=${controller.p} '
        'added=$added passengers=${controller.passengers.length}',
      );
      if (added) entity.setOnGround(onGround: true);
    }
  } finally {
    entity.dispose();
  }
}

Future<void> _stateReplaced(
  Server server,
  CustomBlockStateReplacedEventData e,
) async {
  if (!ConveyanceRuntime.loaded || e.moved) return;
  final rt = ConveyanceRuntime.i;
  final world = e.targetWorld;
  final worldId = rt.ctx.worlds.touch(world);
  final pos = e.pos.toPos();
  final state = BState(
    'create:belt',
    rt.blocks['create:belt']!.stateOf(e.oldStateIndex),
  );

  // Destroy the rest of the chain, in both directions.
  final chain = <Pos>[];
  for (final forward in [true, false]) {
    Pos? current = nextSegmentPosition(state, pos, forward);
    while (current != null) {
      final currentState = _stateAt(rt, worldId, current);
      if (!currentState.isBelt) break;
      chain.add(current);
      current = nextSegmentPosition(currentState, current, forward);
    }
  }

  for (final at in chain) {
    final currentState = _stateAt(rt, worldId, at);
    final belt = _segment(rt, worldId, at);
    var hasPulley = false;
    if (belt != null) {
      if (belt.isController) {
        final inv = belt.getInventory();
        if (inv != null) unawaited(inv.ejectAll());
      }
      hasPulley = belt.hasPulley;
    }
    final axis = beltRotationAxis(currentState);
    final replacement = hasPulley
        ? BState('create:shaft', {'axis': axis.serializedName})
        : BState.air;
    await setBlockState(world, at, replacement);
  }
}

/// `BeltBlock.getDrops`: a belt with a pulley also drops the shaft it was made from.
Future<bool> _playerWillDestroy(
  Server server,
  CustomBlockPlayerWillDestroyEventData e,
) async {
  if (!ConveyanceRuntime.loaded) return true;
  final rt = ConveyanceRuntime.i;
  final worldId = rt.ctx.worlds.touch(e.targetWorld);
  final belt = _segment(rt, worldId, e.pos.toPos());
  if (belt == null || !belt.hasPulley || e.player.isCreative) return true;
  await ItemCodec.giveToPlayer(e.player, const ItemValue('create:shaft', 1));
  return true;
}

Future<ItemStack?> _cloneItem(
  Server server,
  CustomBlockCloneItemEventData e,
) async => ItemStack.create(registryKey: beltConnectorKey, count: 1);

Future<void> _switch(
  ConveyanceRuntime rt,
  World world,
  String worldId,
  Pos pos,
  BState state,
) async {
  final kinetics = rt.kinetics;
  if (kinetics != null) {
    await kinetics.switchToBlockState(
      worldId,
      pos.toBlockPos(),
      KState(state.key, state.props),
    );
    return;
  }
  await setBlockState(world, pos, state);
}
