// `MinecartContraptionItem`: the three "minecart contraption" items. Placing one on a rail spawns
// the matching vanilla cart and puts the saved contraption on it; a wrench click picks the
// contraption back up into the item.
//
// Java: `content/contraptions/mounted/MinecartContraptionItem`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show HostBlockGetter;
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../core/nbt.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../core/contraption.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../data/contraption_pickup_limiting.dart';
import '../entity/contraption_entity.dart';
import '../entity/host_contraption_entities.dart';
import '../entity/oriented_contraption_entity.dart';
import '../minecart/minecart_access.dart';

/// `AllDataComponents.MINECART_CONTRAPTION_DATA`.
const String minecartContraptionDataComponent =
    'create:minecart_contraption_data';

/// `AllItems.MINECART_CONTRAPTION`.
const String minecartContraptionItemKey = 'create:minecart_contraption';
const String furnaceMinecartContraptionItemKey =
    'create:furnace_minecart_contraption';
const String chestMinecartContraptionItemKey =
    'create:chest_minecart_contraption';

/// The cart each item spawns (`minecartType`).
const Map<String, EntityType> minecartContraptionTypes = {
  minecartContraptionItemKey: EntityType.minecart,
  furnaceMinecartContraptionItemKey: EntityType.furnaceMinecart,
  chestMinecartContraptionItemKey: EntityType.chestMinecart,
};

/// The item for a cart type, `null` for any other entity.
String? minecartContraptionItemFor(EntityType? type) => switch (type) {
  EntityType.minecart => minecartContraptionItemKey,
  EntityType.furnaceMinecart => furnaceMinecartContraptionItemKey,
  EntityType.chestMinecart => chestMinecartContraptionItemKey,
  _ => null,
};

/// The item registrations (`Item.Properties` defaults: stack size 64).
List<ItemRegistration> minecartContraptionItemRegistrations() => [
  for (final key in minecartContraptionTypes.keys) ItemRegistration(key: key),
];

/// The contraption entities waiting for their host entity to exist before they ride the cart.
/// `ContraptionEntityFactory.spawn` is asynchronous, so the passenger is attached on the next
/// world tick.
/// The cart is stored as `worldId` and entity id: the `Entity` the callback received is a
/// borrowed resource that is released when the callback returns, so it cannot be held until the
/// next tick.
final List<(AbstractContraptionEntity, String, int)> _pendingRides = [];

/// `MinecartContraptionItem.useOn`: a click on a rail with one of the items spawns the cart.
Future<bool> useMinecartContraptionItem(
  Server server,
  PlayerUseBlockEventData e,
) async {
  if (e.cancelled) return false;

  final String itemKey;
  try {
    itemKey = await e.item.getRegistryKey();
  } catch (_) {
    return false;
  }
  final type = minecartContraptionTypes[itemKey];
  if (type == null) return false;
  final world = e.player.getWorld();
  if (!isRailState(HostBlockGetter(world).stateAt(e.blockPos.toPos()))) {
    return false;
  }

  final pos = e.blockPos.toPos();
  final shape = RailShape.byName(HostBlockGetter(world).stateAt(pos)['shape']);
  final slope =
      shape == null ||
          shape == RailShape.northSouth ||
          shape == RailShape.eastWest
      ? 0.0
      : 0.5;

  final cart = await world.spawnEntity(
    entityType: type,
    pos: (pos.$1 + .5, pos.$2 + 0.0625 + slope, pos.$3 + .5),
  );

  await addContraptionToMinecart(
    world,
    e.item,
    cart,
    Direction.fromYRot(e.player.getYaw()),
  );

  await shrinkHeld(e.player, e.hand, e.item);
  return true;
}

/// `addContraptionToMinecart`: reads the saved contraption from the item and puts it on [cart].
Future<void> addContraptionToMinecart(
  World world,
  ItemStack stack,
  Entity cart,
  Direction? newFacing,
) async {
  final List<int>? bytes;
  try {
    bytes = stack.customComponent(minecartContraptionDataComponent);
  } on Object {
    return;
  }
  if (bytes == null) return;

  final tag = NbtMap.of(NetworkNbt.decode(bytes));
  if (tag.isEmpty) return;

  final worldId = world.getId();
  final level = ActuatorHosts.levelOf(worldId);
  final factory = ActuatorHosts.entities;
  if (level == null || factory == null) return;

  // `readEnum(contraptionTag, "InitialOrientation", Direction.class)`: the Java enum name, falling
  // back to `Direction.values()[0]` ([Direction.down]).
  final initialOrientation =
      Direction.byName(tag.getString('InitialOrientation').toLowerCase()) ??
      Direction.values[0];
  final contraption = Contraption.fromNbt(level, tag, spawnData: false);

  final entity = factory.createOriented(
    worldId,
    contraption,
    initialOrientation,
  );
  if (newFacing != null && entity is OrientedContraptionEntity) {
    entity.startAtYaw(newFacing.toYRot);
  }
  factory.spawn(worldId, entity);
  attachContraptionToCart(entity, worldId, cart.getId());
}

/// `contraptionEntity.startRiding(cart)`: queued until the host entity exists (the factory's
/// spawn is asynchronous).
void attachContraptionToCart(
  AbstractContraptionEntity entity,
  String worldId,
  int cartId,
) => _pendingRides.add((entity, worldId, cartId));

/// Attaches the contraption entities spawned in the previous tick to their carts
/// (`contraptionEntity.startRiding(cart)`).
Future<void> tickPendingRides() async {
  if (_pendingRides.isEmpty) return;
  for (final (entity, worldId, cartId) in List.of(_pendingRides)) {
    final host = entity.host;
    if (host is! HostContraptionEntity) continue;
    final handle = host.handle;
    if (handle == null) continue;
    // `world.getEntity(id)`: the cart may have been removed in the meantime.
    final cart = ActuatorRuntime.maybe?.worlds.byId(worldId)?.getEntityById(
      id: cartId,
    );
    if (cart == null) {
      _pendingRides.remove((entity, worldId, cartId));
      continue;
    }
    try {
      await cart.addPassenger(passenger: handle);
      await handle.setVehicle(vehicle: cart);
    } on Object {
      // the cart or the contraption was removed in the meantime
    }
    _pendingRides.remove((entity, worldId, cartId));
  }
}

/// Forgets pending rides (plugin unload).
void clearPendingRides() => _pendingRides.clear();

/// `MinecartContraptionItem.wrenchCanBeUsedToPickUpMinecartContraptions`: a wrench click on a cart
/// that carries a contraption turns it back into an item.
Future<bool> tryPickUpMinecartContraption(
  Player player,
  World world,
  Entity cart,
) async {
  final runtime = ActuatorRuntime.maybe;
  if (runtime == null) return false;
  if (!runtime.settings.survivalContraptionPickup &&
      player.getGamemode() != GameMode.creative) {
    return false;
  }

  final cartType = cart.getType();
  final itemKey = minecartContraptionItemFor(cartType);
  if (itemKey == null) return false;

  final passengers = cart.getPassengers();
  if (passengers.isEmpty) return false;

  final worldId = world.getId();
  final contraptionEntity = ActuatorHosts.entities?.entityById(
    worldId,
    passengers.first.getId(),
  );
  if (contraptionEntity is! OrientedContraptionEntity) return false;

  final contraption = contraptionEntity.contraption;
  if (contraption == null) return false;

  // `ContraptionMovementSetting.isNoPickup`: a block of the structure forbids pickup.
  final noPickup = contraption.blocks.values.any(
    (b) =>
        contraption.settings?.movementSettingOf(b.state.key) ==
        ContraptionMovementSetting.noPickup,
  );
  if (noPickup) {
    player.sendSystemMessage(
      text: TextComponent.translate(
        key: 'create.contraption.minecart_contraption_illegal_pickup',
        with_: const [],
      ),
      overlay: true,
    );
    return true;
  }

  final level = ActuatorHosts.levelOf(worldId);
  if (level == null) return false;
  contraption.stopMoving();

  final stack = createMinecartContraptionItem(
    itemKey,
    contraption,
    contraptionEntity,
  );
  if (stack == null) return true;

  final tag = NbtMap.of(
    NetworkNbt.decode(
      stack.customComponent(minecartContraptionDataComponent) ?? const [],
    ),
  );
  if (ContraptionPickupLimiting.isTooLargeForPickup(tag)) {
    player.sendSystemMessage(
      text: TextComponent.translate(
        key: 'create.contraption.minecart_contraption_too_big',
        with_: const [],
      ),
      overlay: true,
    );
    return true;
  }

  await player.give(stack);
  contraptionEntity.host.remove();
  cart.remove();
  return true;
}

/// `MinecartContraptionItem.create`: the item holding the contraption's NBT.
ItemStack? createMinecartContraptionItem(
  String itemKey,
  Contraption contraption,
  OrientedContraptionEntity entity,
) {
  final tag = contraption.writeNbt(spawnPacket: false);
  tag.remove('UUID');
  tag.remove('Pos');
  tag.remove('Motion');
  // `entity.getInitialOrientation().name()`: the Java enum name (upper case), the same form
  // `OrientedContraptionEntity` writes and reads.
  tag.putString(
    'InitialOrientation',
    entity.getInitialOrientation().name.toUpperCase(),
  );

  final stack = ItemStack.create(registryKey: itemKey, count: 1);
  stack.setCustomComponent(
    minecartContraptionDataComponent,
    NetworkNbt.encode(tag.toValue()),
  );
  return stack;
}

/// `ItemStack.shrink(1)` in [hand] (the creative check is the caller's).
Future<void> shrinkHeld(Player player, Hand hand, ItemStack stack) async {
  final count = await stack.getCount();
  final inventory = player.getInventory();
  if (count <= 1) {
    await inventory.setItemInHand(hand: hand, item: null);
  } else {
    await stack.setCount(count: count - 1);
    await inventory.setItemInHand(hand: hand, item: stack);
  }
}
