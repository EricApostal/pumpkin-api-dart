// `FunnelMovementBehaviour`: a funnel on a contraption acts on every block the contraption moves
// it into - an extracting funnel drops items out of the contraption's inventory, otherwise the
// funnel pulls the dropped items it runs over into it. The andesite funnel has no filter.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../../conveyance/items/item_codec.dart';
import '../../conveyance/items/item_data.dart';
import '../../conveyance/transport/transport_support.dart';
import '../actors/actor_runtime.dart';
import '../core/movement.dart';
import '../core/nbt_map.dart';
import '../storage/stacks.dart';

/// `FunnelMovementBehaviour`.
final class FunnelMovementBehaviour extends MovementBehaviour {
  const FunnelMovementBehaviour._(this.hasFilter);

  /// `FunnelMovementBehaviour.andesite`.
  factory FunnelMovementBehaviour.andesite() =>
      const FunnelMovementBehaviour._(false);

  /// `FunnelMovementBehaviour.brass`.
  factory FunnelMovementBehaviour.brass() =>
      const FunnelMovementBehaviour._(true);

  /// `hasFilter`: only the brass funnel reads a filter and a filter amount.
  final bool hasFilter;

  @override
  Vec3 getActiveAreaOffset(MovementContext context) {
    final facing = funnelFacing(context.state) ?? Direction.north;
    final vec = facing.unitVec3;
    if (facing != Direction.up) {
      return vec * (context.state.flag('extracting') ? .15 : .65);
    }
    return vec * .65;
  }

  @override
  Future<void> visitNewPosition(MovementContext context, Pos pos) async {
    if (context.state.flag('extracting')) {
      await extract(context, pos);
    } else {
      await succ(context, pos);
    }
  }

  /// `extract`: takes items out of the contraption's inventory and drops them at the funnel as a
  /// new item entity.
  Future<void> extract(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;

    final position = context.position;
    if (position == null) return;
    final funnelFacingDir = funnelFacing(context.state) ?? Direction.north;
    final entityPos = funnelFacingDir == Direction.down
        ? position
        : (position.$1, position.$2 - .5, position.$3);

    // The target block has to be free of collisions, with no dropped items in it.
    if (!context.level.stateCollisionEmpty(context.level.stateAt(pos))) return;
    if (_itemsInBlock(world, posContaining(entityPos)).isNotEmpty) return;

    final filter = _getFilter(context);
    final rawAmount = context.blockEntityData?.getInt('FilterAmount') ?? 0;
    final filterAmount = hasFilter ? rawAmount : 1;
    final upTo = context.blockEntityData?.getBool('UpTo') ?? false;

    final storage = context.contraption.storage.allItems;
    bool matches(StoredStack stack) => _filterMatches(filter, stack);

    // `ItemHelper.extract(..., EXACTLY, amount, false)`: the amount has to be present in full,
    // otherwise nothing is taken. `ItemSlotsHelper.extract` takes what is there, so the exact
    // mode checks it up front with a simulated extraction.
    if (!upTo) {
      final available =
          ItemSlotsHelper.extract(storage, matches, filterAmount, simulate: true);
      if (available.count != filterAmount) return;
    }

    final extracted = ItemSlotsHelper.extract(storage, matches, filterAmount);
    if (extracted.isEmpty) return;

    await ItemCodec.drop(
      world,
      entityPos,
      ItemValue(extracted.item, extracted.count),
      velocity: (0, 0, 0),
      pickupDelay: 5,
    );
    playSoundAt(world, pos, Sound.entityItemPickup, volume: 1 / 16, pitch: .1);
  }

  /// `succ`: pulls the dropped items in the block the funnel moved into into the contraption's
  /// inventory.
  Future<void> succ(MovementContext context, Pos pos) async {
    final world = actors?.worldOf(context);
    if (world == null) return;

    final filter = _getFilter(context);
    final storage = context.contraption.storage.allItems;
    // Java also considers `PackageEntity` here; the port models a package as its item stack
    // (`chain_conveyor_block_entity.dart` drops a box as an item entity), so only dropped items
    // are seen.
    for (final entity in _itemsInBlock(world, pos)) {
      final value = await ItemCodec.read(entity.getStack());
      if (value.isEmpty) continue;
      if (!_filterMatchesItem(filter, value.key)) continue;

      final remainder =
          ItemSlotsHelper.insert(storage, StoredStack(value.key, value.count));
      if (remainder.count == value.count) continue;
      if (remainder.isEmpty) {
        entity.discard();
        continue;
      }

      await setEntityItem(entity.asEntity(), value.withCount(remainder.count));
    }
  }

  /// `MovementContext.getFilterFromBE`: the filter of the funnel, read from its block entity data.
  static StoredStack _getFilter(MovementContext context) {
    final value = context.blockEntityData?['Filter'];
    if (value == null) return StoredStack.empty;
    return StoredStack.fromNbt(NbtMap.of(value));
  }

  /// `FilterItemStack.test`: an empty filter accepts everything. Java compares with
  /// `ItemStack.isSameItem` for a plain filter (components ignored); the actors of this port
  /// compare the stored components as the roller does (`sameItemSameComponents`).
  static bool _filterMatches(StoredStack filter, StoredStack stack) =>
      filter.isEmpty || stack.sameItemSameComponents(filter);

  /// `FilterItemStack.test` for the stack of a dropped item: only the item can be compared, the
  /// host gives the components of a live entity in their network form while the filter holds the
  /// form Java persists (`ItemStack.isSameItem`).
  static bool _filterMatchesItem(StoredStack filter, String key) =>
      filter.isEmpty || filter.item == key;

  /// The dropped items in the block at [pos] (`new AABB(pos)`, `getEntitiesOfClass(ItemEntity)`).
  static List<ItemEntity> _itemsInBlock(World world, Pos pos) =>
      itemEntitiesIn(world, (
        pos.$1.toDouble(),
        pos.$2.toDouble(),
        pos.$3.toDouble(),
      ), (
        pos.$1 + 1.0,
        pos.$2 + 1.0,
        pos.$3 + 1.0,
      ));
}