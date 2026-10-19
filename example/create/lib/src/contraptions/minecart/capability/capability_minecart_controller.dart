// `CapabilityMinecartController`: the controllers of the loaded carts of a world, the carts that
// have a coupling, and the per-tick update that refreshes both and runs the coupling physics.
//
// Java: `content/contraptions/minecart/capability/CapabilityMinecartController`.
import '../../../common/common.dart';
import '../coupling_physics.dart';
import '../minecart_access.dart';
import '../minecart_sim2020.dart';
import 'minecart_controller.dart';

abstract final class CapabilityMinecartController {
  static final Map<String, Map<String, MinecartController>> _controllers = {};
  static final Map<String, Set<String>> _loadedWithCoupling = {};
  static final Map<String, Set<String>> _queuedAdditions = {};
  static final Map<String, Set<String>> _queuedRemovals = {};

  static Map<String, MinecartController> _of(String worldId) =>
      _controllers.putIfAbsent(worldId, () => {});

  /// `get(world, cart)`: the controller of a cart, created on first use.
  static MinecartController get(MinecartWorld level, String cartUuid) =>
      _of(level.worldId)[cartUuid] ??= MinecartController(level, cartUuid);

  /// `getIfPresent`: the controller of [cartUuid], `null` when it is not loaded.
  static MinecartController? getIfPresent(
    MinecartWorld level,
    String? cartUuid,
  ) {
    if (cartUuid == null) return null;
    return _of(level.worldId)[cartUuid];
  }

  /// A controller by cart uuid in a world id (for other modules and the physics hooks).
  static MinecartController? byUuid(String worldId, String cartUuid) =>
      _controllers[worldId]?[cartUuid];

  /// `queuedAdditions.get(world).add(cart)`.
  static void queueAddition(MinecartWorld level, String cartUuid) =>
      _queuedAdditions.putIfAbsent(level.worldId, () => {}).add(cartUuid);

  /// Marks a cart for removal from the loaded set (the cart was removed).
  static void queueRemoval(MinecartWorld level, String cartUuid) =>
      _queuedRemovals.putIfAbsent(level.worldId, () => {}).add(cartUuid);

  /// `loadedMinecartsWithCoupling.get(world)`.
  static Set<String> loadedWithCoupling(String worldId) =>
      _loadedWithCoupling.putIfAbsent(worldId, () => {});

  /// The per-tick update: loads new carts, ticks every controller, refreshes the coupling sets and
  /// runs the coupling physics.
  static void tick(MinecartWorld level) {
    final worldId = level.worldId;
    final controllers = _of(worldId);

    // Carts that joined.
    for (final cartUuid
        in _queuedAdditions.remove(worldId) ?? const <String>{}) {
      final cart = level.byUuid(cartUuid);
      if (cart == null) continue;
      controllers.putIfAbsent(
        cartUuid,
        () => MinecartController(level, cartUuid),
      );
    }
    // Carts that left.
    for (final cartUuid
        in _queuedRemovals.remove(worldId) ?? const <String>{}) {
      controllers.remove(cartUuid);
    }
    // Carts that no longer exist.
    controllers.removeWhere((uuid, controller) => !controller.isPresent);

    // Install the lookups the physics asks for.
    MinecartStallLookup.isStalled = (uuid) =>
        byUuid(worldId, uuid)?.isStalled ?? false;
    MinecartCouplingLookup.couplingLength = (uuid) {
      final controller = byUuid(worldId, uuid);
      if (controller == null || !controller.isLeadingCoupling) return 0;
      return controller.getCouplingLength(true);
    };

    for (final controller in controllers.values.toList()) {
      controller.tick();
    }

    // Refresh the set of carts that lead a coupling.
    final withCoupling = loadedWithCoupling(worldId)..clear();
    for (final entry in controllers.entries) {
      if (entry.value.isLeadingCoupling) withCoupling.add(entry.key);
    }

    // Coupling physics.
    for (final cartUuid in withCoupling.toList()) {
      final controller = controllers[cartUuid];
      if (controller == null) continue;
      final otherUuid = controller.getCoupledCart(true);
      final other = getIfPresent(level, otherUuid);
      if (other == null) continue;
      final first = level.byUuid(cartUuid);
      final second = level.byUuid(otherUuid ?? '');
      if (first == null || second == null) continue;
      tickCoupling(Couple(first, second));
    }
  }

  /// Forgets a world (world unload).
  static void forgetWorld(String worldId) {
    _controllers.remove(worldId);
    _loadedWithCoupling.remove(worldId);
    _queuedAdditions.remove(worldId);
    _queuedRemovals.remove(worldId);
  }

  static void clear() {
    _controllers.clear();
    _loadedWithCoupling.clear();
    _queuedAdditions.clear();
    _queuedRemovals.clear();
  }
}
