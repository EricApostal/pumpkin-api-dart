// The toolbox on the host: the block entity (inventory, connected players), the handler that
// keeps equipped hotbar slots topped up (`ToolboxHandler`), the equip / dispose-all packets and
// the menu (`ToolboxMenu`: 8 representative slots, clicks emulated here because the compartments
// have rules the vanilla click logic does not know).
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';
// The `menus` interface (options, cursor, click rules) is not part of the public wrappers yet.
// ignore: implementation_imports
import 'package:pumpkin_api/src/bindings.g.dart' as raw show menus;

import '../../core/block_entity.dart';
import '../../core/module.dart';
import '../../core/nbt.dart';
import '../../core/pos.dart';
import '../data/equipment_components.dart';
import '../host/env.dart';
import '../host/runtime.dart';
import '../host/stack_codec.dart';
import '../model/dir.dart';
import 'toolbox_bridge.dart';
import 'toolbox_model.dart';

const String toolboxBlockEntityType = 'create:toolbox';
const String toolboxMenuType = 'create:toolbox';
const String toolboxDataKey = 'CreateToolboxData';

final class _Equip {
  final int slot;
  final P3 pos;
  const _Equip(this.slot, this.pos);
}

/// Block entity of the toolboxes (`ToolboxBlockEntity`).
final class ToolboxBlockEntity extends CreateBlockEntity {
  ToolboxBlockEntity(super.worldId, super.pos) {
    inv.onChanged = () => sendData();
    inv.canFit = (s) => !s.key.endsWith('shulker_box');
    lazyTickRate = 10;
  }

  final ToolboxInv inv = ToolboxInv();
  String? uniqueId;
  String? customName;

  /// Number of players with the menu open (`AnimatedContainerBehaviour.openCount`).
  int openCount = 0;

  /// compartment -> player uuid -> hotbar slot
  final Map<int, Map<String, int>> connectedPlayers = {};

  bool _ticking = false;

  ToolboxHost get host => EquipmentRuntime.instance.toolbox;

  bool get isFullyInitialized => uniqueId != null;

  @override
  void onLoad() {
    super.onLoad();
    host._register(this);
  }

  @override
  void onUnload() {
    super.onUnload();
    host._unregister(this);
  }

  @override
  void onRemoved() {
    super.onRemoved();
    host._unregister(this);
  }

  @override
  void lazyTick() {
    super.lazyTick();
    host._register(this);
  }

  @override
  void tick() {
    super.tick();
    if (connectedPlayers.isEmpty || _ticking) return;
    _ticking = true;
    unawaited(host._tickPlayers(this).whenComplete(() => _ticking = false));
  }

  // -- NBT ---------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    uniqueId ??= host.newUuid();
    // The client's view (vanilla stack tags) ...
    final items = <Object>[];
    for (var i = 0; i < ToolboxInv.slotCount; i++) {
      final s = inv.slots[i];
      if (s.isEmpty) continue;
      items.add(StackCodec.toClientNbt(s)..putInt('Slot', i));
    }
    tag.putCompound(
      'Inventory',
      NbtCompound()
        ..putInt('Size', ToolboxInv.slotCount)
        ..putList('Items', items)
        ..putList('Compartments', [for (final f in inv.filters) f.isEmpty ? NbtCompound() : StackCodec.toClientNbt(f)]),
    );
    tag.putIntArray('UniqueId', _uuidToInts(uniqueId!));
    final name = customName;
    if (name != null) tag.putString('CustomName', name);
    if (clientPacket) {
      tag.putInt('OpenCount', openCount);
      return;
    }
    // ... and the private full-fidelity copy.
    tag.putList('Raw', [
      for (var i = 0; i < ToolboxInv.slotCount; i++)
        if (!inv.slots[i].isEmpty) StackCodec.toNbt(inv.slots[i])..putInt('Slot', i),
    ]);
    tag.putList('RawFilters', [for (final f in inv.filters) StackCodec.toNbt(f)]);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    final raw = tag.getList('Raw');
    if (raw != null) {
      for (final e in raw) {
        if (e is! NbtCompound) continue;
        final slot = e.getInt('Slot');
        if (slot == null || slot < 0 || slot >= ToolboxInv.slotCount) continue;
        inv.slots[slot] = StackCodec.fromNbt(e);
      }
      final filters = tag.getList('RawFilters');
      if (filters != null) {
        for (var i = 0; i < ToolboxInv.compartments && i < filters.length; i++) {
          final f = filters[i];
          if (f is NbtCompound) inv.filters[i] = StackCodec.fromNbt(f);
        }
      }
    }
    final ids = tag.getIntArray('UniqueId');
    if (ids != null && ids.length == 4) uniqueId = _intsToUuid(ids);
    customName = tag.getString('CustomName');
  }

  // -- Connected players ----------------------------------------------------------------

  /// `connectPlayer(slot, player, hotbarSlot)`.
  void connectPlayer(int slot, String uuid, int hotbarSlot) {
    final map = connectedPlayers.putIfAbsent(slot, () => {});
    final previous = map[uuid];
    if (previous != null) {
      if (previous == hotbarSlot) return;
      host.unequipSync(uuid, previous, false);
    }
    map[uuid] = hotbarSlot;
  }
}

List<int> _uuidToInts(String uuid) {
  final hex = uuid.replaceAll('-', '');
  int part(int i) {
    final v = int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  return [part(0), part(1), part(2), part(3)];
}

String _intsToUuid(List<int> ints) {
  final hex = [for (final i in ints) (i & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// `ToolboxHandler` + the toolbox menu and packets.
final class ToolboxHost {
  final EquipmentEnv env;

  ToolboxHost(this.env);

  /// uuid -> hotbar slot -> equipped toolbox slot (`CreateToolboxData` of the player's persistent data).
  final Map<String, Map<int, _Equip>> _equipped = {};

  /// uuid -> position of the toolbox the player has open (`containerMenu.contentHolder`).
  final Map<String, ({String worldId, P3 pos})> _openMenus = {};

  /// world id -> position -> block entity (`ToolboxHandler.toolboxes`).
  final Map<String, Map<int, ToolboxBlockEntity>> _toolboxes = {};

  String newUuid() {
    String hex(int n) => env.rng.nextInt(1 << n).toRadixString(16);
    String chunk(int digits) => List.generate(digits, (_) => hex(4)).join();
    final variant = '89ab'[env.rng.nextInt(4)];
    return '${chunk(8)}-${chunk(4)}-4${chunk(3)}-$variant${chunk(3)}-${chunk(12)}';
  }

  void install(CreateContext ctx) {
    ctx.listen(Events.playerJoin, _onJoin);
    ctx.listen(Events.playerLeave, (server, e) {
      final uuid = e.player.getId().asString;
      _equipped.remove(uuid);
      _openMenus.remove(uuid);
    });
    ctx.listen(Events.playerTick, _onPlayerTick);
    ctx.host.intercept(Events.menuClick, _onMenuClick);
    ctx.listen(Events.menuSlotChanged, _onMenuSlotChanged);
    ctx.listen(Events.menuClosed, _onMenuClosed);
    env.bus.onServerbound('create:toolbox_equip', _onEquipPacket);
    env.bus.onServerbound('create:toolbox_dispose_all', _onDisposeAll);
  }

  void _register(ToolboxBlockEntity be) {
    _toolboxes.putIfAbsent(be.worldId, () => {})[packPos(be.pos.x, be.pos.y, be.pos.z)] = be;
  }

  void _unregister(ToolboxBlockEntity be) {
    _toolboxes[be.worldId]?.remove(packPos(be.pos.x, be.pos.y, be.pos.z));
  }

  ToolboxBlockEntity? _at(String worldId, P3 pos) =>
      env.ctx.blockEntities.typed<ToolboxBlockEntity>(worldId, pos.blockPos);

  // -- range ---------------------------------------------------------------------------------

  double get maxRange => env.settings.toolboxRange.toDouble();

  /// `ToolboxHandler.withinRange`.
  bool withinRange(Player player, ToolboxBlockEntity be) {
    final world = player.getWorld();
    if (world.getId() != be.worldId) return false;
    final (x, y, z) = player.getPosition();
    final dx = x - (be.pos.x + 0.5), dy = y - be.pos.y, dz = z - (be.pos.z + 0.5);
    return dx * dx + dy * dy + dz * dz < maxRange * maxRange;
  }

  // -- player equip data ----------------------------------------------------------------------

  Future<void> _onJoin(Server server, PlayerJoinEventData e) async {
    final player = e.player;
    final uuid = player.getId().asString;
    final entity = player.asEntity();
    final map = <int, _Equip>{};
    try {
      final tree = entity.getCustomData(namespace: 'create', key: 'toolbox');
      if (tree != null) {
        final c = NbtCompound.fromTree(tree);
        for (final k in c.keys) {
          final hotbar = int.tryParse(k);
          final d = c.getCompound(k);
          final pos = d?.getIntArray('Pos');
          if (hotbar == null || d == null || pos == null || pos.length != 3) continue;
          map[hotbar] = _Equip(d.getInt('Slot') ?? 0, (pos[0], pos[1], pos[2]));
        }
      }
    } on Object catch (ex) {
      env.log.debug('toolbox data of $uuid unreadable: $ex');
    }
    _equipped[uuid] = map;
    if (map.isNotEmpty) syncData(player);
  }

  void _persist(Player player) {
    final uuid = player.getId().asString;
    final map = _equipped[uuid] ?? const {};
    final c = NbtCompound();
    for (final e in map.entries) {
      c.putCompound(
        '${e.key}',
        NbtCompound()
          ..putInt('Slot', e.value.slot)
          ..putIntArray('Pos', [e.value.pos.$1, e.value.pos.$2, e.value.pos.$3]),
      );
    }
    try {
      final entity = player.asEntity();
      if (map.isEmpty) {
        entity.removeCustomData(namespace: 'create', key: 'toolbox');
      } else {
        entity.setCustomData(namespace: 'create', key: 'toolbox', value: c.toTree());
      }
    } on Object catch (ex) {
      env.log.debug('could not persist toolbox data: $ex');
    }
  }

  /// `ToolboxHandler.syncData`: the persistent data packet the client's overlay reads.
  void syncData(Player player) {
    final map = _equipped[player.getId().asString] ?? const {};
    final data = NbtValue.compound({
      for (final e in map.entries)
        '${e.key}': NbtValue.compound({
          'Slot': NbtValue.int32(e.value.slot),
          'Pos': NbtValue.intArray([e.value.pos.$1, e.value.pos.$2, e.value.pos.$3]),
        }),
    });
    env.bus.sendClientbound('create:persistent_data', player, {
      'entityId': player.asEntity().getId(),
      'readData': NbtValue.compound({toolboxDataKey: data}),
    });
  }

  /// `ToolboxHandler.entityTick`: every second, re-connects the toolboxes of equipped hotbar slots.
  void _onPlayerTick(Server server, PlayerTickEventData e) {
    final player = e.player;
    final uuid = player.getId().asString;
    final map = _equipped[uuid];
    if (map == null || map.isEmpty) return;
    if (player.asEntity().getTicksLived() % 20 != 0) return;
    final world = player.getWorld();
    var sendData = false;
    for (final hotbar in map.keys.toList()) {
      final eq = map[hotbar]!;
      final bp = eq.pos.blockPos;
      if (!world.isLoaded(pos: bp)) continue;
      if (!world.getBlockState(pos: bp).blockName.endsWith('_toolbox')) {
        map.remove(hotbar);
        sendData = true;
        continue;
      }
      _at(world.getId(), eq.pos)?.connectPlayer(eq.slot, uuid, hotbar);
    }
    if (sendData) {
      _persist(player);
      syncData(player);
    }
  }

  /// `ToolboxHandler.unequip(player, hotbarSlot, keepItems)`.
  Future<void> unequip(Player player, int hotbarSlot, bool keepItems) async {
    final uuid = player.getId().asString;
    final map = _equipped[uuid];
    final eq = map?[hotbarSlot];
    if (map == null || eq == null) return;
    final be = _at(player.getWorld().getId(), eq.pos);
    if (be != null) {
      await _unequipOn(be, eq.slot, player, hotbarSlot, keepItems || !withinRange(player, be));
    }
    map.remove(hotbarSlot);
    _persist(player);
  }

  /// `unequip` without a player handle (a player that disconnected, or called from the entity).
  void unequipSync(String uuid, int hotbarSlot, bool keepItems) {
    final player = env.playerByUuid(uuid);
    if (player != null) unawaited(unequip(player, hotbarSlot, keepItems));
  }

  /// `ToolboxBlockEntity.unequip(slot, player, hotbarSlot, keepItems)`.
  Future<void> _unequipOn(ToolboxBlockEntity be, int slot, Player player, int hotbarSlot, bool keepItems) async {
    final map = be.connectedPlayers[slot];
    if (map == null) return;
    map.remove(player.getId().asString);
    if (keepItems) return;
    final storage = player.getInventory().asInventory();
    final host = storage.getItem(slot: hotbarSlot);
    final playerStack = await StackCodec.read(host);
    final toInsert = playerStack.isEmpty ? TStack.empty : _cleanItemNbt(playerStack);
    if (toInsert.isEmpty) return;
    final remainder = be.inv.distributeToCompartment(toInsert, slot);
    if (remainder.count != toInsert.count) {
      await _setHotbar(storage, hotbarSlot, remainder);
    }
  }

  /// `ToolboxInventory.cleanItemNBT`: a belt connector forgets its first shaft.
  TStack _cleanItemNbt(TStack s) {
    if (s.key != 'create:belt_connector') return s;
    return TStack(s.key, s.count,
        maxStack: s.maxStack, damageable: s.damageable, comps: [for (final c in s.comps) if (c.$1 != 'custom:create:belt_first_shaft') c]);
  }

  Future<void> _setHotbar(Inventory storage, int slot, TStack stack) async {
    final h = await StackCodec.write(stack);
    await storage.setItem(slot: slot, item: h);
  }

  // -- Ticking the connected players (`ToolboxBlockEntity.tickPlayers`) ----------------------------

  Future<void> _tickPlayers(ToolboxBlockEntity be) async {
    var update = false;
    for (final slot in be.connectedPlayers.keys.toList()) {
      final set = be.connectedPlayers[slot]!;
      final reference = be.inv.filters[slot];
      final clear = reference.isEmpty;
      for (final uuid in set.keys.toList()) {
        final hotbarSlot = set[uuid]!;
        final player = env.playerByUuid(uuid);
        if (player == null) {
          set.remove(uuid);
          continue;
        }
        if (!clear && !withinRange(player, be)) continue;
        final storage = player.getInventory().asInventory();
        final hostStack = storage.getItem(slot: hotbarSlot);
        final playerStack = await StackCodec.read(hostStack);
        if (clear || !playerStack.isEmpty && !canItemsShareCompartment(playerStack, reference)) {
          _equipped[uuid]?.remove(hotbarSlot);
          set.remove(uuid);
          _persist(player);
          syncData(player);
          continue;
        }
        final count = playerStack.isEmpty ? 0 : playerStack.count;
        final targetAmount = (reference.maxStack + 1) ~/ 2;
        if (count < targetAmount) {
          final amountToReplenish = targetAmount - count;
          if (_isOpenIn(uuid, be)) {
            final extracted = be.inv.takeFromCompartment(amountToReplenish, slot, simulate: true);
            if (!extracted.isEmpty) {
              await unequip(player, hotbarSlot, false);
              syncData(player);
              continue;
            }
          }
          final extracted = be.inv.takeFromCompartment(amountToReplenish, slot);
          if (!extracted.isEmpty) {
            update = true;
            final template = playerStack.isEmpty ? extracted : playerStack;
            await _setHotbar(storage, hotbarSlot, template.copyWithCount(count + extracted.count));
          }
        }
        if (count > targetAmount) {
          final amountToDeposit = count - targetAmount;
          final toDistribute = playerStack.copyWithCount(amountToDeposit);
          if (_isOpenIn(uuid, be)) {
            final deposited = amountToDeposit - be.inv.distributeToCompartment(toDistribute, slot, simulate: true).countOrZero;
            if (deposited > 0) {
              await unequip(player, hotbarSlot, true);
              syncData(player);
              continue;
            }
          }
          final deposited = amountToDeposit - be.inv.distributeToCompartment(toDistribute, slot).countOrZero;
          if (deposited > 0) {
            update = true;
            await _setHotbar(storage, hotbarSlot, playerStack.copyWithCount(count - deposited));
          }
        }
      }
      if (clear) be.connectedPlayers.remove(slot);
    }
    if (update) be.sendData();
  }

  bool _isOpenIn(String uuid, ToolboxBlockEntity be) {
    final o = _openMenus[uuid];
    return o != null && o.worldId == be.worldId && o.pos == be.pos.p3;
  }

  // -- Packets ---------------------------------------------------------------------------------

  void _onEquipPacket(Player player, Map<String, Object?> f) {
    final pos = f['toolboxPos'] as (int, int, int)?;
    final slot = f['slot'] as int;
    final hotbarSlot = f['hotbarSlot'] as int;
    unawaited(_equip(player, pos, slot, hotbarSlot));
  }

  /// `ToolboxEquipPacket.handle`.
  Future<void> _equip(Player player, P3? pos, int slot, int hotbarSlot) async {
    if (hotbarSlot < 0 || hotbarSlot > 8) return;
    if (pos == null) {
      await unequip(player, hotbarSlot, false);
      syncData(player);
      return;
    }
    final world = player.getWorld();
    final be = _at(world.getId(), pos);
    if (be == null) return;
    final (px, py, pz) = player.getPosition();
    final dx = px - (pos.$1 + 0.5), dy = py - pos.$2, dz = pz - (pos.$3 + 0.5);
    if (dx * dx + dy * dy + dz * dz > maxRange * maxRange) return;
    await unequip(player, hotbarSlot, false);
    if (slot < 0 || slot >= 8) {
      syncData(player);
      return;
    }
    final storage = player.getInventory().asInventory();
    final playerStack = await StackCodec.read(storage.getItem(slot: hotbarSlot));
    if (!playerStack.isEmpty && !canItemsShareCompartment(playerStack, be.inv.filters[slot])) {
      var remainder = TStack.empty;
      be.inv.inLimitedMode(() => remainder = be.inv.insertStacked(playerStack));
      if (!remainder.isEmpty) remainder = await _insertIntoPlayer(player, remainder, mainOnly: true);
      if (remainder.isEmpty ? true : remainder.count != playerStack.count) {
        await _setHotbar(storage, hotbarSlot, remainder);
      }
    }
    final map = _equipped.putIfAbsent(player.getId().asString, () => {});
    map[hotbarSlot] = _Equip(slot, pos);
    _persist(player);
    be.connectPlayer(slot, player.getId().asString, hotbarSlot);
    syncData(player);
  }

  /// `ItemReturnInvWrapper`: stacked insert into the player's main inventory (not the hotbar).
  Future<TStack> _insertIntoPlayer(Player player, TStack stack, {required bool mainOnly}) async {
    final storage = player.getInventory().asInventory();
    var rest = stack;
    final start = mainOnly ? 9 : 0;
    final size = math.min(storage.getSize(), 36);
    // merge pass
    for (var i = start; i < size && !rest.isEmpty; i++) {
      final cur = await StackCodec.read(storage.getItem(slot: i));
      if (cur.isEmpty || !cur.sameItemSameComponents(rest) || cur.count >= cur.maxStack) continue;
      final moved = math.min(rest.count, cur.maxStack - cur.count);
      await _setHotbar(storage, i, cur.copyWithCount(cur.count + moved));
      rest = moved >= rest.count ? TStack.empty : rest.copyWithCount(rest.count - moved);
    }
    for (var i = start; i < size && !rest.isEmpty; i++) {
      final cur = storage.getItem(slot: i);
      if (cur != null) continue;
      final moved = math.min(rest.count, rest.maxStack);
      await _setHotbar(storage, i, rest.copyWithCount(moved));
      rest = moved >= rest.count ? TStack.empty : rest.copyWithCount(rest.count - moved);
    }
    return rest;
  }

  void _onDisposeAll(Player player, Map<String, Object?> f) {
    final pos = f['toolboxPos'] as (int, int, int);
    unawaited(_disposeAll(player, pos));
  }

  /// `ToolboxDisposeAllPacket.handle`: puts everything the player carries that fits into the toolbox.
  Future<void> _disposeAll(Player player, P3 pos) async {
    final world = player.getWorld();
    final be = _at(world.getId(), pos);
    if (be == null) return;
    final (px, py, pz) = player.getPosition();
    final dx = px - (pos.$1 + 0.5), dy = py - pos.$2, dz = pz - (pos.$3 + 0.5);
    if (dx * dx + dy * dy + dz * dz > maxRange * maxRange) return;
    var sendData = false;
    final map = _equipped[player.getId().asString];
    final storage = player.getInventory().asInventory();
    for (var i = 0; i < 36; i++) {
      final eq = map?[i];
      if (eq != null && eq.pos == pos) {
        await unequip(player, i, true);
        sendData = true;
      }
      final t = await StackCodec.read(storage.getItem(slot: i));
      if (t.isEmpty) continue;
      var remainder = t;
      be.inv.inLimitedMode(() => remainder = be.inv.insertStacked(t));
      if (remainder.isEmpty ? true : remainder.count != t.count) await _setHotbar(storage, i, remainder);
    }
    if (sendData) syncData(player);
  }

  // -- Menu ------------------------------------------------------------------------------------

  /// Slot rules for the vanilla parts of the menu (shift-clicks from the player's inventory):
  /// a compartment with a filter only takes that item.
  MenuClickRules _rules(ToolboxBlockEntity be) => MenuClickRules(
    slotRules: [
      for (var i = 0; i < ToolboxInv.slotCount; i++)
        if (!be.inv.filters[i ~/ ToolboxInv.stacksPerCompartment].isEmpty)
          MenuSlotRule(
            slot: i,
            kind: MenuSlotKindFilter([be.inv.filters[i ~/ ToolboxInv.stacksPerCompartment].key]),
            maxStackSize: null,
          ),
    ],
    quickMoveTargets: const [MenuSlotRange(start: 0, end: ToolboxInv.slotCount)],
  );

  /// Opens the menu of [be] for [player] (`player.openMenu(toolbox, toolbox::sendToMenu)`).
  Future<void> openMenu(Player player, ToolboxBlockEntity be) async {
    final client = NbtCompound();
    be.write(client, clientPacket: true);
    final extra = PacketBuffer.encode((w) {
      w.writeLong(packPos(be.pos.x, be.pos.y, be.pos.z));
      NetworkNbt.write(w, nbtCompoundToValue(client));
    });
    final world = player.getWorld();
    final blockKey = world.getBlockState(pos: be.pos).blockName;
    final title = be.customName != null
        ? TextComponent.text(plain: be.customName!)
        : TextComponent.translate(key: 'block.${blockKey.replaceFirst(':', '.')}', with_: const []);
    final result = raw.menus.openMenuWithOptions(
      player: player,
      menuTypeKey: toolboxMenuType,
      title: title,
      extraData: extra,
      slotCount: ToolboxInv.slotCount,
      options: MenuOptions(applyVanillaClicks: true, playerInventory: true, rules: _rules(be)),
    );
    if (result is ErrorResult) {
      env.log.warn('Could not open the toolbox menu: ${(result as ErrorResult).value}');
      return;
    }
    _openMenus[player.getId().asString] = (worldId: be.worldId, pos: be.pos.p3);
    be.openCount++;
    be.sendData();
    await _fillMenu(player, be);
  }

  Future<void> _fillMenu(Player player, ToolboxBlockEntity be) async {
    for (var i = 0; i < ToolboxInv.slotCount; i++) {
      final host = await StackCodec.write(be.inv.slots[i]);
      try {
        if (host == null) {
          player.clearPluginMenuSlot(i);
        } else {
          player.setPluginMenuSlot(i, host);
        }
      } on Object catch (ex) {
        env.log.debug('toolbox menu slot $i: $ex');
      }
    }
    try {
      raw.menus.setMenuClickRules(player: player, rules: _rules(be));
    } on Object {
      // the menu closed meanwhile
    }
  }

  Future<void> _refreshViewers(ToolboxBlockEntity be) async {
    for (final e in _openMenus.entries.toList()) {
      if (e.value.worldId != be.worldId || e.value.pos != be.pos.p3) continue;
      final p = env.playerByUuid(e.key);
      if (p != null) await _fillMenu(p, be);
    }
  }

  Future<MenuClickEventData> _onMenuClick(Server server, MenuClickEventData e) async {
    if (e.menuType != toolboxMenuType) return e;
    final uuid = e.player.getId().asString;
    final open = _openMenus[uuid];
    if (open == null) return e;
    final be = _at(open.worldId, open.pos);
    if (be == null) return e.copyWith(cancelled: true);
    final slot = e.slot;
    final onToolbox = slot >= 0 && slot < ToolboxInv.slotCount;
    // `canDragTo`: no dragging into the toolbox slots.
    if (e.mode == MenuClickMode.quickCraft) {
      return e.changedSlots.any((s) => s.slot < ToolboxInv.slotCount) ? e.copyWith(cancelled: true) : e;
    }
    if (!onToolbox) return e;
    switch (e.mode) {
      case MenuClickMode.pickup:
        await _pickupClick(e.player, be, slot, e.button, e.cursorStack);
      case MenuClickMode.quickMove:
        await _quickMoveOut(e.player, be, slot);
      default:
        break;
    }
    return e.copyWith(cancelled: true);
  }

  /// `ToolboxMenu.clicked` for a left / right click on a toolbox slot.
  Future<void> _pickupClick(Player player, ToolboxBlockEntity be, int slotIn, int button, ItemStack? cursorHost) async {
    final inv = be.inv;
    var slot = slotIn;
    var carried = await StackCodec.read(cursorHost);
    final clicked = inv.slots[slot];
    if (!carried.isEmpty && !clicked.isEmpty && canItemsShareCompartment(clicked, carried)) {
      final sub = slot % ToolboxInv.stacksPerCompartment;
      if (sub != ToolboxInv.stacksPerCompartment - 1) slot = slot - sub + ToolboxInv.stacksPerCompartment - 1;
    }
    if (carried.isEmpty && clicked.isEmpty) {
      // an empty click on an empty slot clears the compartment's filter
      inv.filters[slot ~/ ToolboxInv.stacksPerCompartment] = TStack.empty;
      be.sendData();
      await _refreshViewers(be);
      return;
    }
    final slotStack = inv.slots[slot];
    if (carried.isEmpty) {
      if (slotStack.isEmpty) return;
      if (inv.extractItem(slot, 1, simulate: true).isEmpty) return;
      final amount = button == 0 ? slotStack.count : (slotStack.count + 1) ~/ 2;
      carried = inv.extractItem(slot, amount);
    } else {
      final place = button == 0 ? carried.count : 1;
      if (slotStack.isEmpty || slotStack.sameItemSameComponents(carried)) {
        final remainder = inv.insertItem(slot, carried.copyWithCount(place));
        final placed = place - remainder.countOrZero;
        final left = carried.count - placed;
        carried = left <= 0 ? TStack.empty : carried.copyWithCount(left);
      }
      // a different item in a filtered compartment is refused (`mayPlace` is false)
    }
    final host = await StackCodec.write(carried);
    try {
      raw.menus.setMenuCursor(player: player, stack: host);
    } on Object {
      // the menu closed
    }
    be.sendData();
    await _refreshViewers(be);
  }

  /// `quickMoveStack` out of the toolbox: everything in the slot goes to the player's inventory
  /// (hotbar last slot first), merging into matching stacks.
  Future<void> _quickMoveOut(Player player, ToolboxBlockEntity be, int slot) async {
    final inv = be.inv;
    final stack = inv.slots[slot];
    if (stack.isEmpty) return;
    var rest = stack;
    final storage = player.getInventory().asInventory();
    final order = [for (var i = 8; i >= 0; i--) i, for (var i = 35; i >= 9; i--) i];
    for (final i in order) {
      if (rest.isEmpty) break;
      final cur = await StackCodec.read(storage.getItem(slot: i));
      if (cur.isEmpty || !cur.sameItemSameComponents(rest) || cur.count >= cur.maxStack) continue;
      final moved = math.min(rest.count, cur.maxStack - cur.count);
      await _setHotbar(storage, i, cur.copyWithCount(cur.count + moved));
      rest = moved >= rest.count ? TStack.empty : rest.copyWithCount(rest.count - moved);
    }
    for (final i in order) {
      if (rest.isEmpty) break;
      if (storage.getItem(slot: i) != null) continue;
      final moved = math.min(rest.count, rest.maxStack);
      await _setHotbar(storage, i, rest.copyWithCount(moved));
      rest = moved >= rest.count ? TStack.empty : rest.copyWithCount(rest.count - moved);
    }
    final taken = stack.count - rest.countOrZero;
    if (taken > 0) inv.extractItem(slot, taken);
    be.sendData();
    await _refreshViewers(be);
  }

  /// Vanilla handled clicks (shift-click from the player's inventory, hotbar swaps): mirror the
  /// toolbox slots that changed and settle the compartments.
  Future<void> _onMenuSlotChanged(Server server, MenuSlotChangedEventData e) async {
    if (e.menuType != toolboxMenuType) return;
    final open = _openMenus[e.player.getId().asString];
    if (open == null) return;
    final be = _at(open.worldId, open.pos);
    if (be == null) return;
    final touched = <int>{};
    for (final c in e.changes) {
      if (c.slot < 0 || c.slot >= ToolboxInv.slotCount) continue;
      final t = await StackCodec.read(c.stack);
      be.inv.slots[c.slot] = t;
      final comp = c.slot ~/ ToolboxInv.stacksPerCompartment;
      if (!t.isEmpty && be.inv.filters[comp].isEmpty) be.inv.filters[comp] = t.copyWithCount(1);
      touched.add(comp);
    }
    for (final comp in touched) {
      be.inv.settle(comp);
    }
    be.sendData();
    await _refreshViewers(be);
  }

  void _onMenuClosed(Server server, MenuClosedEventData e) {
    if (e.menuType != toolboxMenuType) return;
    final uuid = e.player.getId().asString;
    final open = _openMenus.remove(uuid);
    if (open == null) return;
    final be = _at(open.worldId, open.pos);
    if (be != null) {
      be.openCount = math.max(0, be.openCount - 1);
      be.sendData();
    }
  }

  // -- Block --------------------------------------------------------------------------------------

  /// `ToolboxBlock.attack`: breaking the box returns it to the player with its contents.
  Future<void> collectBox(Player player, World world, ToolboxBlockEntity be, String blockKey) async {
    // `unequipTracked()`
    final affected = <String>{};
    for (final set in be.connectedPlayers.values) {
      for (final e in set.entries) {
        final p = env.playerByUuid(e.key);
        if (p != null) {
          await unequip(p, e.value, false);
          affected.add(e.key);
        }
      }
    }
    for (final uuid in affected) {
      final p = env.playerByUuid(uuid);
      if (p != null) syncData(p);
    }
    be.connectedPlayers.clear();
    final stack = await itemWithData(be, blockKey);
    await world.destroyBlock(pos: be.pos, drop: false, player: null, withParticles: true);
    if (stack != null) {
      await giveItem(player, world, stack);
    }
  }

  Future<void> giveItem(Player player, World world, ItemStack stack) async {
    final storage = player.getInventory().asInventory();
    final size = math.min(storage.getSize(), 36);
    for (var i = 0; i < size; i++) {
      if (storage.getItem(slot: i) == null) {
        await storage.setItem(slot: i, item: stack);
        return;
      }
    }
    await world.dropItem(player.getPosition(), stack);
  }

  /// `getCloneItemStack`: the toolbox item with its inventory, uuid and name components.
  Future<ItemStack?> itemWithData(ToolboxBlockEntity be, String blockKey) async {
    final stack = ItemStack.create(registryKey: blockKey, count: 1);
    be.uniqueId ??= newUuid();
    final data = ToolboxInventoryDataBridge.toData(be.inv, env.itemIds);
    if (data != null) {
      stack.setCustomComponent('create:toolbox_inventory', data);
    }
    stack.setCustomComponent('create:toolbox_uuid', PacketBuffer.encode((w) => w.writeUuid(be.uniqueId!)));
    final name = be.customName;
    if (name != null) await stack.setCustomName(name: TextComponent.text(plain: name));
    return stack;
  }

  /// `setPlacedBy`: inventory, uuid and name from the placed toolbox item.
  Future<void> applyItemData(ToolboxBlockEntity be, ItemStack held, EquipmentEnv env) async {
    final inv = held.customComponent('create:toolbox_inventory');
    if (inv != null) {
      try {
        await ToolboxInventoryDataBridge.fromData(inv, be.inv, env.itemIds, (key) async {
          final probe = ItemStack.create(registryKey: key, count: 1);
          final max = await probe.getMaxCount();
          var damageable = false;
          for (final c in await probe.getComponents()) {
            if (c.component == DataComponent.maxDamage) damageable = true;
          }
          return (max: max, damageable: damageable);
        });
      } on Object catch (e) {
        env.log.warn('toolbox contents unreadable: $e');
      }
    }
    final uuid = held.customComponent('create:toolbox_uuid');
    if (uuid != null) {
      try {
        be.uniqueId = EquipmentWire.readUuid(uuid);
      } on Object {
        // keeps the fresh one
      }
    }
    final name = await held.getCustomName();
    if (name != null) be.customName = name.getText();
    be.sendData();
  }

  /// Dyeing a toolbox: the block changes colour and keeps its contents.
  Future<void> recolor(World world, BlockPos pos, ToolboxBlockEntity old, String newBlock) async {
    final state = world.getBlockState(pos: pos);
    final id = BlockRegistry.resolveState(newBlock, {for (final (k, v) in state.properties) k: v});
    if (id == null) return;
    final keep = (inv: old.inv, uuid: old.uniqueId, name: old.customName);
    await world.setBlockState(pos: pos, state: id, updateFlags: BlockUpdateFlags.normal);
    final nb = env.ctx.blockEntities.typed<ToolboxBlockEntity>(world.getId(), pos) ??
        env.ctx.blockEntities.createAt(world, pos, toolboxBlockEntityType) as ToolboxBlockEntity?;
    if (nb == null) return;
    if (!identical(nb, old)) {
      nb.inv.copyFrom(keep.inv);
      nb.uniqueId = keep.uuid;
      nb.customName = keep.name;
    }
    nb.sendData();
  }
}

extension on TStack {
  int get countOrZero => isEmpty ? 0 : count;
}
