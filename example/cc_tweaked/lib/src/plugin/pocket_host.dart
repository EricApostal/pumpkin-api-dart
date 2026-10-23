// The plugin side of the `pocket` API: the holder's inventory, the upgrade
// components of the pocket computer's item, and the peripheral an upgrade
// brings (`PocketAPI`, `PocketBrain.UpgradeAccess`, `Upgrades.get` in CC:
// Tweaked's `shared/pocket`, mc-26.3).
//
// The machine layer (`machine/api/pocket_api.dart`) queues a request and waits
// for a `pocket_response`; this is what runs the request, from the plugin tick,
// where the host's calls are allowed.
import 'dart:collection';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/api/pocket_api.dart';
import '../machine/peripherals.dart' show WirelessModem;
import '../machine/side.dart';
import '../protocol/components.dart';
import '../protocol/datapack_registries.dart';
import 'service.dart';

/// One entry of `computercraft:pocket_upgrade`.
final class PocketUpgrade {
  /// `computercraft:speaker`, `computercraft:wireless_modem_normal`, ...
  final String key;

  /// Its id: the position in the registry the client was sent
  /// (`RegistryDataLoader` numbers the entries of `registry_data` in order, and
  /// `ByteBufCodecs.holderRegistry` writes that id into the item component).
  final int id;

  /// The upgrade's type: `computercraft:speaker`, `computercraft:wireless_modem`
  /// (`IPocketUpgrade.getType`, the `type` field of the entry).
  final String type;

  /// The item the upgrade is crafted from (`getCraftingItem`, the `item` field
  /// of the entry): the item found in a player's inventory is this one.
  final String item;

  /// A `computercraft:wireless_modem` with `"advanced": true`.
  final bool advancedModem;

  const PocketUpgrade({
    required this.key,
    required this.id,
    required this.type,
    required this.item,
    this.advancedModem = false,
  });

  /// `PocketModem.CODEC` / `PocketSpeaker.CODEC` as the entry's JSON.
  factory PocketUpgrade.fromEntry(DatapackEntry entry, int id) => PocketUpgrade(
    key: entry.key,
    id: id,
    type: entry.type,
    item: entry.json['item'] is String ? entry.json['item']! as String : '',
    advancedModem: entry.json['advanced'] == true,
  );

  /// Whether this upgrade's peripheral is a wireless modem (`PocketModem`).
  bool get isModem => type == 'computercraft:wireless_modem';

  /// Whether this upgrade's peripheral is a speaker (`PocketSpeaker`).
  bool get isSpeaker => type == 'computercraft:speaker';

  @override
  String toString() => 'PocketUpgrade($key)';
}

/// The pocket upgrades of the registry, in id order.
final class PocketUpgrades {
  final List<PocketUpgrade> all;

  PocketUpgrades(this.all);

  factory PocketUpgrades.of(DatapackRegistry registry) =>
      PocketUpgrades([for (var i = 0; i < registry.entries.length; i++) PocketUpgrade.fromEntry(registry.entries[i], i)]);

  PocketUpgrade? byId(int id) => id >= 0 && id < all.length ? all[id] : null;

  /// `Upgrades.get`: the upgrade whose crafting item is [item], or null.
  ///
  /// The built-in upgrades carry no extra data (`UpgradeData.ofDefault`), so the
  /// item alone identifies them; a stack's components are not compared.
  PocketUpgrade? forItem(String item) {
    for (final upgrade in all) {
      if (upgrade.item == item) return upgrade;
    }
    return null;
  }
}

/// Where the pocket computer's item is in the holder's inventory.
final class _Holder {
  final Player player;

  /// The 36 main slots (`PlayerInventory.asInventory`).
  final Inventory inventory;

  /// The slot the item is in, or -1 for the off hand.
  final int slot;

  final bool offhand;

  const _Holder(this.player, this.inventory, this.slot, {this.offhand = false});
}

/// A request the Lua program queued.
final class _Request {
  final int id;
  final PocketSide side;

  /// `true` for `equipBack`/`equipTop`, `false` for the unequip ones.
  final bool equip;

  const _Request(this.id, this.side, this.equip);
}

/// The `pocket` host of one pocket computer.
final class CcPocketHost implements PocketHost {
  final CcService _service;
  final PocketUpgrades upgrades;
  final int computerId;

  /// The most requests that may wait for a tick (`TurtleBrain` uses 16 for its
  /// commands; Java's pocket methods cannot queue at all).
  static const int maxPending = 16;

  @override
  void Function(String name, List<Object?> args)? queueEvent;

  final Queue<_Request> _queue = Queue();
  int _next = 0;

  CcPocketHost(this._service, this.computerId, this.upgrades);

  @override
  int? equip(PocketSide side) => _enqueue(side, true);

  @override
  int? unequip(PocketSide side) => _enqueue(side, false);

  int? _enqueue(PocketSide side, bool equip) {
    if (_queue.length >= maxPending) return null;
    final id = _next++;
    _queue.add(_Request(id, side, equip));
    return id;
  }

  /// Runs the requests queued since the last tick. Called from the plugin tick:
  /// the host's calls are only allowed there.
  Future<void> serve(Server server) async {
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      var ok = false;
      String? reason;
      try {
        final result = request.equip ? await _equip(server, request.side) : await _unequip(server, request.side);
        ok = result.$1;
        reason = result.$2;
      } on Object catch (e) {
        reason = '$e';
      }
      queueEvent?.call('pocket_response', [request.id.toDouble(), ok, reason]);
    }
  }

  /// Whether a request is still waiting (the tick skips the host calls then).
  bool get hasPending => _queue.isNotEmpty;

  /// Attaches the peripherals of the upgrades [item] carries.
  ///
  /// Java's `PocketBrain` follows its holder: the item is the source of truth
  /// for what is equipped, so the peripherals are (re)created from it. The port
  /// learns the item when a player uses the computer (`_usePocket`), which is
  /// the call that needs it for `peripheral.getType`.
  void attachFromItem(ItemStack item) {
    for (final side in PocketSide.values) {
      _attachPeripheral(side, _upgradeOf(item, side));
    }
  }

  void _attachPeripheral(PocketSide side, PocketUpgrade? upgrade) {
    final computerSide = _computerSide(side);
    if (upgrade == null) {
      _service.detachExternal(computerId, computerSide);
      return;
    }
    if (upgrade.isModem) {
      _service.attachExternal(
        computerId,
        computerSide,
        WirelessModem(network: _service.wireless, advanced: upgrade.advancedModem),
      );
      return;
    }
    // `PocketSpeaker` in Java. The speaker peripheral of this port
    // (`SpeakerPeripheral`) is built on a plugin side `SpeakerSink`, which the
    // world peripherals own; a pocket speaker gets its peripheral once that
    // sink can be created for a computer with no block. The upgrade itself is
    // still equipped on the item, which is what `pocket.equipBack` promises.
  }

  // -- `PocketAPI` ------------------------------------------------------------------

  /// `PocketAPI.equip`: finds another upgrade in the holder's inventory and
  /// puts it on [side], giving the old one back.
  Future<(bool, String?)> _equip(Server server, PocketSide side) async {
    final holder = await _findHolder(server);
    if (holder == null) return (false, 'Cannot find player');
    try {
      final item = _itemOf(holder);
      if (item == null) return (false, 'Cannot find player');
      final previous = _upgradeOf(item, side);

      final found = await _findUpgrade(holder, previous);
      if (found == null) return (false, 'Cannot find a valid upgrade');

      // Remove the current upgrade (`storeItem`), then set the new one.
      if (previous != null) await _storeItem(server, holder, previous.item);
      _setUpgrade(item, side, found);
      await _writeItem(holder, item);
      _attachPeripheral(side, found);
      return (true, null);
    } finally {
      holder.player.dispose();
    }
  }

  /// `PocketAPI.unequip`: takes the upgrade out of [side] and gives its item
  /// back to the holder.
  Future<(bool, String?)> _unequip(Server server, PocketSide side) async {
    final holder = await _findHolder(server);
    if (holder == null) return (false, 'Cannot find player');
    try {
      final item = _itemOf(holder);
      if (item == null) return (false, 'Cannot find player');
      final previous = _upgradeOf(item, side);
      if (previous == null) return (false, 'Nothing to unequip');

      _setUpgrade(item, side, null);
      await _writeItem(holder, item);
      await _storeItem(server, holder, previous.item);
      _attachPeripheral(side, null);
      return (true, null);
    } finally {
      holder.player.dispose();
    }
  }

  /// The stack of the pocket computer in [holder]'s inventory.
  ItemStack? _itemOf(_Holder holder) => holder.offhand
      ? holder.player.getInventory().getOffHand()
      : holder.inventory.getItem(slot: holder.slot);

  /// Writes the stack back: the item's components are the upgrade state, so the
  /// inventory slot (or the off hand) gets the changed stack.
  Future<void> _writeItem(_Holder holder, ItemStack item) async {
    final inventory = holder.player.getInventory();
    if (holder.offhand) {
      await inventory.setOffHand(item: item);
    } else {
      await holder.inventory.setItem(slot: holder.slot, item: item);
    }
  }

  /// `PocketAPI.findUpgrade`: searches the 36 main slots from the selected one
  /// (so the held slots are preferred), then the off hand, and consumes one item
  /// from the first stack that is an upgrade other than [previous].
  Future<PocketUpgrade?> _findUpgrade(_Holder holder, PocketUpgrade? previous) async {
    final inventory = holder.player.getInventory();
    final size = holder.inventory.getSize();
    final selected = inventory.getSelectedSlot();
    for (var i = 0; i < size; i++) {
      final upgrade = await _takeUpgradeAt(holder.inventory, (i + selected) % size, previous);
      if (upgrade != null) return upgrade;
    }
    final offHand = inventory.getOffHand();
    if (offHand != null) {
      final upgrade = upgrades.forItem(await offHand.getRegistryKey());
      if (upgrade != null && upgrade.id != previous?.id) {
        final count = await offHand.getCount();
        await inventory.setOffHand(item: count > 1 ? (offHand..setCount(count: count - 1)) : null);
        return upgrade;
      }
    }
    return null;
  }

  Future<PocketUpgrade?> _takeUpgradeAt(Inventory storage, int slot, PocketUpgrade? previous) async {
    final stack = storage.getItem(slot: slot);
    if (stack == null) return null;
    final upgrade = upgrades.forItem(await stack.getRegistryKey());
    if (upgrade == null || upgrade.id == previous?.id) return null;
    final count = await stack.getCount();
    await storage.setItem(slot: slot, item: count > 1 ? (stack..setCount(count: count - 1)) : null);
    return upgrade;
  }

  /// `PocketAPI.storeItem`: gives the upgrade's item back to the player, or
  /// drops it at their feet when their inventory is full (`player.drop`).
  Future<void> _storeItem(Server server, _Holder holder, String itemKey) async {
    if (itemKey.isEmpty) return;
    final stack = ItemStacks.plain(itemKey);
    if (await holder.inventory.give(stack)) return;
    final player = holder.player;
    final world = player.getWorld();
    try {
      final pos = player.getPosition();
      await world.dropItem((pos.$1, pos.$2 + 1.0, pos.$3), stack, pickupDelay: 0);
    } on HostException catch (e) {
      logger.warn('Could not drop the pocket upgrade $itemKey: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  // -- The holder and the components --------------------------------------------------

  /// The player holding this pocket computer: the one whose inventory has a
  /// stack with its `computer_id` (`PocketHolder.EntityHolder`). Java keeps a
  /// holder reference; the item is the source of truth here, so the holder is
  /// found again on every call, which also covers the item changing hands.
  Future<_Holder?> _findHolder(Server server) async {
    for (final player in server.getAllPlayers()) {
      final inventory = player.getInventory();
      final storage = inventory.asInventory();
      final items = storage.getAllItems();
      for (var i = 0; i < items.length; i++) {
        final stack = items[i];
        if (stack != null && _idOf(stack) == computerId) return _Holder(player, storage, i);
      }
      final offHand = inventory.getOffHand();
      if (offHand != null && _idOf(offHand) == computerId) {
        return _Holder(player, storage, -1, offhand: true);
      }
      player.dispose();
    }
    return null;
  }

  /// The `computercraft:computer_id` of [stack], or null.
  int? _idOf(ItemStack stack) {
    final bytes = stack.customComponent(CcComponents.computerId);
    if (bytes == null) return null;
    try {
      return CcComponents.decodeComputerId(bytes);
    } on PacketException {
      return null;
    }
  }

  /// The upgrade in [side]'s slot of [item] (`UpgradeAccess.getUpgrade`), or
  /// null when the slot is empty.
  PocketUpgrade? _upgradeOf(ItemStack item, PocketSide side) {
    final bytes = item.customComponent(_component(side));
    if (bytes == null) return null;
    try {
      return upgrades.byId(PacketReader(bytes).readVarInt());
    } on PacketException {
      return null;
    }
  }

  /// `UpgradeAccess.setUpgrade`: writes the upgrade (and its data, always empty
  /// for the built-in upgrades) into the item, or removes the component.
  void _setUpgrade(ItemStack item, PocketSide side, PocketUpgrade? upgrade) {
    if (upgrade == null) {
      item.removeCustomComponent(_component(side));
      return;
    }
    item.setCustomComponent(
      _component(side),
      PacketBuffer.encode((w) => w..writeVarInt(upgrade.id)..writeByte(0)..writeByte(0)),
    );
  }

  static String _component(PocketSide side) =>
      side == PocketSide.top ? CcComponents.topPocketUpgrade : CcComponents.backPocketUpgrade;

  /// `PocketSide` as the side of the computer (`PocketBrain.java:51-52`).
  static ComputerSide _computerSide(PocketSide side) =>
      side == PocketSide.top ? ComputerSide.top : ComputerSide.back;
}