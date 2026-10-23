// Turtles in the world: the block entities of the turtle blocks, the turtle
// item and its components, the right click that opens the turtle GUI (the slot
// logic of its menu), the commands the Lua `turtle` API issues and the world
// adapter they run against.
//
// It mirrors `TurtleBlock`, `TurtleBlockEntity`, `TurtleBrain` and `TurtleMenu`
// (shared/turtle, mc-26.3) as far as the host allows; the model is in
// `lib/src/turtle` (binding-free), this file is the glue:
//
// * `ComputerId`, `Label`, `On`, `Fuel`, `Color`, `Overlay`, the upgrades, the
//   selected slot and the 16 slots are the save data of the block entity, and
//   the client data (`Label`, `Fuel`, `Color`, `Overlay`, upgrades,
//   `Animation`) is what the client's turtle renderer reads (`turtle_nbt.dart`);
// * placing a turtle item restores everything it carries, breaking a turtle
//   gives it back with all of it, and with the contents of its inventory (the
//   host cannot drop item entities with data, so they go into the breaker's
//   inventory; the break is refused when they do not fit);
// * `player-use-block-event` opens `computercraft:turtle` with 54 slots the
//   plugin owns (the host never applies clicks in plugin menus); the clicks are
//   `MenuLogic` (`turtle/menu.dart`);
// * a move is: set the same block at the new position, write the block entity
//   there with the animation, remove the old block. The client animates the
//   slide from the new block entity's `Animation`; commands are spaced by the
//   8 tick animation like in CC.
//
// Host calls that change something finish later, so this file awaits them. The
// turtle model and the menu logic are synchronous and binding-free: what they
// read is a snapshot taken before (`_playerSlots`, `_MenuSlots.open`, the
// container view of `containerAt`) and what they changed is written back
// after (`_MenuSlots.commit`, `_giveAll`, `ContainerView.setStack`).
//
// Nothing here has run against a host or a client: see docs/host-requirements.md
// ("Turtles") for what the host lacks and the README for what to test first.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/computer.dart';
import '../machine/peripheral.dart';
import '../machine/peripherals.dart';
import '../machine/side.dart';
import '../protocol/components.dart';
import '../protocol/datapack_registries.dart';
import '../protocol/menu_data.dart';
import '../turtle/brain.dart';
import '../turtle/direction.dart';
import '../turtle/menu.dart';
import '../turtle/stack.dart';
import '../turtle/upgrades.dart';
import '../turtle/world.dart';
import 'block_states.dart';
import 'commands.dart' show CcPermissions;
import 'network.dart';
import 'records.dart';
import 'service.dart';
import 'turtle_items.dart';
import 'turtle_nbt.dart';

/// The turtle blocks and whether they are advanced.
const Map<String, bool> _turtleBlocks = {
  'computercraft:turtle_normal': false,
  'computercraft:turtle_advanced': true,
};

/// The menu type of the turtle GUI.
const String _turtleMenu = 'computercraft:turtle';

/// The least ticks between two writes of an unchanged turtle to its chunk.
const int _saveInterval = 5;

String _pathOf(String key) => key.substring(key.indexOf(':') + 1);

/// A turtle block with its entity, as the plugin tracks it.
final class _Turtle {
  final TurtleBrain brain;
  final String blockKey;
  String? label;
  bool on = false;
  int lastSave = 0;

  /// The peripherals of the upgrades by side, with the upgrade they belong to.
  final Map<TurtleSide, (String, Peripheral)> peripherals = {};

  _Turtle(this.brain, this.blockKey);

  ComputerFamily get family => brain.advanced ? ComputerFamily.advanced : ComputerFamily.normal;

  WorldPos get pos => brain.pos;

  String get key => '${brain.worldId}|${pos.x}|${pos.y}|${pos.z}';

  ComputerLocation get location => ComputerLocation(brain.worldId, pos.x, pos.y, pos.z);
}

/// What the player was about to place: read from the item when the use event
/// fires, consumed by the place event right after.
final class _PendingPlacement {
  final String blockKey;
  final TurtleItemData data;
  final int tick;

  const _PendingPlacement(this.blockKey, this.data, this.tick);
}

/// A turtle block that was just removed, for the drop event that may follow.
final class _Removed {
  final _Turtle turtle;
  final int tick;
  bool contentsGiven = false;

  _Removed(this.turtle, this.tick);
}

/// Runs async actions one after another per key: a click, a close and a refresh
/// of the same GUI each read a snapshot of the player's slots and write back
/// what changed, so they must not interleave (the same as `KeyedLock` in
/// example/commons/lib/src/core/lock.dart).
final class _KeyedLock {
  final Map<Object, Completer<void>> _tails = {};

  Future<T> run<T>(Object key, Future<T> Function() action) async {
    final previous = _tails[key];
    final done = Completer<void>();
    _tails[key] = done;
    try {
      if (previous != null) await previous.future;
      return await action();
    } finally {
      done.complete();
      if (identical(_tails[key], done)) _tails.remove(key);
    }
  }
}

/// A player with a turtle's GUI open.
final class _Gui {
  final String playerUuid;
  final _Turtle turtle;
  final int containerId;
  final MenuLogic logic;

  /// The player's handle of the callback that is running (a handle is only
  /// valid inside the callback that received it): refreshed on every click.
  Player player;

  /// The signature of what the host menu holds in each slot.
  final List<String> sent = List<String>.filled(TurtleMenuLayout.slotCount, '');
  int sentSelected = -1;

  _Gui(this.playerUuid, this.turtle, this.containerId, this.logic, this.player);
}

final class CcWorldTurtles {
  final CcService _service;
  final CcNetwork _network;
  final CcBlockStates _states;
  final CcDatapackRegistries _datapack;
  final HostItems _items = HostItems();
  late final TurtleUpgrades _upgrades = TurtleUpgrades.of(_datapack.turtleUpgrades);
  late final TurtleSettings _settings;

  final Map<String, _Turtle> _turtles = {};
  final Map<String, _PendingPlacement> _pending = {};
  final Map<String, _Removed> _removed = {};

  /// The player that is breaking the turtle at a position (from the break
  /// event), for the creative mode case that has no drop event.
  final Map<String, (String, int)> _breakers = {};
  final Map<String, _Gui> _guis = {};
  final _KeyedLock _guiLock = _KeyedLock();
  int _tick = 0;

  /// Whether a [tick] is still waiting for the host.
  bool _ticking = false;

  CcWorldTurtles(this._service, this._network, this._states, this._datapack) {
    final config = _service.pluginConfig;
    _settings = TurtleSettings(
      needsFuel: config.turtlesNeedFuel,
      fuelLimit: config.turtleFuelLimit,
      advancedFuelLimit: config.advancedTurtleFuelLimit,
    );
  }

  /// Number of turtle blocks with an entity the plugin tracks.
  int get placedCount => _turtles.length;

  /// Number of turtle GUIs open.
  int get guiCount => _guis.length;

  static String _key(ComputerLocation l) => '${l.world}|${l.x}|${l.y}|${l.z}';

  static BlockPos _blockPos(WorldPos p) => BlockPos(x: p.x, y: p.y, z: p.z);

  /// Listens for the events that drive turtle blocks.
  void install(Context context) {
    context.intercept(Events.playerUseItem, _onUseItem);
    context.intercept(Events.playerUseBlock, _onUseBlock);
    context.listen(Events.blockPlace, _onBlockPlace);
    context.intercept(Events.blockBreak, _onBlockBreak);
    context.intercept(Events.blockDropItem, _onDropItem);
    context.listen(Events.blockEntityLoad, _onEntityLoad);
    context.listen(Events.blockEntityUnload, _onEntityUnload);
    context.listen(Events.menuClick, _onMenuClick);
    context.listen(Events.menuClosed, _onMenuClosed);
  }

  // -- Turtles from blocks ---------------------------------------------------------

  TurtleBrain _newBrain(String blockKey, ComputerLocation location, Dir facing) {
    final brain = TurtleBrain(
      advanced: _turtleBlocks[blockKey] ?? false,
      settings: _settings,
      upgradeTable: _upgrades,
      itemInfo: _items,
    );
    brain.worldId = location.world;
    brain.pos = WorldPos(location.x, location.y, location.z);
    brain.facing = facing;
    brain.log = (message) => logger.warn('Turtle at ${brain.worldId} ${brain.pos}: $message');
    return brain;
  }

  /// The facing of the turtle block at [pos] (a state property).
  Dir _facingAt(World world, BlockPos pos) {
    final state = _states.decode(world.getBlockStateId(pos: pos));
    return Dir.parse(state?.values['facing'] ?? '') ?? Dir.north;
  }

  /// Tracks the entity at [location]: reads its save data into a brain.
  _Turtle _attach(World world, ComputerLocation location, String blockKey, NbtCompound save) {
    final facing = _facingAt(world, BlockPos(x: location.x, y: location.y, z: location.z));
    final brain = _newBrain(blockKey, location, facing);
    TurtleNbt.load(brain, save);
    final id = save.getInt('ComputerId');
    brain.computerId = id != null && id >= 0 ? id : null;
    final turtle = _Turtle(brain, blockKey)
      ..label = save.getString('Label')
      ..on = save.getBool('On') ?? false
      ..lastSave = _tick;
    brain.saveDirty = false;
    brain.clientDirty = false;
    _turtles[turtle.key] = turtle;
    return turtle;
  }

  /// Gives a turtle block that has no tracked entity one: the entity data from
  /// the chunk if there is one (a load event that was missed), else an empty
  /// turtle (the block was placed by a command or world edit).
  _Turtle? _adopt(World world, ComputerLocation location, String blockKey) {
    try {
      final pos = BlockPos(x: location.x, y: location.y, z: location.z);
      final existing = world.pluginBlockEntityAt(pos);
      if (existing != null) return _attach(world, location, existing.typeKey, existing.save);
      final turtle = _attach(world, location, blockKey, NbtCompound()..putBool('On', false));
      _writeEntity(world, turtle);
      return turtle;
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the block entity of $blockKey at $location: ${e.message}');
      return null;
    }
  }

  // -- Right click: the GUI ------------------------------------------------------------

  Future<PlayerUseBlockEventData> _onUseBlock(Server server, PlayerUseBlockEventData event) async {
    // `AbstractComputerBlock.useWithoutItem`: `!player.isCrouching()`.
    if (event.sneaking || !_turtleBlocks.containsKey(event.block)) return event;
    final player = event.player;
    final world = player.getWorld();
    try {
      final location = ComputerLocation(world.getId(), event.blockPos.x, event.blockPos.y, event.blockPos.z);
      final turtle = _turtles[_key(location)] ?? _adopt(world, location, event.block);
      if (turtle == null) {
        player.send('&cThis turtle has no block entity and could not get one.');
      } else {
        await _open(server, player, turtle);
      }
    } finally {
      world.dispose();
    }
    return event.cancel();
  }

  /// The machine of a turtle, created with the next id when the turtle has
  /// none yet (the id is written to the entity).
  Future<Computer?> _ensureComputer(Player player, _Turtle turtle) async {
    final brain = turtle.brain;
    final id = brain.computerId;
    final Computer computer;
    if (id != null) {
      computer =
          _service.computer(id) ??
          _service.resumeAt(
            id,
            turtle.location,
            family: turtle.family,
            label: turtle.label,
            on: turtle.on,
            turtle: brain,
          );
    } else {
      final owner = player.getId().asString;
      final limit = _service.pluginConfig.maxComputersPerPlayer;
      if (limit > 0 && _service.countOwnedBy(owner) >= limit && !await player.hasPermission(node: CcPermissions.admin)) {
        player.send('&cYou can own at most $limit computers.');
        return null;
      }
      computer = _service.create(family: turtle.family, owner: owner, ownerName: player.getName(), turtle: brain);
      _service.resumeAt(computer.id, turtle.location, family: turtle.family, on: false, turtle: brain);
      brain.computerId = computer.id;
      brain.saveDirty = true;
    }
    _wire(turtle, computer);
    return computer;
  }

  /// Connects the brain and the computer: events and peripherals.
  void _wire(_Turtle turtle, Computer computer) {
    if (!identical(computer.turtle, turtle.brain)) computer.turtle = turtle.brain;
    turtle.brain.onUpgradesChanged = () => _refreshPeripherals(turtle, computer);
    _refreshPeripherals(turtle, computer);
  }

  /// Gives the computer the peripherals of the upgrades on its sides
  /// (`TurtleBrain.updatePeripherals`): wireless modems, and stubs for the
  /// speaker and the crafting table.
  void _refreshPeripherals(_Turtle turtle, Computer computer) {
    for (final side in TurtleSide.values) {
      final instance = turtle.brain.upgradeOn(side);
      final computerSide = side == TurtleSide.left ? ComputerSide.left : ComputerSide.right;
      final current = turtle.peripherals[side];
      if (instance == null || !instance.upgrade.isPeripheral) {
        if (current != null) {
          turtle.peripherals.remove(side);
          computer.setPeripheral(computerSide, null);
        }
        continue;
      }
      if (current != null && current.$1 == instance.upgrade.key) continue;
      final Peripheral? peripheral = switch (instance.upgrade.kind) {
        UpgradeKind.modem => WirelessModem(
          network: _service.wireless,
          advanced: instance.upgrade.advancedModem,
          position: _center(turtle.pos),
        ),
        // The speaker upgrade plays for real: its notes and audio go to the
        // players around the turtle, and it follows the turtle with
        // `speaker_move` (Java: the upgrade's `SpeakerPeripheral` over the
        // turtle's position).
        UpgradeKind.speaker => _speaker(turtle),
        UpgradeKind.workbench => StubPeripheral.workbench(),
        _ => null,
      };
      if (peripheral == null) continue;
      turtle.peripherals[side] = (instance.upgrade.key, peripheral);
      computer.setPeripheral(computerSide, peripheral);
    }
  }

  static (double, double, double) _center(WorldPos pos) => (pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);

  /// The speakers of the turtle upgrades, with the sink that sends their
  /// payloads (keyed by the turtle, so an upgrade keeps its speaker while it is
  /// equipped).
  final Map<String, (SpeakerPeripheral, CcSpeakerSink)> _speakers = {};

  /// The speaker of the speaker upgrade of [turtle]: one per turtle, so
  /// `speaker_audio_empty` and the moving position stay with the same device.
  SpeakerPeripheral _speaker(_Turtle turtle) {
    final existing = _speakers[turtle.key];
    if (existing != null) return existing.$1;
    final sink = CcSpeakerSink(_network, newSpeakerSource(), turtle.location.world, () => _center(turtle.pos));
    final speaker = SpeakerPeripheral(sink: sink, position: _center(turtle.pos));
    _speakers[turtle.key] = (speaker, sink);
    return speaker;
  }

  /// Right click: makes sure there is a computer, turns it on and opens the GUI.
  Future<void> _open(Server server, Player player, _Turtle turtle) async {
    final computer = await _ensureComputer(player, turtle);
    if (computer == null) return;
    final brain = turtle.brain;
    final extra = <ComponentEntry>[
      for (final (name, instance) in [('left_turtle_upgrade', brain.upgradeOn(TurtleSide.left)), ('right_turtle_upgrade', brain.upgradeOn(TurtleSide.right))])
        if (instance != null)
          ComponentEntry(_network.componentTypeId(name), CcComponents.encodeUpgrade(instance.upgrade.id, instance.patch)),
    ];
    // Read before the menu opens, so that the GUI is registered right after it
    // (a click cannot arrive in between).
    final slots = await _MenuSlots.open(this, player, turtle);
    final containerId = _network.open(
      player,
      computer,
      itemName: _pathOf(turtle.blockKey),
      menu: _turtleMenu,
      at: turtle.location,
      slots: TurtleMenuLayout.slotCount,
      extraComponents: extra,
    );
    if (containerId == null) {
      player.send('&cThe CC: Tweaked client mod is needed to open this turtle (NeoForge handshake missing).');
      return;
    }
    logger.info('${player.getName()} opened the turtle GUI of computer #${computer.id} at ${turtle.location} (container $containerId).');
    final uuid = player.getId().asString;
    final gui = _Gui(uuid, turtle, containerId, MenuLogic(slots), player);
    gui.logic.onCursorChanged = () => _showCursor(gui);
    _guis[uuid] = gui;
    await _guiLock.run(uuid, () => _pushAll(player, gui, slots));
  }

  // -- The GUI: slots -----------------------------------------------------------------------

  /// Sends the slots that changed and the selected slot to the player. [known]
  /// is a snapshot of the player's slots that is still current.
  Future<void> _pushAll(Player player, _Gui gui, [_MenuSlots? known]) async {
    final slots = known ?? await _MenuSlots.open(this, player, gui.turtle);
    for (var i = 0; i < TurtleMenuLayout.slotCount; i++) {
      final stack = slots.read(i);
      final signature = HostItems.signature(stack);
      if (signature == gui.sent[i]) continue;
      gui.sent[i] = signature;
      try {
        if (stack == null) {
          player.clearPluginMenuSlot(i);
        } else {
          final host = await _items.toHost(stack);
          player.setPluginMenuSlot(i, host);
          host.dispose();
        }
      } on PluginRegistryException catch (e) {
        logger.warn('Could not send turtle menu slot $i: ${e.message}');
      }
    }
    final selected = gui.turtle.brain.selectedSlot;
    if (selected != gui.sentSelected) {
      gui.sentSelected = selected;
      try {
        // Data slot 0 is `isOn` (`AbstractComputerMenu`), 1 the selected slot (`TurtleMenu`).
        player.setPluginMenuData(1, selected);
      } on PluginRegistryException catch (e) {
        logger.warn('Could not send the selected slot: ${e.message}');
      }
    }
  }

  void _showCursor(_Gui gui) {
    final carried = gui.logic.cursor;
    if (carried == null) return;
    try {
      gui.player.showActionbar(text: Text('Holding ${carried.count} x ${_name(carried.item)}: click a slot to put it down').build());
    } catch (_) {
      // The action bar is a courtesy.
    }
  }

  static String _name(String key) => _pathOf(key).replaceAll('_', ' ');

  TurtleClick _mapClick(ClickType type) => switch (type) {
    ClickType.left => TurtleClick.left,
    ClickType.right => TurtleClick.right,
    ClickType.shiftLeft => TurtleClick.shiftLeft,
    ClickType.shiftRight => TurtleClick.shiftRight,
    ClickType.middle => TurtleClick.middle,
    ClickType.drop => TurtleClick.drop,
    ClickType.controlDrop => TurtleClick.controlDrop,
    ClickType.doubleClick => TurtleClick.doubleClick,
    ClickType.numberKey => TurtleClick.numberKey,
    _ => TurtleClick.unknown,
  };

  Future<void> _onMenuClick(Server server, MenuClickEventData event) async {
    if (event.menuType != _turtleMenu) return;
    final uuid = event.player.getId().asString;
    final gui = _guis[uuid];
    if (gui == null || gui.containerId != event.containerId) return;
    gui.player = event.player;
    await _guiLock.run(uuid, () async {
      // The logic is synchronous: it runs on a snapshot of the player's slots
      // and the changed ones are written back after it.
      final slots = await _MenuSlots.open(this, event.player, gui.turtle);
      gui.logic.slots = slots;
      gui.logic.click(event.slot, event.button, _mapClick(event.clickType), _tick);
      await slots.commit();
      await _pushAll(event.player, gui, slots);
    });
  }

  Future<void> _onMenuClosed(Server server, MenuClosedEventData event) async {
    if (event.menuType != _turtleMenu) return;
    final uuid = event.player.getId().asString;
    final gui = _guis[uuid];
    if (gui == null || gui.containerId != event.containerId) return;
    _guis.remove(uuid);
    await _guiLock.run(uuid, () => _closeGui(event.player, gui));
  }

  /// Gives the cursor stack back (the player's inventory first, then the turtle).
  Future<void> _closeGui(Player player, _Gui gui) async {
    if (gui.logic.cursor == null) return;
    final slots = await _MenuSlots.open(this, player, gui.turtle);
    gui.logic.slots = slots;
    var rest = gui.logic.returnCursor();
    await slots.commit();
    if (rest != null) rest = gui.turtle.brain.storeItems(rest);
    if (rest != null) player.send('&cYour inventory was full: ${rest.count} x ${_name(rest.item)} were lost.');
  }

  // -- Placing -----------------------------------------------------------------------------------

  Future<PlayerUseItemEventData> _onUseItem(Server server, PlayerUseItemEventData event) async {
    final key = await event.item.getRegistryKey();
    if (event.clickedPos != null && _turtleBlocks.containsKey(key)) {
      final tick = _tick;
      _pending[event.player.getId().asString] = _PendingPlacement(key, await TurtleItemData.read(event.item, _upgrades), tick);
    }
    return event;
  }

  /// A turtle block was placed. The event fires before the block is in the
  /// world, so the entity is created a tick later, after checking the block.
  void _onBlockPlace(Server server, BlockPlaceEventData event) {
    if (!_turtleBlocks.containsKey(event.blockPlaced) || event.cancelled) return;
    final player = event.player;
    final uuid = player.getId().asString;
    final owner = player.getName();
    final pending = _pending.remove(uuid);
    final from = pending != null && pending.blockKey == event.blockPlaced && _tick - pending.tick <= 2 ? pending.data : null;
    final world = player.getWorld();
    final String worldId;
    try {
      worldId = world.getId();
    } finally {
      world.dispose();
    }
    final location = ComputerLocation(worldId, event.blockPos.x, event.blockPos.y, event.blockPos.z);
    final blockKey = event.blockPlaced;
    server.runLater(1, (server) => _createEntity(server, location, blockKey, uuid, owner, from));
  }

  void _createEntity(
    Server server,
    ComputerLocation location,
    String blockKey,
    String ownerUuid,
    String ownerName,
    TurtleItemData? from,
  ) {
    final world = server.getWorldByName(name: location.world);
    if (world == null) return;
    try {
      final pos = BlockPos(x: location.x, y: location.y, z: location.z);
      // The placement may have been cancelled or the block replaced since.
      if (!_states.isBlock(world.getBlockStateId(pos: pos), blockKey)) return;
      if (_turtles.containsKey(_key(location))) return;
      if (world.pluginBlockEntityAt(pos) != null) return;

      final brain = _newBrain(blockKey, location, _facingAt(world, pos));
      // `applyImplicitComponents`: everything comes from the item.
      var id = from?.computerId;
      if (id != null && _turtles.values.any((t) => t.brain.computerId == id)) id = null;
      brain.computerId = id;
      brain.ownerUuid = ownerUuid;
      brain.ownerName = ownerName;
      if (from != null) {
        brain.colour = from.colour;
        brain.overlay = from.overlay;
        brain.fuelLevel = from.fuel;
        brain.setUpgradeDirect(TurtleSide.left, from.left);
        brain.setUpgradeDirect(TurtleSide.right, from.right);
      }
      final turtle = _Turtle(brain, blockKey)
        ..label = from?.label
        ..lastSave = _tick;
      _turtles[turtle.key] = turtle;
      _writeEntity(world, turtle);
      logger.info(
        'Turtle placed at $location: $blockKey facing ${brain.facing.name}, computer id ${id ?? 'none yet'}, '
        'fuel ${brain.fuelLevel}, upgrades left ${brain.upgradeOn(TurtleSide.left)?.upgrade.key ?? '-'} '
        'right ${brain.upgradeOn(TurtleSide.right)?.upgrade.key ?? '-'}.',
      );
      if (id != null) {
        // Placed from an item: the machine starts off, like a fresh block entity.
        final computer = _service.resumeAt(
          id,
          turtle.location,
          family: turtle.family,
          owner: ownerUuid,
          ownerName: ownerName,
          label: turtle.label,
          on: false,
          turtle: brain,
        );
        _wire(turtle, computer);
      }
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the block entity of $blockKey at $location: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  // -- Loading and unloading chunks ------------------------------------------------------------------

  /// `BlockEntity.loadAdditional`: the chunk brought a turtle; start its
  /// machine again (it was on when the chunk unloaded).
  void _onEntityLoad(Server server, BlockEntityLoadEventData event) {
    if (!_turtleBlocks.containsKey(event.typeKey)) return;
    final world = event.targetWorld;
    final location = ComputerLocation(world.getId(), event.pos.x, event.pos.y, event.pos.z);
    final NbtCompound data;
    try {
      data = event.save;
    } on FormatException catch (e) {
      logger.warn('The block entity data of ${event.typeKey} at $location is not a compound: $e');
      return;
    }
    final turtle = _attach(world, location, event.typeKey, data);
    final id = turtle.brain.computerId;
    if (id != null) {
      final computer = _service.resumeAt(
        id,
        location,
        family: turtle.family,
        label: turtle.label,
        on: turtle.on,
        turtle: turtle.brain,
      );
      _wire(turtle, computer);
    }
  }

  /// The chunk unloads (the machine stops, its disk stays) or the block was
  /// broken or replaced (`removed`). A turtle that moved is not here any more
  /// (it was re-keyed to its new position), so its old position is ignored.
  Future<void> _onEntityUnload(Server server, BlockEntityUnloadEventData event) async {
    if (!_turtleBlocks.containsKey(event.typeKey)) return;
    final location = ComputerLocation(event.targetWorld.getId(), event.pos.x, event.pos.y, event.pos.z);
    final key = _key(location);
    final turtle = _turtles.remove(key);
    if (turtle == null) return;
    final id = turtle.brain.computerId;
    if (id != null) {
      _network.closeAllFor(server, id);
      _service.suspend(id, blockRemoved: event.removed);
    }
    for (final gui in _guis.values.where((g) => identical(g.turtle, turtle)).toList()) {
      _guis.remove(gui.playerUuid);
    }
    if (!event.removed) {
      // The chunk unloads: write what changed since the last save.
      if (turtle.brain.saveDirty) _tryWrite(event.targetWorld, turtle);
      return;
    }
    final removed = _Removed(turtle, _tick);
    _removed[key] = removed;
    final breaker = _breakers.remove(key);
    if (breaker != null && _tick - breaker.$2 <= 40) {
      // A creative player breaking a turtle gets no item, but the contents of
      // the inventory still come out (`preRemoveSideEffects`).
      final player = server.getPlayerByUuid(id: Uuids.parse(breaker.$1));
      if (player != null) {
        try {
          if (player.isCreative) {
            await _giveContents(player, removed);
          } else {
            // The drop event normally follows at once and gives the item; if it
            // does not (the host skips it for some breaks), give it here.
            final breakerUuid = breaker.$1;
            server.runLater(2, (server) => _fallbackGive(server, key, breakerUuid));
          }
        } finally {
          player.dispose();
        }
      }
    }
  }

  /// The drop event of a broken turtle did not come: give the turtle item and
  /// its contents to the player who broke it.
  Future<void> _fallbackGive(Server server, String key, String playerUuid) async {
    final removed = _removed.remove(key);
    if (removed == null) return;
    final player = server.getPlayerByUuid(id: Uuids.parse(playerUuid));
    if (player == null) return;
    try {
      final includeContents = !removed.contentsGiven;
      removed.contentsGiven = true;
      final stacks = await _turtleStacks(removed.turtle, includeContents: includeContents);
      if ((await _giveAll(player, stacks)).isNotEmpty) player.send('&cYour inventory was full: some of the turtle\'s items were lost.');
    } finally {
      player.dispose();
    }
  }

  /// The turtle as an item with everything it carries, then (optionally) the
  /// stacks of its inventory.
  Future<List<TurtleStack>> _turtleStacks(_Turtle turtle, {required bool includeContents}) async {
    final brain = turtle.brain;
    final item = TurtleItemData()
      ..computerId = brain.computerId
      ..label = turtle.label
      ..colour = brain.colour
      ..fuel = brain.fuelLevel
      ..overlay = brain.overlay
      ..left = brain.upgradeOn(TurtleSide.left)
      ..right = brain.upgradeOn(TurtleSide.right);
    final itemStack = await item.build(turtle.blockKey);
    final stacks = [await _items.fromHost(itemStack)];
    itemStack.dispose();
    if (includeContents) stacks.addAll(_contentsOf(brain));
    return stacks;
  }

  void _tryWrite(World world, _Turtle turtle) {
    try {
      _writeEntity(world, turtle);
    } on PluginRegistryException {
      // The chunk is going away; the last periodic save stands.
    }
  }

  // -- Breaking ------------------------------------------------------------------------------------------

  /// `block-break-event`: refuse the break of a turtle whose item and contents
  /// do not fit into the breaker's inventory (nothing could drop them).
  Future<BlockBreakEventData> _onBlockBreak(Server server, BlockBreakEventData event) async {
    if (!_turtleBlocks.containsKey(event.block)) return event;
    final player = event.player;
    if (player == null) return event;
    final world = player.getWorld();
    try {
      final location = ComputerLocation(world.getId(), event.blockPos.x, event.blockPos.y, event.blockPos.z);
      final turtle = _turtles[_key(location)];
      if (turtle == null) return event;
      final stacks = _contentsOf(turtle.brain);
      if (!player.isCreative) stacks.insert(0, TurtleStack(turtle.blockKey, 1));
      if (stacks.isNotEmpty && !await _fitsInto(player, stacks)) {
        player.send('&cMake room in your inventory first: the turtle and its ${stacks.length - 1} item stack(s) must fit.');
        return event.cancel();
      }
      _breakers[_key(location)] = (player.getId().asString, _tick);
    } finally {
      world.dispose();
    }
    return event;
  }

  /// A broken turtle drops its item with everything it carries
  /// (`collectSafeComponents`) and the contents of its inventory. The host's
  /// own drop is a plain item that the host ignores changes to, so the stacks
  /// go straight into the breaking player's inventory and the vanilla drop is
  /// cancelled. Without a player (an explosion) the plain item drops and the
  /// turtle's id and contents are lost; the computer's disk stays under its id.
  Future<BlockDropItemEventData> _onDropItem(Server server, BlockDropItemEventData event) async {
    final player = event.player;
    if (player == null) return event;
    final world = event.targetWorld;
    final key = _key(ComputerLocation(world.getId(), event.blockPos.x, event.blockPos.y, event.blockPos.z));
    final removed = _removed[key];
    final turtle = removed?.turtle ?? _turtles[key];
    if (turtle == null) return event;
    final includeContents = removed == null || !removed.contentsGiven;
    if (removed != null) removed.contentsGiven = true;
    final stacks = await _turtleStacks(turtle, includeContents: includeContents);
    final rest = await _giveAll(player, stacks);
    if (rest.isNotEmpty) {
      // Should not happen after the check in the break event: keep the plain drop.
      player.send('&cSome of the turtle\'s items did not fit and were lost.');
    }
    _removed.remove(key);
    return event.cancel();
  }

  List<TurtleStack> _contentsOf(TurtleBrain brain) => [
    for (final stack in brain.inventory.items)
      if (stack != null) stack.copy(),
  ];

  Future<void> _giveContents(Player player, _Removed removed) async {
    if (removed.contentsGiven) return;
    removed.contentsGiven = true;
    final rest = await _giveAll(player, _contentsOf(removed.turtle.brain));
    if (rest.isNotEmpty) player.send('&cYour inventory was full: some of the turtle\'s items were lost.');
  }

  /// The player's 36 storage slots (hotbar first) as a model, for fit checks.
  Future<Slots> _playerSlots(Player player) async {
    final slots = Slots(36, _items);
    final inventory = player.getInventory().asInventory();
    for (var i = 0; i < 36; i++) {
      final stack = inventory.getItem(slot: i);
      if (stack == null) continue;
      slots.items[i] = await _items.fromHost(stack);
      stack.dispose();
    }
    return slots;
  }

  /// Whether all [stacks] would fit into the player's inventory.
  Future<bool> _fitsInto(Player player, List<TurtleStack> stacks) async {
    final slots = await _playerSlots(player);
    for (final stack in stacks) {
      if (slots.storeFromOffset(stack, 0) != null) return false;
    }
    return true;
  }

  /// Puts [stacks] into the player's inventory; returns what did not fit.
  Future<List<TurtleStack>> _giveAll(Player player, List<TurtleStack> stacks) async {
    final slots = await _playerSlots(player);
    final before = [for (final s in slots.items) HostItems.signature(s)];
    final rest = <TurtleStack>[];
    for (final stack in stacks) {
      final left = slots.storeFromOffset(stack, 0);
      if (left != null) rest.add(left);
    }
    final inventory = player.getInventory().asInventory();
    for (var i = 0; i < 36; i++) {
      if (HostItems.signature(slots.items[i]) == before[i]) continue;
      final stack = slots.items[i];
      await inventory.setItem(slot: i, item: stack == null ? null : await _items.toHost(stack));
    }
    return rest;
  }

  // -- The server tick ---------------------------------------------------------------------------------------

  /// Runs the turtles' commands and animations, writes changes to the
  /// entities, and keeps open GUIs in sync. A tick that comes while the
  /// previous one still waits for the host only counts as a tick of the clock
  /// and is otherwise skipped.
  Future<void> tick(Server server) async {
    _tick++;
    if (_ticking) return;
    _ticking = true;
    try {
      if (_tick % 40 == 0) {
        _removed.removeWhere((_, r) => _tick - r.tick > 40);
        _pending.removeWhere((_, p) => _tick - p.tick > 40);
        _breakers.removeWhere((_, b) => _tick - b.$2 > 40);
      }
      for (final turtle in _turtles.values.toList()) {
        try {
          await _tickTurtle(server, turtle);
        } catch (e, s) {
          // One turtle must not stop the others (a chunk that is not loaded, a host error).
          logger.error('Turtle at ${turtle.location} failed: $e\n$s');
        }
      }
      _tickSpeakers(server);
      if (_guis.isNotEmpty && _tick % 2 == 0) await _tickGuis(server);
    } catch (e, s) {
      logger.error('The turtle tick failed: $e\n$s');
    } finally {
      _ticking = false;
    }
  }

  /// Plays what the speakers of the turtle upgrades have queued
  /// (`SpeakerPeripheral.update`): the turtle's speaker follows the turtle, so
  /// its position is updated first, and the sink then sends the payloads to the
  /// players around it.
  void _tickSpeakers(Server server) {
    for (final entry in _speakers.entries) {
      final turtle = _turtles[entry.key];
      if (turtle == null) continue;
      final (speaker, sink) = entry.value;
      final at = _center(turtle.pos);
      speaker.position = at;
      sink.server = server;
      speaker.update(_service.nowMicros * 1000);
    }
  }

  Future<void> _tickTurtle(Server server, _Turtle turtle) async {
    final brain = turtle.brain;
    final id = brain.computerId;
    if (id != null) {
      final computer = _service.computer(id);
      if (computer != null) {
        if (computer.isOn != turtle.on || computer.label != turtle.label) {
          turtle.on = computer.isOn;
          turtle.label = computer.label;
          brain.saveDirty = true;
          brain.clientDirty = true;
        }
      }
    }
    final provider = _WorldProvider(this, server, turtle);
    try {
      await brain.update(provider.get);
    } catch (e, s) {
      logger.error('A turtle command failed: $e\n$s');
    } finally {
      provider.dispose();
    }
    // The turtle may have moved: `turtle` is the same object, re-keyed. Or its
    // block was removed while the commands waited for the host.
    if (!identical(_turtles[turtle.key], turtle)) return;
    if (brain.clientDirty || (brain.saveDirty && _tick - turtle.lastSave >= _saveInterval)) {
      final world = server.getWorldByName(name: brain.worldId);
      if (world != null) {
        try {
          _writeEntity(world, turtle);
        } on PluginRegistryException catch (e) {
          logger.warn('Could not save the turtle at ${turtle.location}: ${e.message}');
        } finally {
          world.dispose();
        }
      }
    }
  }

  Future<void> _tickGuis(Server server) async {
    for (final gui in _guis.values.toList()) {
      final player = server.getPlayerByUuid(id: Uuids.parse(gui.playerUuid));
      if (player == null) {
        _guis.remove(gui.playerUuid);
        continue;
      }
      try {
        final open = player.currentPluginMenu;
        if (open == null || open.containerId != gui.containerId) {
          // The menu is gone without a close event (should not happen): do not
          // lose what the player carried.
          _guis.remove(gui.playerUuid);
          await _guiLock.run(gui.playerUuid, () => _closeGui(player, gui));
          continue;
        }
        await _guiLock.run(gui.playerUuid, () => _pushAll(player, gui));
      } finally {
        player.dispose();
      }
    }
  }

  // -- The block entity ---------------------------------------------------------------------------------------------

  /// Writes the save and client data of [turtle] to its entity (which sends
  /// the client data to the players that watch it).
  void _writeEntity(World world, _Turtle turtle) {
    final brain = turtle.brain;
    world.setPluginBlockEntity(
      _blockPos(turtle.pos),
      turtle.blockKey,
      TurtleNbt.save(brain, label: turtle.label, on: turtle.on),
      client: TurtleNbt.client(brain, label: turtle.label),
    );
    brain.saveDirty = false;
    brain.clientDirty = false;
    turtle.lastSave = _tick;
  }

  /// A turtle moved from [from]: re-key it and tell the machine and the GUIs.
  void _moved(_Turtle turtle, String oldKey) {
    _turtles.remove(oldKey);
    _turtles[turtle.key] = turtle;
    final id = turtle.brain.computerId;
    if (id != null) {
      _service.record(id)?.location = turtle.location;
      _network.relocate(id, turtle.location);
    }
    for (final entry in turtle.peripherals.values) {
      final peripheral = entry.$2;
      if (peripheral is WirelessModem) peripheral.position = _center(turtle.pos);
    }
  }
}

// -- The world adapter -----------------------------------------------------------------------------------

/// Opens the world of a turtle once per tick, only when a command needs it.
final class _WorldProvider {
  final CcWorldTurtles _owner;
  final Server _server;
  final _Turtle _turtle;
  _HostTurtleWorld? _world;

  _WorldProvider(this._owner, this._server, this._turtle);

  TurtleWorld? get() {
    final existing = _world;
    if (existing != null) return existing;
    final world = _server.getWorldByName(name: _turtle.brain.worldId);
    if (world == null) return null;
    return _world = _HostTurtleWorld(_owner, _server, world, _turtle);
  }

  void dispose() => _world?.world.dispose();
}

/// `TurtleWorld` over the host's world API. What the host cannot do is noted
/// at the method (docs/host-requirements.md, "Turtles").
final class _HostTurtleWorld implements TurtleWorld {
  final CcWorldTurtles owner;
  final Server server;
  final World world;
  final _Turtle turtle;

  _HostTurtleWorld(this.owner, this.server, this.world, this.turtle);

  TurtleBrain get _brain => turtle.brain;

  @override
  int maxStack(String item) => owner._items.maxStack(item);

  @override
  BlockInfo blockAt(WorldPos pos) {
    final bp = CcWorldTurtles._blockPos(pos);
    final state = world.getBlockState(pos: bp);
    final block = world.getBlock(pos: bp);
    return BlockInfo(
      name: state.blockName,
      stateId: state.id,
      isAir: state.isAir,
      isLiquid: state.isLiquid,
      replaceable: state.replaceable,
      hardness: state.hardness,
      properties: state.propertyMap,
      itemKey: block.itemId > 0 ? itemKeyOfId(block.itemId) : null,
    );
  }

  @override
  String? whyCannotEnter(WorldPos pos) {
    final minY = world.getMinY();
    final height = world.getDimension() == 'minecraft:overworld' ? 384 : 256;
    if (pos.y < minY) return 'Too low to move';
    if (pos.y >= minY + height) return 'Too high to move';
    final border = world.getBorder();
    try {
      final half = border.getDiameter() / 2;
      final dx = (pos.x + 0.5 - border.getCenterX()).abs();
      final dz = (pos.z + 0.5 - border.getCenterZ()).abs();
      if (dx > half || dz > half) return 'Cannot pass the world border';
    } finally {
      border.dispose();
    }
    if (world.getChunk(x: pos.x >> 4, z: pos.z >> 4) == null) return 'Cannot leave loaded world';
    return null;
  }

  /// Players only: the host has no cheap entity-in-box query, and scanning every
  /// entity of the world per move is not worth it.
  @override
  String? entityObstruction(WorldPos pos) {
    for (final player in server.getAllPlayers()) {
      if (player.isSpectator) continue;
      final playerWorld = player.getWorld();
      final same = playerWorld.getId() == _brain.worldId;
      playerWorld.dispose();
      if (!same) continue;
      final (px, py, pz) = player.getPosition();
      if (px + 0.3 > pos.x && px - 0.3 < pos.x + 1 && py + 1.8 > pos.y && py < pos.y + 1 && pz + 0.3 > pos.z && pz - 0.3 < pos.z + 1) {
        return 'Movement obstructed';
      }
    }
    return null;
  }

  static const Set<BlockFlagsFlag> _flags = {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.notifyNeighbors};

  @override
  Future<bool> moveTurtle(WorldPos to) async {
    final from = _brain.pos;
    final oldKey = turtle.key;
    final oldPos = CcWorldTurtles._blockPos(from);
    final newPos = CcWorldTurtles._blockPos(to);
    final oldState = owner._states.decode(world.getBlockStateId(pos: oldPos));
    // Waterlogged only when moving into a water source block, so that moving
    // does not create water (`TurtleBrain.teleportTo`).
    final target = world.getBlockState(pos: newPos);
    final intoWater = target.blockName == 'minecraft:water' && target.propertyMap['level'] == '0';
    final stateId = owner._states.encode(turtle.blockKey, {
      'facing': _brain.facing.name,
      'waterlogged': intoWater ? 'true' : 'false',
    });
    if (stateId == null) return false;
    await world.setBlockState(pos: newPos, state: stateId, updateFlags: const {BlockFlagsFlag.notifyListeners});
    if (!owner._states.isBlock(world.getBlockStateId(pos: newPos), turtle.blockKey)) return false;

    // The entity first (the client needs the turtle where it now is), then the
    // old block goes: its entity is removed with it, but the plugin no longer
    // tracks the old position.
    _brain.pos = to;
    owner._moved(turtle, oldKey);
    try {
      owner._writeEntity(world, turtle);
    } on PluginRegistryException catch (e) {
      logger.warn('Could not write the entity of the moved turtle at $to: ${e.message}');
      final newKey = turtle.key;
      _brain.pos = from;
      owner._moved(turtle, newKey);
      await world.setBlockByName(pos: newPos, name: 'minecraft:air', updateFlags: _flags);
      return false;
    }
    final wasWaterlogged = oldState?.values['waterlogged'] == 'true';
    await world.setBlockByName(pos: oldPos, name: wasWaterlogged ? 'minecraft:water' : 'minecraft:air', updateFlags: _flags);
    return true;
  }

  @override
  Future<void> setFacing(Dir direction) async {
    final pos = CcWorldTurtles._blockPos(_brain.pos);
    final next = owner._states.withValues(world.getBlockStateId(pos: pos), {'facing': direction.name});
    if (next != null) await world.setBlockState(pos: pos, state: next, updateFlags: const {BlockFlagsFlag.notifyListeners});
  }

  @override
  Future<void> removeBlock(WorldPos pos) async {
    final bp = CcWorldTurtles._blockPos(pos);
    final waterlogged = world.getBlockState(pos: bp).propertyMap['waterlogged'] == 'true';
    await world.setBlockByName(pos: bp, name: waterlogged ? 'minecraft:water' : 'minecraft:air', updateFlags: _flags);
  }

  @override
  Future<bool> placeBlock(WorldPos pos, String itemKey, Dir direction) async {
    // Blocks with entities of this plugin cannot be placed by a turtle (their
    // entity and id would be missing).
    if (itemKey.startsWith('computercraft:')) return false;
    final block = BlockRegistry.of(itemKey);
    if (block == null) return false;
    final defaults = block.defaultState.propertyMap;
    final horizontal = direction.isHorizontal ? direction : _brain.facing;
    final properties = <String, String>{};
    if (defaults.containsKey('axis')) {
      properties['axis'] = direction.dx != 0 ? 'x' : (direction.dz != 0 ? 'z' : 'y');
    }
    if (defaults.containsKey('facing')) {
      final name = block.name;
      final sameDirection = name.endsWith('_stairs') || name.endsWith('piston') || name.endsWith('_door') || name.endsWith('_trapdoor');
      final facing = defaults['facing'] == 'north' || defaults['facing'] == 'south' || defaults['facing'] == 'east' || defaults['facing'] == 'west'
          ? (sameDirection ? horizontal : horizontal.opposite)
          : horizontal.opposite;
      properties['facing'] = facing.name;
    }
    final stateId = BlockRegistry.resolveState(block.name, properties) ?? block.defaultStateId;
    await world.setBlockState(pos: CcWorldTurtles._blockPos(pos), state: stateId, updateFlags: _flags);
    return true;
  }

  @override
  Future<bool> replaceBlock(WorldPos pos, String blockName, {Map<String, String> properties = const {}}) async {
    final stateId = BlockRegistry.resolveState(blockName, properties);
    if (stateId == null) return false;
    await world.setBlockState(pos: CcWorldTurtles._blockPos(pos), state: stateId, updateFlags: _flags);
    return true;
  }

  @override
  Future<ContainerView?> containerAt(WorldPos pos) async {
    final entity = world.getBlockEntity(pos: CcWorldTurtles._blockPos(pos));
    if (entity == null) return null;
    final Inventory inventory;
    switch (entity) {
      case BlockEntityTypeChestBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeTrappedChestBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeBarrelBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeDispenserBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeDropperBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeHopperBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeFurnaceBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeBlastingFurnaceBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeSmokerBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeShulkerBoxBlockEntity(:final value):
        inventory = value.getContainer().getInventory();
      case BlockEntityTypeContainerBlockEntity(:final value):
        inventory = value.getInventory();
      default:
        return null;
    }
    return _HostContainer.open(inventory, owner._items);
  }

  @override
  Future<bool> attack(WorldPos pos, double damage) async {
    // The turtle's block centre and one and a half blocks along the direction
    // it faces (`TurtleTool.attack` clips 1.5 blocks); the entity hit first
    // takes the damage.
    final from = _brain.pos;
    final dx = pos.x - from.x;
    final dy = pos.y - from.y;
    final dz = pos.z - from.z;
    final start = (from.x + 0.5, from.y + 0.5, from.z + 0.5);
    final end = (from.x + 0.5 + dx * 1.5, from.y + 0.5 + dy * 1.5, from.z + 0.5 + dz * 1.5);
    final hit = world.rayTraceEntity(start: start, end: end);
    if (hit == null) return false;
    final living = hit.entity.asLiving();
    if (living == null) return false;
    await living.damage(amount: damage, damageType: DamageType.playerAttack);
    return true;
  }

  @override
  Future<void> syncClient() async => owner._writeEntity(world, turtle);
}

/// An inventory of a block in the world as a [ContainerView]. The slots are
/// read once when the view is opened (the host answers asynchronously and the
/// commands read them synchronously); [setStack] updates the snapshot and
/// writes to the host.
final class _HostContainer implements ContainerView {
  final Inventory _inventory;
  final HostItems _items;
  final List<TurtleStack?> _slots;

  _HostContainer._(this._inventory, this._items, this._slots);

  /// Reads every slot of [inventory].
  static Future<_HostContainer> open(Inventory inventory, HostItems items) async {
    final slots = <TurtleStack?>[];
    final size = inventory.getSize();
    for (var slot = 0; slot < size; slot++) {
      final stack = inventory.getItem(slot: slot);
      if (stack == null) {
        slots.add(null);
        continue;
      }
      final model = await items.fromHost(stack);
      stack.dispose();
      slots.add(model.isEmpty ? null : model);
    }
    return _HostContainer._(inventory, items, slots);
  }

  @override
  int get size => _slots.length;

  @override
  TurtleStack? stackAt(int slot) => _slots[slot]?.copy();

  @override
  Future<void> setStack(int slot, TurtleStack? stack) async {
    final value = stack == null || stack.isEmpty ? null : stack.copy();
    _slots[slot] = value;
    await _inventory.setItem(slot: slot, item: value == null ? null : await _items.toHost(value));
  }
}

// -- The menu's slots ------------------------------------------------------------------------------------

/// The 54 slots of the turtle menu over the turtle and the player. The menu
/// logic is synchronous, so the player's side is a snapshot ([open]) that
/// [read]/[write] work on and [commit] writes back to the host afterwards.
final class _MenuSlots implements MenuSlotAccess {
  final CcWorldTurtles _owner;
  final Player _player;
  final _Turtle _turtle;

  /// The player's 36 storage slots (hotbar first) and the off hand.
  final List<TurtleStack?> _storage;
  TurtleStack? _offhand;

  /// What the snapshot held when it was taken, as signatures.
  final List<String> _storageBefore;
  final String _offhandBefore;
  final Set<int> _dirty = {};
  bool _offhandDirty = false;

  _MenuSlots._(this._owner, this._player, this._turtle, this._storage, this._offhand)
    : _storageBefore = [for (final s in _storage) HostItems.signature(s)],
      _offhandBefore = HostItems.signature(_offhand);

  /// Reads the player's slots.
  static Future<_MenuSlots> open(CcWorldTurtles owner, Player player, _Turtle turtle) async {
    final inventory = player.getInventory().asInventory();
    final storage = <TurtleStack?>[];
    for (var i = 0; i < 36; i++) {
      final stack = inventory.getItem(slot: i);
      if (stack == null) {
        storage.add(null);
        continue;
      }
      final model = await owner._items.fromHost(stack);
      stack.dispose();
      storage.add(model.isEmpty ? null : model);
    }
    TurtleStack? offhand;
    final held = player.getInventory().getOffHand();
    if (held != null) {
      final model = await owner._items.fromHost(held);
      held.dispose();
      offhand = model.isEmpty ? null : model;
    }
    return _MenuSlots._(owner, player, turtle, storage, offhand);
  }

  /// Writes the player's slots that the logic changed to the host.
  Future<void> commit() async {
    final inventory = _player.getInventory().asInventory();
    for (final slot in _dirty.toList()..sort()) {
      final stack = _storage[slot];
      if (HostItems.signature(stack) == _storageBefore[slot]) continue;
      await inventory.setItem(slot: slot, item: stack == null ? null : await _owner._items.toHost(stack));
    }
    _dirty.clear();
    if (_offhandDirty && HostItems.signature(_offhand) != _offhandBefore) {
      final stack = _offhand;
      await _player.getInventory().setOffHand(item: stack == null ? null : await _owner._items.toHost(stack));
    }
    _offhandDirty = false;
  }

  TurtleBrain get _brain => _turtle.brain;

  @override
  int maxStack(String item) => _owner._items.maxStack(item);

  @override
  TurtleStack? read(int slot) {
    if (slot >= 0 && slot < TurtleMenuLayout.turtleSlots) return _brain.inventory[slot]?.copy();
    if (TurtleMenuLayout.isUpgrade(slot)) {
      final instance = _brain.upgradeOn(slot == TurtleMenuLayout.leftUpgrade ? TurtleSide.left : TurtleSide.right);
      return instance == null ? null : TurtleStack(instance.upgrade.item, 1);
    }
    final inventorySlot = TurtleMenuLayout.inventorySlotOfMenu(slot);
    if (inventorySlot < 0) return null;
    return _storage[inventorySlot]?.copy();
  }

  @override
  void write(int slot, TurtleStack? stack) {
    final value = stack == null || stack.isEmpty ? null : stack;
    if (slot >= 0 && slot < TurtleMenuLayout.turtleSlots) {
      _brain.inventory[slot] = value?.copy();
      _brain.saveDirty = true;
      return;
    }
    if (TurtleMenuLayout.isUpgrade(slot)) {
      final side = slot == TurtleMenuLayout.leftUpgrade ? TurtleSide.left : TurtleSide.right;
      final upgrade = value == null ? null : _brain.upgradeTable.forItem(value);
      final current = _brain.upgradeOn(side);
      if (upgrade == null) {
        _brain.setUpgrade(side, null);
      } else if (current == null || current.upgrade.key != upgrade.key) {
        _brain.setUpgrade(side, UpgradeInstance(upgrade));
      }
      return;
    }
    final inventorySlot = TurtleMenuLayout.inventorySlotOfMenu(slot);
    if (inventorySlot < 0) return;
    _storage[inventorySlot] = value?.copy();
    _dirty.add(inventorySlot);
  }

  @override
  bool mayPlace(int slot, TurtleStack stack) =>
      !TurtleMenuLayout.isUpgrade(slot) || _brain.upgradeTable.forItem(stack) != null;

  @override
  TurtleStack? readOffhand() => _offhand?.copy();

  @override
  void writeOffhand(TurtleStack? stack) {
    _offhand = stack == null || stack.isEmpty ? null : stack.copy();
    _offhandDirty = true;
  }

  @override
  bool get isCreative => _player.isCreative;
}
