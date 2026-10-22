// The linked controller on the server: the item's component helpers, the lectern
// controller block and entity, the three serverbound payloads, the right clicks of the
// item and the frequency screen (`LinkedControllerMenu`) a sneak-use opens. The client
// side (key handling, the bind mode, the screen drawing) is not ours.
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../api/payloads.dart' show ItemIdResolver, ItemComponentPatch, ItemStackData;
import '../../api/util.dart' hide pos;
import '../../common/ghost_menu_layout.dart';
import '../../common/ghost_quick_move.dart';
import '../../common/menu_mirror.dart';
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../../core/registry.dart' show RegistryKind;
import '../../core/registry_apply.dart' show AppliedIds;
import '../../logistics/model/stack.dart';
import '../power_face.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/players.dart';
import '../support/rs_runtime.dart';
import 'controller_items.dart';
import 'controller_server.dart';
import 'frequency.dart';
import 'frequency_stacks.dart';
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

/// The `ControllerData` compound the lectern controller stores: `ItemContainerContents.CODEC`,
  /// i.e. `{items: [{slot, item}]}`. Java's `CatnipCodecUtils.encode(ItemContainerContents.CODEC, …)`
  /// writes the codec's own compound, not a bare list.
  NbtCompound controllerDataToNbt(ControllerItems items, ItemIdResolver ids) =>
      NbtCompound()..putList('items', controllerItemsToNbt(items, ids));

  /// The contents of a `ControllerData` tag: the `items` list of the compound, or a bare list
  /// (the shape an older save of this port wrote).
  ControllerItems controllerDataFromNbt(NbtCompound tag, ItemIdResolver ids) {
    final compound = tag.getCompound('ControllerData');
    final list = compound?.getList('items') ?? tag.getList('ControllerData');
    return controllerItemsFromNbt(list, ids);
  }

  /// The list tag of the `items` field.
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
    if (color != -1) item.putCompound('components', dyedComponents(color));
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
  return Frequency.of(key, color: components == null ? -1 : colorOfComponent(components) ?? -1);
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
    tag.putCompound('ControllerData', controllerDataToNbt(controllerData, controllerIds()));
    final u = user;
    if (u != null) tag.putIntArray('User', _uuidToInts(u));
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    controllerData = controllerDataFromNbt(tag, controllerIds());
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
            powerEventSide(e.face.toDirection()) == Direction.up && block.stateOf(e.stateIndex)['powered'] == 'true' ? 15 : 0,
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
    LinkedControllerMenus.install(ctx);
    ctx.host.intercept(Events.playerUseItem, _onUseItem);
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

  /// `LinkedControllerItem.use`: a sneak-use with the controller in the main hand opens the
  /// frequency screen (`player.openMenu(this, ...)`). A lectern controller swap is handled by
  /// [install] before this and never reaches here.
  static Future<PlayerUseItemEventData> _onUseItem(
    Server server,
    PlayerUseItemEventData e,
  ) async {
    if (e.hand != Hand.right) return e;
    if (!await isLinkedController(e.item)) return e;
    final player = e.player;
    if (!player.asEntity().isSneaking()) return e;
    // `player.mayBuild()`: a spectator cannot use the screen.
    if (player.getGamemode() == GameMode.spectator) return e;
    await LinkedControllerMenus.open(player, e.item);
    return e.cancel();
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

/// `AllMenuTypes.LINKED_CONTROLLER`.
const String linkedControllerMenuType = 'create:linked_controller';

/// `LinkedControllerMenu.addSlots`: the 36 player slots first, then the 12 frequency slots (two
/// per button).
const GhostMenu controllerLayout = GhostMenu.linkedController;

/// The menu slot of the controller frequency slot [i] (`36 + i`).
int controllerGhostSlot(int i) => controllerLayout.ghostSlot(i);

/// The screen of `LinkedControllerMenu`: the 12 frequency slots the client edits, backed by the
/// held controller's `create:linked_controller_items` component.
final class LinkedControllerSession {
  final int containerId;
  final String playerUuid;

  /// `ghostInventory`, from the held item's component when the menu opened.
  ControllerItems items;

  /// Whether a ghost slot changed: `LinkedControllerMenu.saveData` writes the component when the
  /// screen closes, so a menu that was only opened leaves the item alone.
  bool dirty = false;

  LinkedControllerSession(this.containerId, this.playerUuid, this.items);
}

abstract final class LinkedControllerMenus {
  static final Map<String, LinkedControllerSession> _byPlayer = {};

  /// The host ids, for the numeric item and data component ids of the component's format.
  static AppliedIds? _ids;
  static Map<int, String>? _componentNames;

  /// The click rules of the screen: a ghost slot takes one item off the cursor
  /// (`GhostItemMenu.clicked`; `LinkedControllerMenu.allowRepeats()`).
  static final MenuClickRules _rules = MenuClickRules(
    slotRules: [
      for (var i = 0; i < controllerLayout.ghostSlots; i++)
        MenuSlotRule(
          slot: controllerGhostSlot(i),
          kind: const MenuSlotKindGhost(),
          maxStackSize: 1,
        ),
    ],
    quickMoveTargets: const [],
  );

  static void install(CreateContext ctx) {
    _ids = ctx.ids;
    // The host applies the vanilla clicks (the player inventory mirror and the frequency slots; a
    // frequency slot takes one item off the cursor). The shift-clicks follow
    // `GhostItemMenu.quickMoveStack` and are applied here: one item of a mirror slot goes into the
    // first empty frequency slot, one item leaves a frequency slot.
    ctx.host.intercept(Events.menuClick, (server, e) async {
      if (e.menuType != linkedControllerMenuType) return e;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return e;
      if (e.mode != MenuClickMode.quickMove) return e;
      final sourceHost = await playerStackAt(e.player, e.slot);
      final sourceKey = sourceHost == null ? null : await sourceHost.getRegistryKey();
      final sourceCount = sourceHost == null ? 0 : await sourceHost.getCount();
      final move = ghostQuickMove(
        menuSlot: e.slot,
        source: sourceKey == null ? LStack.empty : LStack.of(sourceKey, sourceCount),
        ghostSlots: controllerLayout.ghostSlots,
        ghostEmpty: (i) => session.items.slot(i) == null,
      );
      if (!move.isNone) {
        if (move.take) {
          final current = session.items.slot(move.ghost);
          final count = current == null ? 0 : current.count - 1;
          session.items = session.items.withSlot(
            move.ghost,
            current == null || count <= 0 ? null : ItemTemplate(current.itemId, count, current.patch),
          );
        } else {
          final template = await _template(sourceHost);
          if (template != null) {
            session.items = session.items.withSlot(move.ghost, ItemTemplate(template.itemId, 1, template.patch));
          }
        }
        session.dirty = true;
        await _sendGhosts(e.player, session.items);
      }
      return e.copyWith(cancelled: true);
    });

    ctx.listen(Events.menuSlotChanged, (server, e) async {
      if (e.menuType != linkedControllerMenuType) return;
      final session = _byPlayer[e.player.getId().asString];
      if (session == null || session.containerId != e.containerId) return;
      for (final change in e.changes) {
        // The player inventory mirror the client's menu shows first.
        if (await applyPlayerMirrorChange(e.player, change)) continue;
        final slot = controllerLayout.ghostIndexAt(change.slot);
        if (slot == null) continue;
        session.items = session.items.withSlot(slot, await _template(change.stack));
        session.dirty = true;
      }
    });
    ctx.listen(Events.menuClosed, (server, e) {
      if (e.menuType != linkedControllerMenuType) return;
      unawaited(_save(e.player, e.containerId));
    });
    ctx.listen(Events.playerLeave, (server, e) {
      unawaited(_save(e.player, null));
    });
  }

  /// `ServerPlayer.openMenu(this, buf -> ItemStack.STREAM_CODEC.encode(buf, heldItem))`: the extra
  /// data is the controller, so the client's menu reads its frequencies
  /// (`LinkedControllerMenu.createOnClient`).
  static Future<void> open(Player player, ItemStack held) async {
    final itemId = controllerIds().idOf(linkedControllerItem);
    if (itemId == null) return;
    final count = await held.getCount();
    final component = held.customComponent(controllerItemsKey);
    final componentId = _componentId(controllerItemsKey);
    final patch = component != null && componentId != null
        ? ItemComponentPatch(added: [(componentId, Uint8List.fromList(component))])
        : ItemComponentPatch.empty;
    final extra = PacketBuffer.encode(
      (w) => ItemStackData(itemId, count, patch).write(w, allowEmpty: false),
    );
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: linkedControllerMenuType,
      // `MenuProvider.getDisplayName()` is an empty component.
      title: TextComponent.text(plain: ''),
      extraData: extra,
      slotCount: controllerLayout.menuSlots,
      options: MenuOptions(
        applyVanillaClicks: true,
        // The client's menu adds the player inventory first (`LinkedControllerMenu.addSlots`), so
        // the server tracks a mirror of it instead of the host's player-inventory layout.
        playerInventory: false,
        rules: _rules,
      ),
    );
    if (result is! OkResult<int, String>) {
      Rs.i.log.warn(
        'Could not open $linkedControllerMenuType: '
        '${(result as ErrorResult<int, String>).value}',
      );
      return;
    }
    final session = LinkedControllerSession(
      result.value,
      player.getId().asString,
      // `LinkedControllerItem.getFrequencyItems(contentHolder)`.
      readControllerItems(held),
    );
    _byPlayer[player.getId().asString] = session;
    await fillPlayerMirror(player);
    await _sendGhosts(player, session.items);
  }

  /// Sends the frequency slots to the client: the server's menu starts them empty, so the screen
  /// would show empty pickers otherwise.
  static Future<void> _sendGhosts(Player player, ControllerItems items) async {
    for (var i = 0; i < controllerLayout.ghostSlots; i++) {
      final template = items.slot(i);
      await setMenuSlot(
        player,
        controllerGhostSlot(i),
        template == null ? null : await _hostStack(template),
      );
    }
  }

  /// `LinkedControllerMenu.saveData` / `MenuBase.removed`: writes the frequency slots back into the
  /// component of the held item.
  static Future<void> _save(Player player, int? containerId) async {
    final session = _byPlayer.remove(player.getId().asString);
    if (session == null) return;
    if (containerId != null && session.containerId != containerId) return;
    if (!session.dirty) return;
    // `HeldItemGhostItemMenu`: the menu edits the item of the main hand.
    final held = player.getItemInHand(hand: Hand.right);
    if (!await isLinkedController(held)) return;
    writeControllerItems(
      held!,
      ControllerItems([
        for (var i = 0; i < controllerLayout.ghostSlots; i++) session.items.slot(i),
      ]),
    );
    await player.setItemInHand(hand: Hand.right, stack: held);
  }

  /// A host stack for [t] with its component patch (`ItemStack.STREAM_CODEC` shape).
  static Future<ItemStack?> _hostStack(ItemTemplate t) async {
    final key = controllerIds().keyOf(t.itemId);
    if (key == null) return null;
    final stack = ItemStack.create(registryKey: key, count: t.count);
    for (final (id, bytes) in t.patch.added) {
      final name = _componentNameOf(id);
      if (name == null) continue;
      final vanilla = DataComponent.fromWireName(RegistryKeys.toWireName(name));
      if (vanilla != null) {
        await stack.setComponent(component: vanilla, value: bytes);
      } else {
        stack.setCustomComponent(name, bytes);
      }
    }
    return stack;
  }

  /// The `ItemStackTemplate` of [stack]: the stack a click put in a ghost slot, components
  /// included (`GhostItemMenu.clicked` copies the cursor stack).
  static Future<ItemTemplate?> _template(ItemStack? stack) async {
    if (stack == null) return null;
    final count = await stack.getCount();
    if (count <= 0) return null;
    final itemId = controllerIds().idOf(await stack.getRegistryKey());
    if (itemId == null) return null;
    final added = <(int, Uint8List)>[];
    for (final c in await stack.getComponents()) {
      final id = _componentId(RegistryKeys.fromWireName(c.component.wireName));
      if (id == null) continue;
      added.add((id, Uint8List.fromList(c.value)));
    }
    return ItemTemplate(itemId, count, ItemComponentPatch(added: added));
  }

  static int? _componentId(String key) => _ids?.of(RegistryKind.dataComponents, key);

  static String? _componentNameOf(int id) {
    _componentNames ??= {
      for (final e in _ids?.all(RegistryKind.dataComponents).entries ?? const <MapEntry<String, int>>[])
        e.value: e.key,
    };
    return _componentNames?[id];
  }
}
