// `CouplingHandler`: creating, removing and walking the chain of coupled minecarts, plus the
// status message shown to the player.
//
// Java: `content/contraptions/minecart/CouplingHandler`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../blocks/actuator_runtime.dart';
import 'minecart_access.dart';

import '../../common/common.dart';
import 'capability/capability_minecart_controller.dart';
import 'capability/minecart_controller.dart';

/// `getNextInCouplingChain`: `MinecartController.empty()` at the end of the chain, `null` when the
/// next cart is not loaded.
MinecartController? nextInCouplingChain(
  MinecartWorld level,
  MinecartController controller,
  bool forward,
) {
  final coupledUuid = controller.getCoupledCart(forward);
  if (coupledUuid == null) return MinecartController.empty();
  return CapabilityMinecartController.getIfPresent(level, coupledUuid);
}

/// `forEachLoadedCoupling`.
void forEachLoadedCoupling(
  MinecartWorld level,
  void Function(Couple<MinecartController>) consumer,
) {
  for (final cartUuid in CapabilityMinecartController.loadedWithCoupling(
    level.worldId,
  ).toList()) {
    final controller = CapabilityMinecartController.getIfPresent(
      level,
      cartUuid,
    );
    if (controller == null || !controller.isLeadingCoupling) continue;
    final other = CapabilityMinecartController.getIfPresent(
      level,
      controller.getCoupledCart(true),
    );
    if (other == null) continue;
    consumer(Couple(controller, other));
  }
}

/// `tryToCoupleCarts`.
Future<bool> tryToCoupleCarts(
  Player? player,
  MinecartWorld level,
  int cartId1,
  int cartId2,
) async {
  final cart1 = level.byId(cartId1);
  final cart2 = level.byId(cartId2);
  if (cart1 == null || cart2 == null) return false;

  var distanceTo = (cart1.position - cart2.position).length.floor();
  final contraptionCoupling = player == null;

  if (distanceTo < 2) {
    if (contraptionCoupling) return false;
    distanceTo = 2;
  }

  final maxLength = ActuatorRuntime.maybe?.maxCartCouplingLength ?? 32;
  if (distanceTo > maxLength) {
    _status(player, 'too_far');
    return false;
  }

  final mainController = CapabilityMinecartController.get(level, cart1.uuid);
  final connectedController = CapabilityMinecartController.get(
    level,
    cart2.uuid,
  );

  if (!mainController.isPresent || !connectedController.isPresent) {
    _status(player, 'unloaded');
    return false;
  }
  if (mainController.isFullyCoupled || connectedController.isFullyCoupled) {
    _status(player, 'two_couplings_max');
    return false;
  }

  if (mainController.isLeadingCoupling &&
          mainController.getCoupledCart(true) == cart2.uuid ||
      connectedController.isLeadingCoupling &&
          connectedController.getCoupledCart(true) == cart1.uuid) {
    return false;
  }

  for (final main in [true, false]) {
    var current = main ? mainController : connectedController;
    final forward = current.isLeadingCoupling;
    var safetyCount = 1000;
    while (true) {
      if (safetyCount-- <= 0) return false;
      final next = nextInCouplingChain(level, current, forward);
      if (next == null) {
        _status(player, 'unloaded');
        return false;
      }
      if (identical(next, connectedController)) {
        _status(player, 'no_loops');
        return false;
      }
      if (next.isEmpty) break;
      current = next;
    }
  }

  if (!contraptionCoupling) await _consumeCoupling(player);

  mainController.prepareForCoupling(true);
  connectedController.prepareForCoupling(false);

  mainController.coupleWith(
    true,
    cart2.uuid,
    distanceTo.toDouble(),
    contraptionCoupling,
  );
  connectedController.coupleWith(
    false,
    cart1.uuid,
    distanceTo.toDouble(),
    contraptionCoupling,
  );
  return true;
}

/// `status`: the player sees the coupling status above the hotbar.
void _status(Player? player, String key) {
  if (player == null) return;
  player.sendSystemMessage(
    text: TextComponent.translate(
      key: 'create.minecraft_coupling.$key',
      with_: const [],
    ),
    overlay: true,
  );
}

/// Takes one coupling item from the player's hands (creative players keep theirs).
Future<void> _consumeCoupling(Player player) async {
  if (player.getGamemode() == GameMode.creative) return;
  final inventory = player.getInventory();
  for (final hand in [Hand.right, Hand.left]) {
    final stack = inventory.getItemInHand(hand: hand);
    if (stack == null) continue;
    try {
      final key = await stack.getRegistryKey();
      if (key != 'create:minecart_coupling') continue;
      final count = await stack.getCount();
      await inventory.setItemInHand(
        hand: hand,
        item: count <= 1
            ? null
            : ItemStack.create(registryKey: key, count: count - 1),
      );
      return;
    } on Object {
      continue;
    }
  }
}

/// `status` for other modules.
void couplingStatus(Player? player, String key) => _status(player, key);
