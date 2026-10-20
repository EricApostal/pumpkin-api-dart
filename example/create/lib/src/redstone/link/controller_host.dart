// The linked controller on the server: the item's component helpers, the lectern
// controller block and entity, the three serverbound payloads and the right clicks of the
// item. The client side (key handling, the bind mode, the screen) is not ours.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/payloads.dart' show ItemIdResolver;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/players.dart';
import '../support/rs_runtime.dart';
import 'controller_items.dart';
import 'controller_server.dart';
import 'frequency.dart';
import 'link_behaviour.dart';

/// The component key.
const String controllerItemsKey = 'create:linked_controller_items';

/// The item key.
const String linkedControllerItem = 'create:linked_controller';

/// Item ids for the container codec: vanilla ids and the host's numbering of custom items.
ItemIdResolver controllerIds() =>
    ItemIdResolver.vanilla(custom: ItemRegistries.host.idOf, customKey: ItemRegistries.host.keyOf);

/// `LinkedControllerItem.getFrequencyItems(stack)`.
ControllerItems readControllerItems(ItemStack stack) {
  final bytes = stack.customComponent(controllerItemsKey);
  if (bytes == null) return ControllerItems.empty;
  return ControllerItems.decode(bytes, error: (e) => Rs.i.log.warn('Unreadable $controllerItemsKey: $e'));
}

/// `stack.set(LINKED_CONTROLLER_ITEMS, containerContentsFromHandler(...))`.
void writeControllerItems(ItemStack stack, ControllerItems items) =>
    stack.setCustomComponent(controllerItemsKey, items.encode());

Future<bool> isLinkedController(ItemStack? stack) async =>
    stack != null && await stack.getCount() > 0 && await stack.getRegistryKey() == linkedControllerItem;

// -- NBT form of the contents (`ItemContainerContents.CODEC`) --------------------------------

/// The list tag the lectern controller stores as `ControllerData`.
List<Object> controllerItemsToNbt(ControllerItems items, ItemIdResolver ids) {
  final list = <Object>[];
  for (var i = 0; i < items.slots.length; i++) {
    final t = items.slots[i];
    if (t == null) continue;
    final key = ids.keyOf(t.itemId);
    if (key == null) continue;
    final item = NbtCompound()
      ..putString('id', key)
      ..putInt('count', t.count);
    final color = _colorOf(t);
    if (color != -1) item.putCompound('components', NbtCompound()..putInt('minecraft:dyed_color', color));
    list.add(
      NbtCompound()
        ..putInt('slot', i)
        ..putCompound('item', item),
    );
  }
  return list;
}

int _colorOf(ItemTemplate t) {
  final dyed = dyedColorComponentId;
  if (dyed == null) return -1;
  for (final (id, bytes) in t.patch.added) {
    if (id == dyed && bytes.length >= 4) {
      return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]).toSigned(32);
    }
  }
  return -1;
}

/// The inverse of [controllerItemsToNbt].
ControllerItems controllerItemsFromNbt(List<Object>? list, ItemIdResolver ids) {
  if (list == null) return ControllerItems.empty;
  final slots = <int, ItemTemplate>{};
  var max = -1;
  for (final e in list) {
    if (e is! NbtCompound) continue;
    final slot = e.getInt('slot');
    final item = e.getCompound('item');
    final key = item?.getString('id');
    if (slot == null || item == null || key == null || slot < 0 || slot > 255) continue;
    final f = frequencyFromNbtLike(item, key);
    final template = ControllerItems.templateOf(f, ids);
    if (template == null) continue;
    slots[slot] = ItemTemplate(template.itemId, item.getInt('count') ?? 1, template.patch);
    if (slot > max) max = slot;
  }
  return ControllerItems([for (var i = 0; i <= max; i++) slots[i]]);
}

Frequency frequencyFromNbtLike(NbtCompound item, String key) {
  final components = item.getCompound('components');
  return Frequency.of(key, color: components?.getInt('minecraft:dyed_color') ?? -1);
}

// -- Lectern controller ---------------------------------------------------------------------

String _uuidFromInts(List<int> a) {
  String hex(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  final s = '${hex(a[0])}${hex(a[1])}${hex(a[2])}${hex(a[3])}';
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

List<int> _uuidToInts(String uuid) {
  final h = uuid.replaceAll('-', '');
  return [for (var i = 0; i < 4; i++) int.parse(h.substring(i * 8, i * 8 + 8), radix: 16).toSigned(32)];
}

/// `LecternControllerBlockEntity`.
final class LecternControllerBlockEntity extends CreateBlockEntity {
  static const String type = 'create:lectern_controller';
  static const String usingKey = 'IsUsingLecternController';

  ControllerItems controllerData = ControllerItems.empty;
  String? user;
  bool _deactivatedThisTick = false;

  LecternControllerBlockEntity(super.worldId, super.pos);

  /// `getController()`: a fresh controller stack with the stored frequencies.
  ItemStack createLinkedController() {
    final stack = ItemStack.create(registryKey: linkedControllerItem, count: 1);
    writeControllerItems(stack, controllerData);
    return stack;
  }

  bool get hasUser => user != null;

  /// `isUsedBy(player)`.
  bool isUsedBy(Player player) => user != null && user == player.getId().asString;

  /// `playerIsUsingLectern`.
  static bool playerIsUsingLectern(Player player) =>
      player.asEntity().hasCustomData(namespace: playerDataNamespace, key: usingKey);

  /// `playerInRange(player, world, pos)`.
  static bool playerInRange(Player player, Pos pos) {
    final attr = player.asEntity().asLiving()?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5;
    final reach = 0.4 * attr;
    final (ex, ey, ez) = eyePosition(player);
    final dx = ex - (pos.x + 0.5), dy = ey - (pos.y + 0.5), dz = ez - (pos.z + 0.5);
    return dx * dx + dy * dy + dz * dz < reach * reach;
  }

  /// `tryStartUsing`.
  void tryStartUsing(Player player) {
    if (!_deactivatedThisTick && !hasUser && !playerIsUsingLectern(player) && playerInRange(player, pos.toPos())) {
      _startUsing(player);
    }
  }

  /// `tryStopUsing`.
  void tryStopUsing(Player player) {
    if (isUsedBy(player)) _stopUsing(player);
  }

  void _startUsing(Player player) {
    user = player.getId().asString;
    player.asEntity().setCustomData(
      namespace: playerDataNamespace,
      key: usingKey,
      value: (NbtCompound()..putBool('v', true)).toTree(),
    );
    sendData();
  }

  void _stopUsing(Player? player) {
    user = null;
    if (player != null) {
      player.asEntity().removeCustomData(namespace: playerDataNamespace, key: usingKey);
    }
    _deactivatedThisTick = true;
    sendData();
  }

  @override
  void tick() {
    super.tick();
    _deactivatedThisTick = false;
    final u = user;
    if (u == null) return;
    final player = onlinePlayer(u);
    if (player == null) {
      _stopUsing(null);
      return;
    }
    if (!playerInRange(player, pos.toPos()) || !playerIsUsingLectern(player)) _stopUsing(player);
  }

  /// `setController(stack)`: copies the frequencies of [newController].
  void setController(ItemStack newController) {
    controllerData = readControllerItems(newController);
    final w = world;
    w?.playCustomSound(
      soundName: 'create:controller_put',
      category: SoundCategory.blocks,
      pos: pos.toPos().center,
      volume: 1,
      pitch: 1,
    );
    sendData();
  }

  /// `dropController`: drops a controller above the lectern and forgets the data.
  void dropController(Map<String, String> props) {
    final u = user;
    if (u != null) {
      final player = onlinePlayer(u);
      if (player != null) _stopUsing(player);
    }
    final dir = Direction.byName(props['facing'] ?? 'north') ?? Direction.north;
    final w = world;
    if (w != null) {
      final stack = createLinkedController();
      unawaited(w.dropItem((pos.x + 0.5 + 0.25 * dir.stepX, pos.y + 1.0, pos.z + 0.5 + 0.25 * dir.stepZ), stack));
    }
    controllerData = ControllerItems.empty;
  }

  @override
  void onRemoved() {
    super.onRemoved();
    // The block is gone: drop the controller (the old `onRemove`).
    final w = world;
    if (w != null) {
      unawaited(w.dropItem((pos.x + 0.5, pos.y + 1.0, pos.z + 0.5), createLinkedController()));
    }
    final u = user;
    if (u != null) {
      final player = onlinePlayer(u);
      if (player != null) player.asEntity().removeCustomData(namespace: playerDataNamespace, key: usingKey);
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putList('ControllerData', controllerItemsToNbt(controllerData, controllerIds()));
    final u = user;
    if (u != null) tag.putIntArray('User', _uuidToInts(u));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    controllerData = controllerItemsFromNbt(tag.getList('ControllerData'), controllerIds());
    final arr = tag.getIntArray('User');
    user = arr != null && arr.length == 4 ? _uuidFromInts(arr) : null;
  }
}

/// `LecternControllerBlock`.
final class LecternControllerBlock {
  static const String key = 'lectern_controller';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: LecternControllerBlockEntity.type,
      behavior: BlockBehavior(
        onUse: _onUse,
        onComparatorOutput: (server, e) => 15,
        onCloneItem: (server, e) async => ItemStacks.plain('minecraft:lectern'),
        // LecternBlock: the pulse of a turned page; the controller never sets it itself.
        onWeakPower: (server, e) => block.stateOf(e.stateIndex)['powered'] == 'true' ? 15 : 0,
        // `LecternBlock.getDirectSignal`: strong power only upwards (`direction == UP`).
        onStrongPower: (server, e) =>
            e.face == BlockDirection.up && block.stateOf(e.stateIndex)['powered'] == 'true' ? 15 : 0,
      ),
    );
    return block;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: LecternControllerBlockEntity.type,
    validBlocks: const ['create:lectern_controller'],
    create: LecternControllerBlockEntity.new,
    tickInterval: 1,
  );

  /// `useItemOn`.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    final pos = e.pos.toPos();
    if (!e.sneaking && LecternControllerBlockEntity.playerInRange(e.player, pos)) {
      Rs.i.be<LecternControllerBlockEntity>(e.targetWorld, e.pos)?.tryStartUsing(e.player);
      return BlockUseResult.success;
    }
    if (e.sneaking) {
      await replaceWithLectern(Lvl(e.targetWorld), pos);
      return BlockUseResult.success;
    }
    return e.withItem ? BlockUseResult.tryEmptyHand : BlockUseResult.pass;
  }

  /// `replaceWithLectern`: the controller leaves, the plain lectern stays.
  static Future<void> replaceWithLectern(Lvl lvl, Pos pos) async {
    final props = lvl.info(pos)?.properties;
    if (props == null) return;
    lvl.world.playCustomSound(
      soundName: 'create:controller_take',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    final state = BlockStates.withProperties('minecraft:lectern', {
      'facing': props['facing'] ?? 'north',
      'powered': props['powered'] ?? 'false',
    });
    if (state != null) await lvl.setState(pos, state, neighbors: true);
  }

  /// `replaceLectern`: a plain lectern becomes a lectern with [controller] on it.
  static Future<void> replaceLectern(Lvl lvl, Pos pos, Map<String, String> lecternProps, ItemStack controller) async {
    final state = BlockStates.withProperties('create:lectern_controller', {
      'facing': lecternProps['facing'] ?? 'north',
      'powered': lecternProps['powered'] ?? 'false',
      'has_book': 'true',
    });
    if (state == null) return;
    await lvl.setState(pos, state, neighbors: true);
    final be = Rs.i.store.typed<LecternControllerBlockEntity>(lvl.id, BlockPos(x: pos.x, y: pos.y, z: pos.z));
    be?.setController(controller);
  }
}

// -- The item and the payloads --------------------------------------------------------------------

/// Hooks of `LinkedControllerItem` and the three `LinkedControllerPacketBase` payloads.
abstract final class LinkedControllerHooks {
  static void install(CreateContext ctx, RsRuntime rs, LinkedControllerServerHandler handler) {
    // onItemUseFirst: lectern swap, lectern replace, link click.
    ctx.host.intercept(Events.itemUseFirst, (server, e) async {
      if (e.useResult != ItemUseFirstResult.pass) return e;
      if (await e.stack.getRegistryKey() != linkedControllerItem) return e;
      final player = e.player;
      if (player.getGamemode() == GameMode.spectator) return e;
      final world = player.getWorld();
      final lvl = Lvl(world);
      final pos = e.blockPos.toPos();
      final info = lvl.info(pos);
      if (info == null) return e;
      final sneaking = player.asEntity().isSneaking();
      if (sneaking) {
        if (info.key == 'create:lectern_controller') {
          final be = rs.be<LecternControllerBlockEntity>(world, e.blockPos);
          if (be != null) await _swapControllers(be, player, e.hand, info.properties);
          return e.copyWith(useResult: ItemUseFirstResult.success);
        }
        return e;
      }
      if (info.key == 'create:redstone_link') {
        player.startCooldown(group: linkedControllerItem, durationTicks: 2);
        return e.copyWith(useResult: ItemUseFirstResult.success);
      }
      if (info.key == 'minecraft:lectern' && info.properties['has_book'] != 'true') {
        final held = player.getItemInHand(hand: e.hand);
        if (held != null) {
          final lecternStack = ItemStack.create(registryKey: linkedControllerItem, count: 1);
          writeControllerItems(lecternStack, readControllerItems(held));
          if (player.getGamemode() != GameMode.creative) await _consumeOne(player, e.hand, held);
          await LecternControllerBlock.replaceLectern(lvl, pos, info.properties, lecternStack);
        }
        return e.copyWith(useResult: ItemUseFirstResult.success);
      }
      if (info.key == 'create:lectern_controller') return e;
      return e;
    });

    final bus = rs.bus;
    if (bus == null) return;

    // LinkedControllerInputPacket
    bus.onServerbound('create:linked_controller_input', (player, f) async {
      final lecternPos = f['lecternPos'] as (int, int, int)?;
      final press = f['press'] == true;
      final buttons = [for (final b in (f['activatedButtons'] as List<Object?>? ?? const [])) b as int];
      if (player.getGamemode() == GameMode.spectator && press) return;
      final world = player.getWorld();
      ItemStack? controller;
      if (lecternPos != null) {
        final be = rs.be<LecternControllerBlockEntity>(world, BlockPos(x: lecternPos.$1, y: lecternPos.$2, z: lecternPos.$3));
        if (be == null || !be.isUsedBy(player)) return;
        controller = be.createLinkedController();
      } else {
        controller = await _heldController(player);
        if (controller == null) return;
      }
      final items = readControllerItems(controller);
      final ids = controllerIds();
      final keys = [
        for (final b in buttons)
          if (b >= 0 && b < 6) items.toFrequency(b, ids),
      ];
      final (px, py, pz) = player.getPosition();
      handler.receivePressed(
        rs.worldId(world),
        (px.floor(), py.floor(), pz.floor()),
        player.getId().asString,
        keys,
        pressed: press,
      );
    });

    // LinkedControllerBindPacket
    bus.onServerbound('create:linked_controller_bind', (player, f) async {
      if (player.getGamemode() == GameMode.spectator) return;
      final button = f['button'] as int;
      if (button < 0 || button >= 6) return;
      final loc = f['linkLocation'] as (int, int, int);
      final world = player.getWorld();
      final held = await _heldController(player);
      if (held == null) return;
      final hand = (await isLinkedController(player.getItemInHand(hand: Hand.right))) ? Hand.right : Hand.left;
      final link = rs.be<CreateBlockEntity>(world, BlockPos(x: loc.$1, y: loc.$2, z: loc.$3))?.getBehaviour<LinkBehaviour>();
      if (link == null) return;
      final ids = controllerIds();
      var items = readControllerItems(held);
      final key = link.networkKey;
      items = items.withSlot(button * 2, ControllerItems.templateOf(key.first, ids));
      items = items.withSlot(button * 2 + 1, ControllerItems.templateOf(key.second, ids));
      writeControllerItems(held, items);
      await player.setItemInHand(hand: hand, stack: held);
    });

    // LinkedControllerStopLecternPacket
    bus.onServerbound('create:linked_controller_use_lectern', (player, f) {
      final p = f['lecternPos'] as (int, int, int);
      final be = rs.be<LecternControllerBlockEntity>(player.getWorld(), BlockPos(x: p.$1, y: p.$2, z: p.$3));
      be?.tryStopUsing(player);
    });
  }

  /// `LinkedControllerPacketBase.handle`: the controller in the main hand, else the offhand.
  static Future<ItemStack?> _heldController(Player player) async {
    final main = player.getItemInHand(hand: Hand.right);
    if (await isLinkedController(main)) return main;
    final off = player.getItemInHand(hand: Hand.left);
    if (await isLinkedController(off)) return off;
    return null;
  }

  static Future<void> _consumeOne(Player player, Hand hand, ItemStack held) async {
    final count = await held.getCount();
    if (count <= 1) {
      await player.setItemInHand(hand: hand, stack: null);
    } else {
      await held.setCount(count: count - 1);
      await player.setItemInHand(hand: hand, stack: held);
    }
  }

  /// `swapControllers`.
  static Future<void> _swapControllers(
    LecternControllerBlockEntity be,
    Player player,
    Hand hand,
    Map<String, String> state,
  ) async {
    final held = player.getItemInHand(hand: hand);
    if (held == null) return;
    final newController = ItemStack.create(registryKey: linkedControllerItem, count: 1);
    writeControllerItems(newController, readControllerItems(held));
    final remaining = (await held.getCount()) - 1;
    if (remaining <= 0) {
      // The hand is empty now: it receives the lectern's controller.
      await player.setItemInHand(hand: hand, stack: be.createLinkedController());
    } else {
      await held.setCount(count: remaining);
      await player.setItemInHand(hand: hand, stack: held);
      be.dropController(state);
    }
    be.setController(newController);
  }
}
