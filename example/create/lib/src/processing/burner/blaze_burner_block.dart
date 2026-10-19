// `BlazeBurnerBlock` and `LitBlazeBurnerBlock`: the burner's block states, the heat levels,
// the fuel tables (the host has no reader for the vanilla `minecraft:cooking_fuel` component,
// see `data_component_codec.dart`) and the interactions (lighting, fuel, goggles, stock
// keeper).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart' hide pos;
import '../basin/basin_block_entity.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/heat.dart';
import '../../core/blocks.dart';
import '../support/kinetics_bridge.dart';
import 'blaze_burner_block_entity.dart';

/// `BlazeBurnerBlock`.
abstract final class BlazeBurnerBlock {
  static const String key = 'create:blaze_burner';

  /// `HEAT_LEVEL` (the manifest property is named `blaze`).
  static const String blazeProperty = 'blaze';

  /// `HorizontalDirectionalBlock.FACING`.
  static const String facingProperty = 'facing';

  /// The item that places a burner with a captured blaze.
  static const String filledItemKey = 'create:blaze_burner';

  /// The item that places an empty burner.
  static const String emptyItemKey = 'create:empty_blaze_burner';

  /// `AllShapes.HEATER_BLOCK_SHAPE`.
  static final BlockShape shape = BlockShape.boxes(const [
    BlockBox(1 / 16, 0, 1 / 16, 15 / 16, 14 / 16, 15 / 16),
  ]);

  /// `AllShapes.HEATER_BLOCK_SPECIAL_COLLISION_SHAPE`.
  static final BlockShape specialCollisionShape = BlockShape.boxes(const [
    BlockBox(0, 0, 0, 1, 4 / 16, 1),
  ]);

  /// `CreateDataMaps.SUPERHEATED_BLAZE_BURNER_FUELS` (`create:blaze_cake`).
  static const Map<String, int> superheatedFuels = {'create:blaze_cake': 3200};

  /// Vanilla furnace fuels. `minecraft:cooking_fuel` cannot be read by the host, so the common
  /// fuels are listed; anything else falls back to the `create:blaze_burner_fuel/*` tags.
  static const Map<String, int> regularFuels = {
    'minecraft:coal': 1600,
    'minecraft:charcoal': 1600,
    'minecraft:coal_block': 16000,
    'minecraft:blaze_rod': 2400,
    'minecraft:lava_bucket': 20000,
    'minecraft:dried_kelp_block': 4000,
    'minecraft:stick': 100,
    'minecraft:bamboo': 50,
    'minecraft:crafting_table': 300,
    'minecraft:bookshelf': 300,
    'minecraft:chest': 300,
    'minecraft:ladder': 300,
  };

  /// The burn time of a superheated fuel, or `null`.
  static int? specialFuelBurnTime(String key) => superheatedFuels[key];

  /// The burn time of a regular fuel, or `null`.
  static int? regularFuelBurnTime(String key) {
    final direct = regularFuels[key];
    if (direct != null) return direct;
    if (!key.startsWith('minecraft:')) return null;
    // Wooden blocks and items share the 300 / 100 tick furnace values.
    if (key.endsWith('_planks') ||
        key.endsWith('_log') ||
        key.endsWith('_wood') ||
        key.endsWith('_stem') ||
        key.endsWith('_hyphae') ||
        key.endsWith('_fence') ||
        key.endsWith('_fence_gate') ||
        key.endsWith('_stairs')) {
      return 300;
    }
    if (key.endsWith('_slab')) return 150;
    if (key.endsWith('_sapling') ||
        key.endsWith('_wool') ||
        key.endsWith('_carpet'))
      return 100;
    return null;
  }

  /// The crafting remainder of a fuel item (lava buckets give their bucket back).
  static String? craftingRemainderOf(String key) =>
      key == 'minecraft:lava_bucket' ? 'minecraft:bucket' : null;

  /// `BlazeBurnerBlock.getHeatLevelOf`.
  static HeatLevel heatLevelOf(BState state) {
    final value = state[blazeProperty];
    if (value == null) return HeatLevel.none;
    return HeatLevel.byName(value) ?? HeatLevel.none;
  }

  /// `BlazeBurnerBlock.getLight` as far as a static luminance can express it (the host cannot
  /// change the light level per state; the block is registered with 0).
  static int lightOf(HeatLevel heat) => switch (heat) {
    HeatLevel.none => 0,
    HeatLevel.smouldering => 8,
    _ => 15,
  };

  static CreateBlock build() => createBlockFromManifest(
    'blaze_burner',
    blockEntityType: BlazeBurnerBlockEntity.type,
    placement: const [PlacementRule.horizontalFacing('facing', opposite: true)],
    collisionShape: shape,
    selectionShape: shape,
    behavior: BlockBehavior(
      onPlaced: _onPlaced,
      onUse: _onUse,
      onComparatorOutput: (server, e) {
        final state = HostBlockGetter(e.targetWorld).stateAt(e.pos.toPos());
        return heatLevelOf(state).index <= 1 ? 0 : heatLevelOf(state).index - 1;
      },
      onCloneItem: (server, e) async {
        final state = HostBlockGetter(e.targetWorld).stateAt(e.pos.toPos());
        final key = heatLevelOf(state) == HeatLevel.none
            ? emptyItemKey
            : filledItemKey;
        return ItemStack.create(registryKey: key, count: 1);
      },
      isPathfindable: (server, e) => false,
    ),
  );

  /// `onPlace`: tell a basin above, and place a captured blaze as smouldering.
  static Future<void> _onPlaced(
    Server server,
    CustomBlockPlacedEventData e,
  ) async {
    final rt = ProcessingRuntime.instance;
    final worldId = rt.worlds.touch(e.targetWorld);
    final pos = e.pos.toPos();

    final above = rt.store.typed<BasinBlockEntity>(
      worldId,
      pos.above.toBlockPos(),
    );
    above?.notifyChangeOfContents();

    final playerId = e.player;
    if (playerId == null) return;
    final player = server.getPlayerByUuid(id: playerId);
    if (player == null) return;

    // `BlazeBurnerBlockItem.hasCapturedBlaze()`: the filled item places a smouldering burner.
    final inventory = player.getInventory();
    final main = inventory.getItemInHand(hand: Hand.right);
    final off = inventory.getItemInHand(hand: Hand.left);
    var captured = false;
    for (final held in [main, off]) {
      if (held == null) continue;
      if (await held.getRegistryKey() == filledItemKey) {
        captured = true;
        break;
      }
    }
    if (!captured) return;

    final state = HostBlockGetter(e.targetWorld).stateAt(pos);
    if (heatLevelOf(state) != HeatLevel.none) return;
    await setBlockState(
      e.targetWorld,
      pos,
      state.setValue(blazeProperty, HeatLevel.smouldering.serializedName),
    );
  }

  /// `useItemOn`.
  static Future<BlockUseResult> _onUse(
    Server server,
    CustomBlockUseEventData e,
  ) async {
    final rt = ProcessingRuntime.instance;
    final worldId = rt.worlds.touch(e.targetWorld);
    final pos = e.pos.toPos();
    final state = HostBlockGetter(e.targetWorld).stateAt(pos);
    final heat = heatLevelOf(state);
    final be = rt.store.typed<BlazeBurnerBlockEntity>(worldId, e.pos);

    final itemKey = e.withItem ? await e.item.getRegistryKey() : '';
    if (itemKey == 'create:goggles' && heat != HeatLevel.none) {
      if (be == null) return BlockUseResult.tryEmptyHand;
      if (be.goggles) return BlockUseResult.tryEmptyHand;
      be.goggles = true;
      be.sendData();
      return BlockUseResult.success;
    }

    if (be != null && be.stockKeeper) {
      // `StockTickerInteractionHandler.interactWithLogisticsManagerAt` (logistics module) is not
      // ported; the click is consumed so the burner does not take fuel.
      return BlockUseResult.success;
    }

    if (!e.withItem && heat != HeatLevel.none) {
      if (be == null || !be.goggles) return BlockUseResult.tryEmptyHand;
      be.goggles = false;
      be.sendData();
      return BlockUseResult.success;
    }

    if (heat == HeatLevel.none) {
      if (itemKey == 'minecraft:flint_and_steel') {
        await setBlockState(
          e.targetWorld,
          pos,
          BState(LitBlazeBurnerBlock.key, {
            LitBlazeBurnerBlock.flameTypeProperty: 'regular',
          }),
        );
        return BlockUseResult.success;
      }
      return BlockUseResult.tryEmptyHand;
    }

    if (be == null || !e.withItem) return BlockUseResult.tryEmptyHand;

    final stack = await HostStacks.read(e.item);
    if (stack.isEmpty) return BlockUseResult.tryEmptyHand;

    final before = stack.count;
    final remainder = be.tryInsertFuel(
      stack,
      doNotConsume: e.player.isCreative,
      forceOverflow: true,
    );
    if (remainder.count == before) return BlockUseResult.tryEmptyHand;

    if (!e.player.isCreative) {
      await _shrinkHeld(e.player, e.hand);
      final remainderKey = craftingRemainderOf(stack.key);
      if (remainderKey != null) await e.player.giveItem(remainderKey);
    }
    return BlockUseResult.success;
  }

  /// `ItemStack.shrink(1)` on the stack in [hand].
  static Future<void> _shrinkHeld(Player player, Hand hand) async {
    final inventory = player.getInventory();
    final held = inventory.getItemInHand(hand: hand);
    if (held == null) return;
    final count = await held.getCount();
    if (count <= 1) {
      await inventory.setItemInHand(hand: hand, item: null);
    } else {
      await held.setCount(count: count - 1);
      await inventory.setItemInHand(hand: hand, item: held);
    }
  }
}

/// `LitBlazeBurnerBlock`: the freshly lit burner, until it is extinguished.
abstract final class LitBlazeBurnerBlock {
  static const String key = 'create:lit_blaze_burner';

  /// `FlameType` (`regular` / `soul`).
  static const String flameTypeProperty = 'flame_type';

  static CreateBlock build() => createBlockFromManifest(
    'lit_blaze_burner',
    collisionShape: BlazeBurnerBlock.shape,
    selectionShape: BlazeBurnerBlock.shape,
    behavior: BlockBehavior(
      onUse: _onUse,
      onComparatorOutput: (server, e) {
        final state = HostBlockGetter(e.targetWorld).stateAt(e.pos.toPos());
        return state[flameTypeProperty] == 'soul' ? 2 : 1;
      },
      onCloneItem: (server, e) => ItemStack.create(
        registryKey: BlazeBurnerBlock.emptyItemKey,
        count: 1,
      ),
      isPathfindable: (server, e) => false,
    ),
  );

  /// `useItemOn`: a shovel douses the flame, soul fire base blocks turn it soul.
  static Future<BlockUseResult> _onUse(
    Server server,
    CustomBlockUseEventData e,
  ) async {
    final pos = e.pos.toPos();
    final state = HostBlockGetter(e.targetWorld).stateAt(pos);
    final itemKey = e.withItem ? await e.item.getRegistryKey() : '';

    if (itemKey.endsWith('_shovel')) {
      await setBlockState(
        e.targetWorld,
        pos,
        BState(BlazeBurnerBlock.key, {
          BlazeBurnerBlock.blazeProperty: 'none',
          BlazeBurnerBlock.facingProperty: 'north',
        }),
      );
      return BlockUseResult.success;
    }

    if (state[flameTypeProperty] == 'regular' &&
        (itemKey == 'minecraft:soul_sand' ||
            itemKey == 'minecraft:soul_soil')) {
      await setBlockState(
        e.targetWorld,
        pos,
        state.setValue(flameTypeProperty, 'soul'),
      );
      return BlockUseResult.success;
    }

    return BlockUseResult.tryEmptyHand;
  }
}
