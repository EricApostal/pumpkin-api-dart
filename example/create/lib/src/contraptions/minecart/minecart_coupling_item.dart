// `MinecartCouplingItem` (server side): the coupling item and the wrench remove couplings from a
// minecart. The two-cart selection is made by the client, which sends
// `create:minecart_coupling_creation`.
//
// Java: `content/contraptions/minecart/MinecartCouplingItem`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../blocks/actuator_runtime.dart';
import 'capability/capability_minecart_controller.dart';
import 'coupling_handler.dart';
import 'minecart_access.dart';

const String minecartCouplingKey = 'create:minecart_coupling';

/// The registration of `create:minecart_coupling`.
ItemRegistration minecartCouplingItem() =>
    const ItemRegistration(key: minecartCouplingKey);

/// The item in the main hand of [player] (Java reads the event's hand; the host event does not
/// carry it).
Future<String?> heldItemKey(Player player) async {
  final inventory = player.getInventory();
  for (final hand in [Hand.right, Hand.left]) {
    final stack = inventory.getItemInHand(hand: hand);
    if (stack == null) continue;
    try {
      final key = await stack.getRegistryKey();
      if (key != 'minecraft:air') return key;
    } on Object {
      continue;
    }
  }
  return null;
}

/// `handleInteractionWithMinecart`: the coupling item reports a fully coupled cart, the wrench
/// removes the couplings. Returns whether the click was consumed.
Future<bool> onMinecartInteract(
  Server server,
  PlayerInteractEntityEventData e,
) async {
  if (e.action != EntityInteractionAction.interact) return false;

  final world = e.player.getWorld();
  final level = HostMinecartWorld(world, ActuatorRuntime.instance.store);
  final cart = level.byId(e.entityId);
  if (cart == null || !cart.isAnyMinecart) return false;

  final controller = CapabilityMinecartController.get(level, cart.uuid);
  if (!controller.isPresent) return false;

  final itemKey = await heldItemKey(e.player);
  if (itemKey == null) return false;

  if (itemKey == minecartCouplingKey) {
    if (controller.isFullyCoupled) {
      couplingStatus(e.player, 'two_couplings_max');
      return true;
    }
    // The client opens the coupling selection.
    return false;
  }
  if (itemKey != 'create:wrench') return false;

  var couplings =
      (controller.isConnectedToCoupling ? 1 : 0) +
      (controller.isLeadingCoupling ? 1 : 0);
  if (couplings == 0) return false;

  for (final forward in [true, false]) {
    if (controller.hasContraptionCoupling(forward)) couplings--;
  }

  couplingStatus(e.player, 'removed');
  controller.decouple();
  if (e.player.getGamemode() != GameMode.creative && couplings > 0) {
    await e.player.give(
      ItemStack.create(registryKey: minecartCouplingKey, count: couplings),
    );
  }
  return true;
}
