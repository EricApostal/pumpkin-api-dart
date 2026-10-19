// The unpacking handlers that need the block entity at the target (`BasinUnpackingHandler`,
// `CrafterUnpackingHandler`). They register themselves in `UnpackingHandlers` when the module
// loads; the pure rules live in `unpacking.dart`.
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../core/block_entity.dart' show CreateBlockEntity;
import '../../processing/basin/basin_block_entity.dart' show BasinBlockEntity;
import '../../processing/crafter/mechanical_crafter_block_entity.dart';
import '../host/host_inventory.dart' show StorageInv;
import '../host/runtime.dart' show Lg;
import '../model/inventory.dart';
import '../model/orders.dart';
import '../model/stack.dart';
import 'unpacking.dart';

/// The target of a package being unpacked, with the block entity it names.
final class HostUnpackTarget implements UnpackTarget {
  final String worldId;
  final Pos pos;

  @override
  final PackageOrderWithCrafts? orderContext;

  const HostUnpackTarget(this.worldId, this.pos, {this.orderContext});

  /// The block entity at the target position, if it is a `T`.
  T? be<T extends CreateBlockEntity>() =>
      Lg.i.store.typed<T>(worldId, pos.toBlockPos());
}

/// `AllUnpackingHandlers.registerDefaults`: the handlers that need the target block entity.
void registerHostUnpackingHandlers() {
  UnpackingHandlers.register('create:basin', const BasinUnpackingHandler());
  UnpackingHandlers.register(
    'create:mechanical_crafter',
    const CrafterUnpackingHandler(),
  );
}

/// `BasinUnpackingHandler`: a basin takes the box's stacks slot by slot, so two different items
/// never share a slot (`BasinInventory.packagerMode`).
final class BasinUnpackingHandler implements UnpackingHandler {
  const BasinUnpackingHandler();

  @override
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
    UnpackTarget? where,
  }) async {
    final basin = where is HostUnpackTarget
        ? where.be<BasinBlockEntity>()
        : null;
    if (basin == null) return false;
    final inventory = basin.inputInventory;
    inventory.packagerMode = true;
    try {
      return await UnpackingHandlers.defaultHandler.unpack(
        target,
        items,
        simulate: simulate,
        where: where,
      );
    } finally {
      inventory.packagerMode = false;
    }
  }
}

/// `CrafterUnpackingHandler`: with crafting information, one item per connected crafter in the
/// order the recipe expects; without it, a plain stacked insert.
final class CrafterUnpackingHandler implements UnpackingHandler {
  const CrafterUnpackingHandler();

  @override
  Future<bool> unpack(
    ItemInv target,
    List<LStack> items, {
    required bool simulate,
    UnpackTarget? where,
  }) async {
    final context = where?.orderContext;
    if (!PackageOrderWithCrafts.hasCraftingInformation(context)) {
      return UnpackingHandlers.defaultHandler.unpack(
        target,
        items,
        simulate: simulate,
        where: where,
      );
    }

    final crafter = where is HostUnpackTarget
        ? where.be<MechanicalCrafterBlockEntity>()
        : null;
    if (crafter == null) return false;
    final inventories = crafter.connectedInventories;
    if (inventories.isEmpty) return false;

    final craftingContext = context!.craftingInformation;
    final max = inventories.length < craftingContext.length
        ? inventories.length
        : craftingContext.length;

    outer:
    for (var i = 0; i < max; i++) {
      final targetStack = craftingContext[i];
      if (targetStack.stack.isEmpty) continue;

      final inventory = StorageInv(inventories[i], Lg.i.io);
      // If there is already an item here, no point in trying.
      if ((await inventory.stackAt(0)).isNotEmpty) continue;

      // Go through each item in the box and try to insert it if it matches the target.
      for (var j = 0; j < items.length; j++) {
        final stack = items[j];
        if (stack.isEmpty) continue;
        if (!stack.sameItemSameComponents(targetStack.stack)) continue;
        final toInsert = stack.withCount(1);
        if ((await inventory.insert(0, toInsert, simulate: simulate)).isEmpty) {
          items[j] = stack.count > 1 ? stack.withCount(stack.count - 1) : LStack.empty;
          // One item per crafter, move to the next one once successful.
          continue outer;
        }
      }
    }

    for (final item in items) {
      if (item.isNotEmpty) return false;
    }

    if (!simulate) crafter.checkCompletedRecipe(true);
    return true;
  }
}

