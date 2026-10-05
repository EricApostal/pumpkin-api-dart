// Computers in the world: the block entities of the computer blocks, the right
// click that opens a computer's GUI, pocket computers, the block state that
// shows whether a computer is off, on or blinking, and the item a broken
// computer drops.
//
// It mirrors `AbstractComputerBlock`, `ComputerBlock` and
// `AbstractComputerBlockEntity` (shared/computer/blocks, mc-26.3):
//
// * `ComputerId` (int), `Label` (string), `On` (bool) are the save data of the
//   entity (`saveAdditional`); `Capacity` and `TerminalSize` are kept when
//   they are there. The entity has no client data (no `getUpdateTag`): the
//   look of a computer is its `state` block state property.
// * a computer id is created when the computer is first used (`serverTick`
//   calls `createServerComputer` once there is something to run, the use of the
//   block does at the latest), or restored from the `computer_id` component of
//   the item it was placed from.
// * `useWithoutItem`: a click without sneaking opens the menu.
// * `updateBlockState`: `state` follows `ServerComputer.getState`.
//
// Nothing here has run against a host or a client: see docs/host-requirements.md.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/computer.dart';
import '../protocol/components.dart';
import 'block_states.dart';
import 'commands.dart' show CcPermissions;
import 'network.dart';
import 'records.dart';
import 'service.dart';

/// The computer blocks and the family of their machine. The command computer
/// has a block entity too, but runs as an advanced computer without the
/// `commands` API and is not opened (its menu is for operators).
const Map<String, ComputerFamily> _computerBlocks = {
  'computercraft:computer_normal': ComputerFamily.normal,
  'computercraft:computer_advanced': ComputerFamily.advanced,
  'computercraft:computer_command': ComputerFamily.advanced,
};

/// The pocket computer items.
const Map<String, ComputerFamily> _pocketItems = {
  'computercraft:pocket_computer_normal': ComputerFamily.normal,
  'computercraft:pocket_computer_advanced': ComputerFamily.advanced,
};

String _pathOf(String key) => key.substring(key.indexOf(':') + 1);

/// A computer block with its entity, as the plugin tracks it.
final class _Placed {
  final ComputerLocation location;
  final String blockKey;

  /// The `save-data` of the entity: kept so that keys the plugin does not know
  /// (`Capacity`, `TerminalSize`, `Lock`) survive a rewrite.
  final NbtCompound data;
  int? computerId;
  String? label;
  bool on;

  /// The `state` property last written to the block.
  ComputerState shown = ComputerState.off;

  _Placed(this.location, this.blockKey, this.data, {this.computerId, this.label, this.on = false});

  ComputerFamily get family => _computerBlocks[blockKey] ?? ComputerFamily.advanced;
}

/// What the player was about to place: read from the item when the use event
/// fires, consumed by the place event right after.
final class _PendingPlacement {
  final String blockKey;
  final int? computerId;
  final String? label;
  final int tick;

  const _PendingPlacement(this.blockKey, this.computerId, this.label, this.tick);
}

/// A computer block that was just removed, for the drop event that may follow.
final class _Removed {
  final String blockKey;
  final int? computerId;
  final String? label;
  final int tick;

  const _Removed(this.blockKey, this.computerId, this.label, this.tick);
}

final class CcWorldComputers {
  final CcService _service;
  final CcNetwork _network;
  final CcBlockStates _states;

  final Map<String, _Placed> _placed = {};
  final Map<String, _PendingPlacement> _pending = {};
  final Map<String, _Removed> _removed = {};
  final Map<String, int> _lastPocketOpen = {};
  int _tick = 0;

  CcWorldComputers(this._service, this._network, this._states);

  /// Number of computer blocks with an entity the plugin tracks.
  int get placedCount => _placed.length;

  static String _key(ComputerLocation l) => '${l.world}|${l.x}|${l.y}|${l.z}';

  static BlockPos _pos(ComputerLocation l) => BlockPos(x: l.x, y: l.y, z: l.z);

  static ComputerLocation _location(String world, BlockPos pos) => ComputerLocation(world, pos.x, pos.y, pos.z);

  /// Listens for the events that drive computer blocks and pocket computers.
  void install(Context context) {
    context.intercept(Events.playerUseItem, _onUseItem);
    context.intercept(Events.playerUseBlock, _onUseBlock);
    context.listen(Events.blockPlace, _onBlockPlace);
    context.intercept(Events.blockDropItem, _onDropItem);
    context.listen(Events.blockEntityLoad, _onEntityLoad);
    context.listen(Events.blockEntityUnload, _onEntityUnload);
  }

  // -- The right click on a computer ------------------------------------------------

  PlayerUseBlockEventData _onUseBlock(Server server, PlayerUseBlockEventData event) {
    // `AbstractComputerBlock.useWithoutItem`: `!player.isCrouching()`.
    if (event.sneaking || !_computerBlocks.containsKey(event.block)) return event;
    final player = event.player;
    final world = player.getWorld();
    try {
      final location = _location(world.getId(), event.blockPos);
      final placed = _placed[_key(location)] ?? _adopt(world, location, event.block);
      if (placed == null) {
        player.send('&cThis computer has no block entity and could not get one.');
      } else {
        _open(server, player, placed);
      }
    } finally {
      world.dispose();
    }
    return event.cancel();
  }

  /// Gives a computer block that has no tracked entity one: its entity data
  /// from the chunk if there is one (a load event that was missed), else an
  /// empty one (the block was placed by a command or world edit).
  _Placed? _adopt(World world, ComputerLocation location, String blockKey) {
    try {
      final existing = world.pluginBlockEntityAt(_pos(location));
      if (existing != null) return _attach(location, existing.typeKey, existing.save);
      final data = NbtCompound()..putBool('On', false);
      world.setPluginBlockEntity(_pos(location), blockKey, data);
      return _attach(location, blockKey, data);
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the block entity of $blockKey at $location: ${e.message}');
      return null;
    }
  }

  /// `useWithoutItem` for a computer: makes sure there is a computer, turns it
  /// on and opens the menu.
  void _open(Server server, Player player, _Placed placed) {
    if (placed.blockKey == 'computercraft:computer_command') {
      player.send('&eCommand computers are not supported yet (no `commands` API).');
      return;
    }
    final computer = _ensureComputer(server, player, placed);
    if (computer == null) return;
    final containerId = _network.open(
      player,
      computer,
      itemName: _pathOf(placed.blockKey),
      at: placed.location,
    );
    if (containerId == null) {
      player.send('&cThe CC: Tweaked client mod is needed to open this computer (NeoForge handshake missing).');
    }
  }

  /// The machine of a computer block, created with the next free id when the
  /// block has none yet (the id is written to the entity).
  Computer? _ensureComputer(Server server, Player player, _Placed placed) {
    final id = placed.computerId;
    if (id != null) {
      return _service.computer(id) ??
          _service.resumeAt(id, placed.location, family: placed.family, label: placed.label, on: placed.on);
    }
    final owner = player.getId().asString;
    final limit = _service.pluginConfig.maxComputersPerPlayer;
    if (limit > 0 && _service.countOwnedBy(owner) >= limit && !player.hasPermission(node: CcPermissions.admin)) {
      player.send('&cYou can own at most $limit computers.');
      return null;
    }
    final computer = _service.create(family: placed.family, owner: owner, ownerName: player.getName());
    _service.resumeAt(computer.id, placed.location, family: placed.family, on: false);
    placed.computerId = computer.id;
    _writeEntity(server, placed);
    return computer;
  }

  // -- Pocket computers (`PocketComputerItem.use`) ----------------------------------

  PlayerUseItemEventData _onUseItem(Server server, PlayerUseItemEventData event) {
    final key = event.item.getRegistryKey();
    final family = _pocketItems[key];
    if (family != null) {
      _usePocket(server, event, key, family);
      return event.cancel();
    }
    // A computer block item that is about to be placed: remember its component.
    if (event.clickedPos != null && _computerBlocks.containsKey(key)) {
      final bytes = event.item.customComponent(CcComponents.computerId);
      final label = event.item.getCustomName()?.getText();
      _pending[event.player.getId().asString] = _PendingPlacement(
        key,
        bytes == null ? null : _tryId(bytes),
        label == null || label.isEmpty ? null : label,
        _tick,
      );
    }
    return event;
  }

  static int? _tryId(List<int> bytes) {
    try {
      return CcComponents.decodeComputerId(bytes);
    } on PacketException {
      return null;
    }
  }

  /// Right click with a pocket computer: gets (or creates) its computer, turns
  /// it on and opens the menu. The item keeps the id in its `computer_id`
  /// component.
  void _usePocket(Server server, PlayerUseItemEventData event, String itemKey, ComputerFamily family) {
    final player = event.player;
    // A click on a block is followed by a use in the air that the host reports as
    // a second event: do not reopen the GUI the first one just opened.
    final uuid = player.getId().asString;
    final last = _lastPocketOpen[uuid];
    if (last != null && _tick - last < 4) return;
    final bytes = event.item.customComponent(CcComponents.computerId);
    var id = bytes == null ? null : _tryId(bytes);
    Computer? computer = id == null ? null : (_service.computer(id) ?? _service.resume(id));
    if (computer == null) {
      final owner = player.getId().asString;
      final limit = _service.pluginConfig.maxComputersPerPlayer;
      if (limit > 0 && _service.countOwnedBy(owner) >= limit && !player.hasPermission(node: CcPermissions.admin)) {
        player.send('&cYou can own at most $limit computers.');
        return;
      }
      computer = _service.create(family: family, owner: owner, ownerName: player.getName());
      id = computer.id;
      // The held stack that event.item copies: write the id into the real one.
      final held = player.getItemInHand(hand: event.hand);
      if (held != null) {
        held.setCustomComponent(CcComponents.computerId, CcComponents.encodeComputerId(id));
        player.setItemInHand(hand: event.hand, stack: held);
      }
    }
    _lastPocketOpen[uuid] = _tick;
    final menu = event.hand == Hand.left ? 'computercraft:pocket_computer_no_term' : 'computercraft:computer';
    final containerId = _network.open(player, computer, itemName: _pathOf(itemKey), menu: menu);
    if (containerId == null) {
      player.send('&cThe CC: Tweaked client mod is needed to use this computer (NeoForge handshake missing).');
    }
  }

  // -- Placing ------------------------------------------------------------------------

  /// A computer block was placed. The event fires before the block is in the
  /// world, so the entity is created a tick later, after checking the block.
  void _onBlockPlace(Server server, BlockPlaceEventData event) {
    final family = _computerBlocks[event.blockPlaced];
    if (family == null || event.cancelled) return;
    final player = event.player;
    final uuid = player.getId().asString;
    final owner = player.getName();
    final pending = _pending.remove(uuid);
    final from = pending != null && pending.blockKey == event.blockPlaced && _tick - pending.tick <= 2 ? pending : null;
    final world = player.getWorld();
    final String worldId;
    try {
      worldId = world.getId();
    } finally {
      world.dispose();
    }
    final location = _location(worldId, event.blockPos);
    final blockKey = event.blockPlaced;
    server.runLater(1, (server) => _createEntity(server, location, blockKey, uuid, owner, from));
  }

  void _createEntity(
    Server server,
    ComputerLocation location,
    String blockKey,
    String ownerUuid,
    String ownerName,
    _PendingPlacement? from,
  ) {
    final world = server.getWorldByName(name: location.world);
    if (world == null) return;
    try {
      // The placement may have been cancelled or the block replaced since.
      if (!_states.isBlock(world.getBlockStateId(pos: _pos(location)), blockKey)) return;
      if (_placed.containsKey(_key(location))) return;
      if (world.pluginBlockEntityAt(_pos(location)) != null) return;

      // `applyImplicitComponents`: the id and the label come from the item. An
      // id that another block already uses is not reused (CC would let two
      // blocks share one id; this plugin has one machine per id).
      var id = from?.computerId;
      if (id != null && _placed.values.any((p) => p.computerId == id)) id = null;
      final data = NbtCompound()..putBool('On', false);
      if (id != null) data.putInt('ComputerId', id);
      final label = from?.label;
      if (label != null) data.putString('Label', label);
      world.setPluginBlockEntity(_pos(location), blockKey, data);
      final placed = _attach(location, blockKey, data);
      if (id != null) {
        // Placed from an item: the machine starts off, like a fresh block entity.
        _service.resumeAt(id, location, family: placed.family, owner: ownerUuid, ownerName: ownerName, label: label, on: false);
      }
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the block entity of $blockKey at $location: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  /// Tracks the entity at [location]; reads the machine's id, label and power
  /// from [data].
  _Placed _attach(ComputerLocation location, String typeKey, NbtCompound data) {
    final storedId = data.getInt('ComputerId');
    final placed = _Placed(
      location,
      typeKey,
      data,
      computerId: storedId != null && storedId >= 0 ? storedId : null,
      label: data.getString('Label'),
      on: data.getBool('On') ?? false,
    );
    _placed[_key(location)] = placed;
    return placed;
  }

  // -- Loading and unloading chunks ------------------------------------------------------

  /// `BlockEntity.loadAdditional`: the chunk brought a computer; start its
  /// machine again (it was on when the chunk unloaded, `startOn`).
  void _onEntityLoad(Server server, BlockEntityLoadEventData event) {
    if (!_computerBlocks.containsKey(event.typeKey)) return;
    final world = event.targetWorld;
    final location = _location(world.getId(), event.pos);
    final NbtCompound data;
    try {
      data = event.save;
    } on FormatException catch (e) {
      logger.warn('The block entity data of ${event.typeKey} at $location is not a compound: $e');
      return;
    }
    final placed = _attach(location, event.typeKey, data);
    final id = placed.computerId;
    if (id != null) {
      _service.resumeAt(id, location, family: placed.family, label: placed.label, on: placed.on);
    }
  }

  /// The chunk unloads (the computer stops, its disk stays) or the block was
  /// broken (`removed`).
  void _onEntityUnload(Server server, BlockEntityUnloadEventData event) {
    if (!_computerBlocks.containsKey(event.typeKey)) return;
    final location = _location(event.targetWorld.getId(), event.pos);
    final placed = _placed.remove(_key(location));
    final id = placed?.computerId ?? _tryReadId(event);
    if (id != null) {
      _network.closeAllFor(server, id);
      _service.suspend(id, blockRemoved: event.removed);
    }
    if (event.removed) {
      _removed[_key(location)] = _Removed(event.typeKey, id, placed?.label, _tick);
    }
  }

  int? _tryReadId(BlockEntityUnloadEventData event) {
    try {
      final id = event.save.getInt('ComputerId');
      return id != null && id >= 0 ? id : null;
    } on FormatException {
      return null;
    }
  }

  // -- Breaking: the drop keeps the id (`collectSafeComponents`) --------------------------

  /// A broken computer drops its item with the `computer_id` component and its
  /// label as custom name. The event's own items are copies that the host
  /// ignores, so the stack goes straight into the breaking player's inventory
  /// and the vanilla drop is cancelled. With a full inventory, an explosion
  /// or another source without a player, the plain item drops and the id is
  /// lost (the computer's disk stays under its id).
  BlockDropItemEventData _onDropItem(Server server, BlockDropItemEventData event) {
    final player = event.player;
    if (player == null) return event;
    final world = event.targetWorld;
    final location = _location(world.getId(), event.blockPos);
    final key = _key(location);
    final placed = _placed[key];
    final removed = _removed[key];
    final blockKey = placed?.blockKey ?? removed?.blockKey;
    final id = placed?.computerId ?? removed?.computerId;
    if (blockKey == null || id == null) return event;
    final stack = ItemStack.create(registryKey: blockKey, count: 1);
    stack.setCustomComponent(CcComponents.computerId, CcComponents.encodeComputerId(id));
    final label = placed?.label ?? removed?.label;
    if (label != null) stack.setCustomName(name: Text(label).build());
    if (!_give(player, stack)) return event;
    _removed.remove(key);
    return event.cancel();
  }

  /// Puts [stack] into the first empty slot of the main inventory (the host
  /// has no call to drop an item entity with components).
  bool _give(Player player, ItemStack stack) {
    final inventory = player.getInventory().asInventory();
    // Main inventory first (9 to 35), then the hotbar.
    for (final slot in [for (var i = 9; i < 36; i++) i, for (var i = 0; i < 9; i++) i]) {
      if (inventory.getItem(slot: slot) == null) {
        inventory.setItem(slot: slot, item: stack);
        return true;
      }
    }
    return false;
  }

  // -- The server tick -----------------------------------------------------------------------

  /// Writes the power state and label to the entity and the block state
  /// (`serverTick`: `updateBlockState`) when they change, and forgets old
  /// removals.
  void tick(Server server) {
    _tick++;
    if (_removed.isNotEmpty && _tick % 40 == 0) {
      _removed.removeWhere((_, r) => _tick - r.tick > 40);
    }
    if (_pending.isNotEmpty && _tick % 40 == 0) {
      _pending.removeWhere((_, p) => _tick - p.tick > 40);
    }
    for (final placed in _placed.values.toList()) {
      final id = placed.computerId;
      if (id == null) continue;
      final computer = _service.computer(id);
      if (computer == null) continue;
      if (computer.state != placed.shown) _applyState(server, placed, computer.state);
      if (computer.isOn != placed.on || computer.label != placed.label) {
        placed.on = computer.isOn;
        placed.label = computer.label;
        _writeEntity(server, placed);
      }
    }
  }

  void _applyState(Server server, _Placed placed, ComputerState state) {
    final world = server.getWorldByName(name: placed.location.world);
    if (world == null) return;
    try {
      final pos = _pos(placed.location);
      final current = world.getBlockStateId(pos: pos);
      if (!_states.isBlock(current, placed.blockKey)) return;
      final next = _states.withValues(current, {'state': state.name});
      if (next == null) return;
      if (next != current) {
        world.setBlockState(pos: pos, state: next, updateFlags: const {BlockFlagsFlag.notifyListeners});
      }
      placed.shown = state;
    } finally {
      world.dispose();
    }
  }

  /// Writes the id, label and power state to the entity's save data.
  void _writeEntity(Server server, _Placed placed) {
    final world = server.getWorldByName(name: placed.location.world);
    if (world == null) return;
    try {
      final id = placed.computerId;
      if (id != null) placed.data.putInt('ComputerId', id);
      final label = placed.label;
      if (label != null) {
        placed.data.putString('Label', label);
      } else {
        placed.data.remove('Label');
      }
      placed.data.putBool('On', placed.on);
      world.setPluginBlockEntity(_pos(placed.location), placed.blockKey, placed.data);
    } on PluginRegistryException catch (e) {
      logger.warn('Could not save the block entity at ${placed.location}: ${e.message}');
    } finally {
      world.dispose();
    }
  }
}
