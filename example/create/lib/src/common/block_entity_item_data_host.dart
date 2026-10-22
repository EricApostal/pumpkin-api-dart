// The host side of the item data of a block whose block entity survives break -> place
// (`block_entity_item_data.dart` is the shaping, this is the plumbing): one pair of interceptors
// and one pair of block hooks, shared by the tank and the schematicannon.
//
// Java does this in `BlockItem`/vanilla:
//  * break/pick-block: `ServerGamePacketListenerImpl.addBlockDataToItem` writes the block
//    entity's saved NBT into the item's `minecraft:block_entity_data` component (and its implicit
//    components), and the loot table's `copy_components` does the same for the cannon's
//    `create:schematicannon_options`;
//  * placement: `BlockItem.updateCustomBlockEntityTag` merges that component *over* the fresh
//    block entity's own saved NBT (`TypedEntityData.loadInto`) and
//    `updateBlockEntityComponents` applies the item's components to it.
//
// The host has neither hook for a plugin block: a placed plugin block entity starts empty
// (`crates/pumpkin-core/src/block/registry.rs` `create_block_entity` returns `None` for a plugin
// type, so its placement path never runs), and `PluginBlockEntity` does not override
// `collect_item_components`, which the drop path does call
// (`crates/pumpkin-core/src/block/mod.rs` `drop_loot`). So both directions are done here.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart' show manifestBlocksByKey;
import '../common/direction.dart' as dir;
import '../common/host_bridge.dart' show BlockDirectionToPure;
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../core/module.dart';
import '../processing/common/stack.dart' show namespacedItemKey;
import 'block_entity_item_data.dart';

/// One block whose item form carries the block entity's data across break -> place.
final class ItemDataBlock {
  /// The block key (`create:fluid_tank`).
  final String blockKey;

  /// The item the block drops (`create:fluid_tank`, from the manifest's `blockItem`).
  final String itemKey;

  /// The component the data travels in: [blockEntityDataComponent], or one of the mod's own.
  final String componentKey;

  /// Whether [componentKey] is a `create:*` component; the host keeps those as *custom*
  /// components (`ItemStack.customComponent`), separate from the vanilla ones.
  final bool customComponent;

  /// The block entity at [pos] of [world], `null` when the block there is not this block's
  /// entity. Doubles as the type check the drop intercept keys on.
  final CreateBlockEntity? Function(World world, BlockPos pos) entityAt;

  /// The component value for [be]: the canonical layout of `block_entity_item_data.dart`.
  final List<int> Function(CreateBlockEntity be) itemComponent;

  /// Applies an item's component to the freshly created [be] - `bytes` is `null` when the item
  /// carried none, which is the `getOrDefault` case of Java's `applyImplicitComponents`.
  final void Function(CreateBlockEntity be, List<int>? bytes) applyComponent;

  const ItemDataBlock({
    required this.blockKey,
    required this.itemKey,
    required this.componentKey,
    required this.entityAt,
    required this.itemComponent,
    required this.applyComponent,
    this.customComponent = false,
  });
}

/// The item a manifest block drops (`create:<blockItem>`, the manifest's `blockItem`): the key
/// `BlockDrops.selfItem` puts on the dropped stack, and so the key the stamping matches.
String manifestItemKeyOf(String blockKey) {
  final key = blockKey.startsWith('create:')
      ? blockKey.substring('create:'.length)
      : blockKey;
  return 'create:${manifestBlocksByKey[key]?.blockItem ?? key}';
}

/// The pure position of a host [BlockPos].
Pos _posOf(BlockPos p) => (p.x, p.y, p.z);

/// A `playerUseBlock` click that may place one of the registered blocks.
///
/// The placement event carries no stack (and no hand: `FluidTankItem` reads
/// `ctx.getItemInHand()`, the hand of the click), so the item of the click is read while the use
/// event's handles are still valid and kept as bytes.
final class _Click {
  final String itemKey;
  final List<int>? component;
  final Pos clickedPos;
  final dir.Direction face;

  const _Click(this.itemKey, this.component, this.clickedPos, this.face);

  /// Whether this click placed a block at [pos]: the neighbour of the clicked block, or the
  /// clicked block itself when it was replaced (`BlockPlaceContext.getClickedPos`).
  bool placedAt(Pos pos) => clickedPos.relative(face) == pos || clickedPos == pos;
}

/// The one mechanism both blocks use: register the block, install the interceptors once.
abstract final class ItemDataStamps {
  /// The blocks whose items carry their block entity's data.
  static final List<ItemDataBlock> blocks = [];

  /// The block entity store the interceptors were installed for: one per runtime, shared by
  /// every module (`CreateContext` is built per module, so it cannot be the guard).
  static BlockEntityStore? _installedFor;
  static Logger? _log;

  /// The last block click of each player, by `player.getId()` (`high`, `low`).
  static final Map<(int, int), _Click> _clicks = {};

  /// Adds [block] to the mechanism (from a module's `register`).
  static void register(ItemDataBlock block) {
    blocks.removeWhere((b) => b.blockKey == block.blockKey);
    blocks.add(block);
  }

  /// Installs the shared interceptors (from a module's `onLoad`; idempotent per runtime).
  static void install(CreateContext ctx) {
    if (identical(_installedFor, ctx.blockEntities)) return;
    _installedFor = ctx.blockEntities;
    _log = ctx.log;
    _clicks.clear();
    ctx.host.intercept(Events.playerUseBlock, _rememberClick);
    ctx.host.intercept(Events.blockDropItem, _stampDrops);
  }

  /// `BlockBehaviour.getCloneItemStack` for a block of [blocks]: the plain item with the block
  /// entity's data on it (`ServerGamePacketListenerImpl.addBlockDataToItem`).
  static Future<ItemStack> cloneItem(
    ItemDataBlock block,
    CustomBlockCloneItemEventData e,
  ) async {
    final stack = ItemStack.create(registryKey: block.itemKey, count: 1);
    final be = block.entityAt(e.targetWorld, e.pos);
    if (be != null) await _setComponent(stack, block, block.itemComponent(be));
    return stack;
  }

  /// The placement half (`BlockItem.updateCustomBlockEntityTag` and
  /// `updateBlockEntityComponents`): applies the component of the item the player placed with to
  /// the fresh block entity at the placed position, and publishes it.
  ///
  /// Call it from the block's `placed` hook, *after* the block entity exists and after whatever
  /// the block itself does on placement (`FluidTankBlock.onPlace`'s connectivity runs before
  /// vanilla merges the item's NBT, and the merge reads the entity's own NBT as its base).
  ///
  /// A block entity placed without a click of its own item (a deployer, the schematicannon)
  /// gets [ItemDataBlock.applyComponent] with `null`, which is Java's `getOrDefault` default.
  static Future<void> applyPlaced(
    ItemDataBlock block,
    Server server,
    CustomBlockPlacedEventData e,
  ) async {
    final be = block.entityAt(e.targetWorld, e.pos);
    if (be == null) return;
    List<int>? bytes;
    final playerId = e.player;
    if (playerId != null) {
      final key = (playerId.high, playerId.low);
      final click = _clicks[key];
      if (click != null &&
          click.itemKey == block.itemKey &&
          click.placedAt(_posOf(e.pos))) {
        _clicks.remove(key);
        bytes = click.component;
      }
    }
    block.applyComponent(be, bytes);
    be.markDirty();
    be.sendData();
  }

  // -- interceptors ------------------------------------------------------------------------

  /// Keeps the item of the last block click of each player for [applyPlaced].
  static Future<PlayerUseBlockEventData> _rememberClick(
    Server server,
    PlayerUseBlockEventData e,
  ) async {
    try {
      final itemKey = await _itemKey(e.item);
      final block = _blockForItem(itemKey);
      if (block == null) return e;
      final id = e.player.getId();
      _clicks[(id.high, id.low)] = _Click(
        itemKey,
        await _readComponent(e.item, block),
        _posOf(e.blockPos),
        e.face.toDirection(),
      );
    } on Object catch (error, stack) {
      _log?.warn(
        'Could not read a block click with ${e.item}',
        error: error,
        stackTrace: stack,
      );
    }
    return e;
  }

  /// The drop half: the item a block of [blocks] drops carries the block entity's data.
  ///
  /// The host has already rolled the drops of the block at the position (this is its
  /// `blockDropItem` event) and calls `collect_item_components` afterwards, which a plugin block
  /// entity does not implement - so the component is written onto the dropped stack here. A
  /// registration keeps `BlockDrops.selfItem`, so an explosion or a piston still drops the item
  /// itself; this only annotates it.
  static Future<BlockDropItemEventData> _stampDrops(
    Server server,
    BlockDropItemEventData e,
  ) async {
    for (final block in blocks) {
      try {
        final be = block.entityAt(e.targetWorld, e.blockPos);
        if (be == null) continue;
        final bytes = block.itemComponent(be);
        for (final stack in e.items) {
          if (await _itemKey(stack) != block.itemKey) continue;
          await _setComponent(stack, block, bytes);
        }
      } on Object catch (error, stack) {
        _log?.warn(
          'Could not write the data of ${block.blockKey} on its drop',
          error: error,
          stackTrace: stack,
        );
      }
    }
    return e;
  }

  // -- stacks ------------------------------------------------------------------------------

  /// `ItemStack.getRegistryKey()` with the default namespace restored.
  static Future<String> _itemKey(ItemStack stack) async =>
      namespacedItemKey(await stack.getRegistryKey());

  static ItemDataBlock? _blockForItem(String itemKey) {
    for (final block in blocks) {
      if (block.itemKey == itemKey) return block;
    }
    return null;
  }

  /// The value of [ItemDataBlock.componentKey] on [stack], `null` when it has none.
  static Future<List<int>?> _readComponent(
    ItemStack stack,
    ItemDataBlock block,
  ) async {
    if (block.customComponent) {
      final value = stack.customComponent(block.componentKey);
      return value == null ? null : List<int>.of(value);
    }
    for (final c in await stack.getComponents()) {
      if (c.component.wireName == block.componentKey) return List<int>.of(c.value);
    }
    return null;
  }

  static Future<void> _setComponent(
    ItemStack stack,
    ItemDataBlock block,
    List<int> bytes,
  ) async {
    if (block.customComponent) {
      stack.setCustomComponent(block.componentKey, bytes);
      return;
    }
    final component = DataComponent.fromWireName(block.componentKey);
    if (component == null) return;
    await stack.setComponent(component: component, value: bytes);
  }
}