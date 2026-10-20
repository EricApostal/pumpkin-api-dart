// The package items and entity type, and the package item's server interactions (throw, place,
// open). See `model/package.dart` for the package data helpers.
import 'dart:async';
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/module.dart';
import '../../core/registry.dart';
import '../host/player_items.dart';
import '../host/runtime.dart';
import '../logistics_part.dart';
import '../model/package.dart';
import '../model/stack.dart';

/// The package part: `PackageItem` and `PackageEntity` registration.
final class PackagePart extends LogisticsPart {
  @override
  String get name => 'package';

  @override
  void register(CreateRegistry registry) {
    // `AllItems`: every package style is its own item with a stack size of one.
    for (final key in PackageStyles.allKeys) {
      registry.item(ItemRegistration(key: key, maxStackSize: 1));
    }

    // `AllEntityTypes.PACKAGE`. `PackageEntity implements IEntityWithComplexSpawn`: the client
    // needs the box stack (and the motion) to draw the package.
    registry.entityType(
      const EntityTypeSpec(
        key: 'create:package',
        width: 1,
        height: 1,
        category: EntityCategory.misc,
        trackingRange: 10,
        updateInterval: 3,
        trackDeltas: true,
        summonable: true,
        saveable: true,
        pickable: true,
        pushable: true,
        spawnDataChannel: 'neoforge:advanced_add_entity',
      ),
    );
  }

  @override
  void onLoad(CreateContext ctx, LgRuntime rt) {
    ctx.listen(Events.playerInteract, (server, e) async {
      if (e.cancelled) return;
      if (e.action != InteractAction.rightClickAir &&
          e.action != InteractAction.rightClickBlock)
        return;
      await _onInteract(rt, e);
    });
  }

  Future<void> _onInteract(LgRuntime rt, PlayerInteractEventData e) async {
    final player = e.player;
    final hand = player.getInventory().getItemInHand(hand: Hand.right);
    if (hand == null) return;
    final stack = await rt.read(hand);
    if (!PackageItem.isPackage(stack)) return;

    // Blocks of this module handle packages themselves (unpacking, configuration, ...).
    if (e.action == InteractAction.rightClickBlock && _handlesPackages(e.block))
      return;

    final entity = player.asEntity();
    final sneaking = entity.isSneaking();
    entity.dispose();

    if (sneaking) {
      await _open(rt, player, stack);
      return;
    }

    final world = player.getWorld();
    try {
      final (px, py, pz) = player.getPosition();
      final (double, double, double) pos;
      if (e.action == InteractAction.rightClickBlock && e.clickedPos != null) {
        pos = (
          e.clickedPos!.x + 0.5,
          e.clickedPos!.y + 1.0,
          e.clickedPos!.z + 0.5,
        );
      } else {
        final yaw = player.getYaw() * pi / 180;
        pos = (px + sin(-yaw) * 0.5, py + 1.2, pz + cos(-yaw) * 0.5);
      }

      final host = await rt.write(stack.withCount(1));
      if (host == null) return;
      await world.dropItem(pos, host, velocity: (0, 0.15, 0));
    } finally {
      world.dispose();
    }
    await consumeOneInHand(player, Hand.right);
  }

  /// `PackageItem.open`: the contents spill into the player's inventory.
  Future<void> _open(LgRuntime rt, Player player, LStack box) async {
    for (final stack in PackageItem.contentsList(box)) {
      await giveToPlayer(player, stack);
    }
    await consumeOneInHand(player, Hand.right);
  }

  /// Blocks that consume a package interaction on their own.
  static bool _handlesPackages(String block) =>
      block == 'create:packager' ||
      block == 'create:repackager' ||
      block == 'create:package_frogport' ||
      block == 'create:stock_ticker' ||
      block == 'create:redstone_requester' ||
      block == 'create:factory_gauge' ||
      block == 'create:item_hatch' ||
      block.endsWith('_postbox') ||
      block.endsWith('_table_cloth');
}
