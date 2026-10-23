// The peripheral blocks of CC: Tweaked in the world: the disk drives (with
// their media), the printers, the speakers, the redstone relays, the wired
// modems and cables, and a computer or turtle as a peripheral of its
// neighbours.
//
// Java gets all of this from the block entity's peripheral capability
// (`ModRegistry.registerPeripherals`, `ModRegistry.java:679-696`): CC looks at
// the block next to a computer and asks it for its `IPeripheral`. The host has
// the same events (a block entity load/unload, a neighbour update, a use), so
// this file plays the part of that capability lookup: it tracks the block
// entities, makes one peripheral per block and puts it on the sides of the
// computers that touch it.
//
// What is not a faithful port, with the reason:
//
// * The **inventory** of a drive and of a printer does not exist: a plugin
//   block entity has no container (`menus.wit` has slots but a menu needs a
//   player looking at it). The disk of a drive and the ink and paper of a
//   printer therefore live in the block entity's own save data, and a player
//   puts them in by right clicking the block with the item
//   (`DiskDriveBlock.defaultUseItemOn` does the same for a disk). A finished
//   page is dropped in front of the printer instead of landing in its tray.
// * The **disk contents** are the plugin's own storage (`disks/<id>/` in its
//   data folder, `disks.json` for the id counter) rather than CC's
//   `disk_storage.bin`; a treasure disk reads the mod jar's
//   `data/computercraft/lua/treasure/<path>`. The drive's save-data keys are
//   the plugin's own.
// * A vanilla command block as a peripheral (`command`) is **absent**: the host
//   gives a vanilla block entity's NBT only as opaque bytes
//   (`world.getBlockEntityNbt`) and the Dart API has no NBT byte codec, so
//   `getCommand`/`setCommand` cannot be implemented, and `runCommand`'s result
//   would need `execute-command-captured`, which is not in this checkout's
//   bindings. The peripheral was not registered at all, so `peripheral.find`
//   does not see it.
// * The drive has **no `playAudio`/`stopAudio`**: the `play_record` payload
//   needs the record's jukebox song from the datapack registry
//   `minecraft:jukebox_song`, which the host does not expose. `hasAudio` and
//   `getAudioTitle` do exist (they read the item's component).
// * A **wired network** is a graph of the adjacent cable/wired-modem blocks
//   built here, with the same connectivity as Java's `WiredElement` graph. A
//   full modem has one peripheral for the whole block (Java has one per side).
// * The bundled redstone methods of a relay (`getBundledInput`,
//   `setBundledOutput`, ...) are **state only**: the host has no bundled signal
//   query, so nothing of them reaches the world. The same is true of the
//   `redstone` API of a computer (audit A9), which this file does not change.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../compat/simulated_attach.dart';
import '../machine/media.dart';
import '../machine/mounts.dart';
import '../machine/peripheral.dart';
import '../machine/peripherals.dart';
import '../machine/side.dart';
import '../machine/zip.dart';
import '../protocol/components.dart';
import 'block_states.dart';
import 'network.dart';
import 'service.dart';
import 'storage.dart';

/// The block entity types this file drives.
const String _driveType = 'computercraft:disk_drive';
const String _printerType = 'computercraft:printer';
const String _speakerType = 'computercraft:speaker';
const String _relayType = 'computercraft:redstone_relay';
const String _cableType = 'computercraft:cable';
const String _fullModemType = 'computercraft:wired_modem_full';

/// The computer blocks that are a peripheral of their neighbours
/// (`ComputerPeripheral`, type `computer`; a command computer is not one in CC
/// either, `ModRegistry.java:680-683`).
const Map<String, String> _computerBlocks = {
  'computercraft:computer_normal': 'computer',
  'computercraft:computer_advanced': 'computer',
};

/// The turtle blocks, which are a `turtle` peripheral (`TurtleBlockEntity.java:362`).
const Map<String, String> _turtleBlocks = {
  'computercraft:turtle_normal': 'turtle',
  'computercraft:turtle_advanced': 'turtle',
};

/// The space a floppy disk has (`ConfigSpec.floppySpaceLimit`).
const int _floppySpaceLimit = 125000;

/// The ink colour of each vanilla dye (`ColourUtils`, which maps a dye item to
/// a colour index).
const Map<String, int> _dyeColours = {
  'white_dye': 0,
  'orange_dye': 1,
  'magenta_dye': 2,
  'light_blue_dye': 3,
  'yellow_dye': 4,
  'lime_dye': 5,
  'pink_dye': 6,
  'gray_dye': 7,
  'light_gray_dye': 8,
  'cyan_dye': 9,
  'purple_dye': 10,
  'blue_dye': 11,
  'brown_dye': 12,
  'green_dye': 13,
  'red_dye': 14,
  'black_dye': 15,
};

/// Every world direction, for the redstone reads of a relay.
const List<BlockDirection> _allDirections = [
  BlockDirection.up,
  BlockDirection.down,
  BlockDirection.north,
  BlockDirection.south,
  BlockDirection.east,
  BlockDirection.west,
];

/// The peripheral blocks of CC: Tweaked in the world.
final class CcWorldPeripherals {
  final CcService _service;
  final CcNetwork _network;
  final CcBlockStates _states;

  /// The tracked blocks, by `world|x|y|z`.
  final Map<String, _Drive> _drives = {};
  final Map<String, _Printer> _printers = {};
  final Map<String, _Speaker> _speakers = {};
  final Map<String, _Relay> _relays = {};

  /// Every cable and wired modem block (a cable without a modem carries the
  /// network but has no peripheral), and the modems among them.
  final Map<String, String> _wired = {};
  final Map<String, _Modem> _modems = {};

  /// The computers and turtles whose block entity was read, by position: the
  /// type their neighbours see and their id.
  final Map<String, _ComputerBox> _computers = {};

  /// An attach that found no machine yet, retried for a while: the chunk load
  /// order of two blocks of the same chunk is not ours.
  final List<(String, (int, int, int), (int, int, int))> _pending = [];

  /// Ejections and printed pages that need a `Server` handle: they happen in
  /// the tick, which has a fresh one.
  final List<String> _pendingEjects = [];
  final List<(String, BlockPos, ItemStack)> _pendingPages = [];

  /// The next id of a disk (Java: `IDAssigner.DISK`, the level's `next_id`).
  int _nextDiskId = 0;

  /// The ids the wired network hands out (`ServerContext.getNextId`): one
  /// counter per peripheral type.
  final Map<String, int> _nextPeripheralIds = {};

  int _pendingTicks = 0;
  bool _ticking = false;

  CcWorldPeripherals(this._service, this._network, this._states) {
    _loadDisks();
  }

  /// How many peripheral blocks (drives, printers, speakers, relays, modems)
  /// are tracked.
  int get blockCount => _drives.length + _printers.length + _speakers.length + _relays.length + _modems.length;

  /// How many disk ids the server has handed out.
  int get diskCount => _nextDiskId;

  /// How many cable or modem blocks the wired network spans.
  int get wiredCount => _wired.length;

  /// How many computers are visible as peripherals of their neighbours.
  int get computerCount => _computers.length;

  static String _key(String world, BlockPos pos) => '$world|${pos.x}|${pos.y}|${pos.z}';

  static BlockPos _pos(String key) {
    final parts = key.split('|');
    return BlockPos(x: int.parse(parts[1]), y: int.parse(parts[2]), z: int.parse(parts[3]));
  }

  static String _worldOf(String key) => key.split('|').first;

  static BlockPos _offset(BlockPos pos, (int, int, int) offset) =>
      BlockPos(x: pos.x + offset.$1, y: pos.y + offset.$2, z: pos.z + offset.$3);

  /// Listens for the events that drive the peripheral blocks.
  void install(Context context) {
    context.intercept(Events.playerUseBlock, _onUseBlock);
    context.listen(Events.blockEntityLoad, _onEntityLoad);
    context.listen(Events.blockEntityUnload, _onEntityUnload);
    context.listen(Events.blockPlace, _onBlockPlace);
    _installNeighbourRefresh(context);
  }

  /// The blocks whose neighbour changing matters: a neighbour may be a computer
  /// (which then gets a peripheral) or another cable (which changes the wired
  /// network).
  void _installNeighbourRefresh(Context context) {
    final behavior = BlockBehavior(onNeighborUpdate: (server, event) => _onNeighbourUpdate(server, event));
    for (final key in [
      _driveType,
      _printerType,
      _speakerType,
      _relayType,
      _cableType,
      _fullModemType,
      ..._computerBlocks.keys,
      ..._turtleBlocks.keys,
    ]) {
      try {
        context.registerBlockBehavior(key, behavior);
      } on HostException catch (e) {
        logger.warn('Could not listen for the neighbours of $key: $e');
      }
    }
  }

  // -- Events -------------------------------------------------------------------

  /// A block entity came with its chunk.
  void _onEntityLoad(Server server, BlockEntityLoadEventData event) {
    final worldId = event.targetWorld.getId();
    final pos = event.pos;
    final kind = event.typeKey;
    final key = _key(worldId, pos);

    final computerType = _computerBlocks[kind] ?? _turtleBlocks[kind];
    if (computerType != null) {
      _computers[key] = _ComputerBox(computerType, event.save.getInt('ComputerId'));
      _attachAround(server, worldId, pos);
      return;
    }

    switch (kind) {
      case _driveType:
        _drives[key] = _drive(worldId, pos, event.save);
      case _printerType:
        _printers[key] = _printer(worldId, pos, event.save);
      case _speakerType:
        _speakers[key] = _speaker(worldId, pos);
      case _relayType:
        _relays[key] = _relay(worldId, pos, _facingAt(event.targetWorld, pos));
      case _cableType || _fullModemType:
        _wired[key] = kind;
        final modem = _modem(worldId, pos, kind, event.save, _modemVariantAt(event.targetWorld, pos, kind));
        if (modem != null) _modems[key] = modem;
        _rebuildNetworks();
      default:
        return;
    }
    _attachAround(server, worldId, pos);
  }

  /// The block entity is gone (its chunk unloaded, or its block was broken).
  void _onEntityUnload(Server server, BlockEntityUnloadEventData event) {
    final worldId = event.targetWorld.getId();
    final pos = event.pos;
    final kind = event.typeKey;
    final key = _key(worldId, pos);

    if (_computerBlocks.containsKey(kind) || _turtleBlocks.containsKey(kind)) {
      _computers.remove(key);
      _detachAround(worldId, pos);
      return;
    }
    switch (kind) {
      case _driveType:
        _drives.remove(key);
      case _printerType:
        _printers.remove(key);
      case _speakerType:
        _speakers.remove(key);
      case _relayType:
        _relays.remove(key);
      case _cableType || _fullModemType:
        _wired.remove(key);
        _modems.remove(key);
        _rebuildNetworks();
      default:
        return;
    }
    _detachAround(worldId, pos);
  }

  /// A neighbour of one of our blocks changed: a computer may have appeared or
  /// gone, or a cable's shape changed.
  void _onNeighbourUpdate(Server server, CustomBlockNeighborUpdateEventData event) {
    final worldId = event.targetWorld.getId();
    final pos = event.pos;
    final key = _key(worldId, pos);
    if (_modems.containsKey(key)) {
      final modem = _modems[key]!;
      final variant = _modemVariantAt(event.targetWorld, pos, modem.typeKey);
      if (variant != modem.variant) {
        modem.variant = variant;
        // A cable that gained a modem now has a peripheral; one that lost it
        // does not (`CableBlockEntity.invalidateCapability`).
        final had = _modems.remove(key) != null;
        if (variant == 'none' || (modem.typeKey == _fullModemType && variant != 'true')) {
          if (had) _rebuildNetworks();
        } else {
          _modems[key] = modem;
        }
      }
      _refreshModem(worldId, pos);
      _rebuildNetworks();
    }
    if (_drives.containsKey(key) || _printers.containsKey(key) || _speakers.containsKey(key) || _relays.containsKey(key)) {
      _attachAround(server, worldId, pos);
    }
    if (_computers.containsKey(key)) {
      _attachAround(server, worldId, pos);
    }
    // A peripheral block may have been placed next to a computer that this file
    // tracks: the computer sees it from here, because a block of another mod
    // does not get a neighbour update from us.
    for (final entry in SimulatedAttach.neighbours.values) {
      final neighbour = _offset(pos, entry.$1);
      final neighbourKey = _key(worldId, neighbour);
      if (_peripheralAt(worldId, neighbour) != null) _attachPair(server, worldId, pos, neighbour);
      if (_computers.containsKey(neighbourKey)) _attachPair(server, worldId, neighbour, pos);
    }
  }

  /// Right click: put a disk in a drive, or ink or paper in a printer.
  Future<PlayerUseBlockEventData> _onUseBlock(Server server, PlayerUseBlockEventData event) async {
    final kind = event.block;
    if (kind != _driveType && kind != _printerType) return event;
    final player = event.player;
    final world = player.getWorld();
    try {
      final worldId = world.getId();
      final key = _key(worldId, event.blockPos);
      final itemKey = await event.item.getRegistryKey();
      final count = await event.item.getCount();

      final drive = _drives[key];
      if (kind == _driveType && drive != null && drive.media == null) {
        final media = await _mediaFor(itemKey, event.item);
        if (media == null) return event;
        if (media is TreasureDisk) drive.treasurePath = _treasurePath(itemKey, event.item);
        _insertDisk(world, drive, media);
        await _consume(event, count);
        return event.cancel();
      }

      final printer = _printers[key];
      if (kind == _printerType && printer != null) {
        final dye = _dyeColours[itemKey.split(':').last];
        if (dye != null) {
          printer.ink += count;
          printer.inkColour = dye;
          _applySupplies(printer);
          _writePrinter(world, printer);
          await _consume(event, count);
          return event.cancel();
        }
        if (itemKey == 'minecraft:paper' ||
            itemKey == 'computercraft:printed_page' ||
            itemKey == 'computercraft:printed_pages') {
          printer.paper += count;
          final bytes = event.item.customComponent(CcComponents.key('printout'));
          final printout = bytes == null ? null : CcComponents.decodePrintout(bytes);
          if (printout != null) {
            printer.peripheral.setNextPrintout(Printout(printout.$1, printout.$2));
          }
          _applySupplies(printer);
          _writePrinter(world, printer);
          await _consume(event, count);
          return event.cancel();
        }
      }
      return event;
    } finally {
      player.dispose();
    }
  }

  /// A block was placed: the block entity is created a tick later, like the
  /// computers (`AbstractComputerBlock`'s `setPlacedBy` is the entity's own).
  void _onBlockPlace(Server server, BlockPlaceEventData event) {
    if (event.cancelled) return;
    final kind = event.blockPlaced;
    if (kind != _driveType &&
        kind != _printerType &&
        kind != _speakerType &&
        kind != _relayType &&
        kind != _cableType &&
        kind != _fullModemType) {
      return;
    }
    final player = event.player;
    final world = player.getWorld();
    final String worldId;
    try {
      worldId = world.getId();
    } finally {
      world.dispose();
    }
    final pos = event.blockPos;
    server.runLater(1, (server) => _adoptPlaced(server, worldId, pos, kind));
  }

  /// Creates the block entity of a placed peripheral block (the host does not
  /// create one for a plugin block).
  void _adoptPlaced(Server server, String worldId, BlockPos pos, String kind) {
    final world = server.getWorldByName(name: worldId);
    if (world == null) return;
    try {
      if (!_states.isBlock(world.getBlockStateId(pos: pos), kind)) return;
      if (world.pluginBlockEntityAt(pos) != null) return;
      world.setPluginBlockEntity(pos, kind, NbtCompound());
      _onEntityLoad(
        server,
        BlockEntityLoadEventData(
          targetWorld: world,
          pos: pos,
          typeKey: kind,
          saveData: NbtCompound().toTree(),
          clientData: null,
        ),
      );
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the block entity of $kind at $pos: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  // -- Attaching to computers -----------------------------------------------------

  /// Attaches the peripherals of the blocks around [pos] to the computers next
  /// to them (and detaches the ones that are gone).
  void _attachAround(Server server, String worldId, BlockPos pos) {
    for (final entry in SimulatedAttach.neighbours.values) {
      final offset = entry.$1;
      final neighbour = _offset(pos, offset);
      if (_peripheralAt(worldId, pos) != null) _attachPair(server, worldId, neighbour, pos);
      if (_peripheralAt(worldId, neighbour) != null) _attachPair(server, worldId, pos, neighbour);
    }
  }

  /// Attaches the peripheral of the block at [block] to the computer at
  /// [computerPos], on the side that faces the block; detaches it when the
  /// block has no peripheral any more.
  void _attachPair(Server server, String worldId, BlockPos computerPos, BlockPos block) {
    final box = _computers[_key(worldId, computerPos)];
    if (box == null) return;
    final id = box.computerId;
    if (id == null || id < 0) return;
    final side = SimulatedAttach.sideTowards(
      (computerPos.x, computerPos.y, computerPos.z),
      (block.x, block.y, block.z),
    );
    if (side == null) return;

    final peripheral = _peripheralAt(worldId, block);
    if (peripheral == null) {
      final existing = _service.peripheral(id, side);
      if (existing != null && _isOurs(existing)) _service.detachExternal(id, side);
      return;
    }
    if (identical(_service.peripheral(id, side), peripheral)) return;
    if (!_service.hasComputer(id)) {
      final pending = (worldId, (computerPos.x, computerPos.y, computerPos.z), (block.x, block.y, block.z));
      if (!_pending.contains(pending)) _pending.add(pending);
      return;
    }
    _service.attachExternal(id, side, peripheral);
  }

  /// Detaches what the blocks around [pos] had on the computers next to them.
  void _detachAround(String worldId, BlockPos pos) {
    final peripheral = _peripheralAt(worldId, pos);
    for (final entry in SimulatedAttach.neighbours.values) {
      final neighbour = _offset(pos, entry.$1);
      final box = _computers[_key(worldId, neighbour)];
      final id = box?.computerId;
      if (id == null || id < 0) continue;
      final side = SimulatedAttach.sideTowards(
        (neighbour.x, neighbour.y, neighbour.z),
        (pos.x, pos.y, pos.z),
      );
      if (side == null) continue;
      final attached = _service.peripheral(id, side);
      if (attached != null && (identical(attached, peripheral) || (peripheral == null && _isOurs(attached)))) {
        _service.detachExternal(id, side);
      }
    }
  }

  /// Whether [peripheral] is one of the ones this file attaches (so it may be
  /// detached; a monitor or a modem of the computer's own record is not ours).
  static bool _isOurs(Peripheral peripheral) =>
      peripheral is DiskDrivePeripheral ||
      peripheral is PrinterPeripheral ||
      peripheral is SpeakerPeripheral ||
      peripheral is RedstoneRelayPeripheral ||
      peripheral is WiredModem ||
      peripheral is ComputerPeripheral;

  /// The peripheral the block at [pos] exposes, or null when it has none.
  Peripheral? _peripheralAt(String worldId, BlockPos pos) {
    final key = _key(worldId, pos);
    return _drives[key]?.peripheral ??
        _printers[key]?.peripheral ??
        _speakers[key]?.peripheral ??
        _relays[key]?.peripheral ??
        _modems[key]?.peripheral ??
        _computerPeripheral(key);
  }

  /// The `computer`/`turtle` peripheral of the computer at [key].
  ComputerPeripheral? _computerPeripheral(String key) {
    final box = _computers[key];
    final id = box?.computerId;
    if (box == null || id == null || id < 0) return null;
    return ComputerPeripheral(box.type, _ServiceComputer(_service, id));
  }

  // -- The server tick --------------------------------------------------------------

  /// Plays the speakers, drives the relays' redstone, drops the ejected disks
  /// and the printed pages, and retries the attaches that found no machine.
  Future<void> tick(Server server) async {
    _pendingTicks++;
    if (_ticking) return;
    _ticking = true;
    try {
      final now = _service.nowMicros * 1000;
      for (final speaker in _speakers.values) {
        speaker.sink.server = server;
        speaker.peripheral.update(now);
      }
      for (final relay in _relays.values) {
        await _tickRelay(server, relay);
      }
      for (final drive in _drives.values) {
        _persistLabel(server, drive);
      }
      if (_pendingEjects.isNotEmpty) await _flushEjects(server);
      if (_pendingPages.isNotEmpty) await _flushPages(server);
      // A block entity whose machine was not up yet: retried for five seconds
      // (a hundred ticks), then given up (the computer is not coming back
      // without its chunk).
      if (_pending.isNotEmpty) {
        if (_pendingTicks % 20 == 0) await _flushPending(server);
      }
    } catch (e, s) {
      logger.error('The peripheral block tick failed: $e\n$s');
    } finally {
      _ticking = false;
    }
  }

  /// The label of the disk in a drive changed (`setDiskLabel` writes it to the
  /// item in Java, which has the disk in its inventory): keep the entity's copy
  /// in step, so the label survives a reload.
  void _persistLabel(Server server, _Drive drive) {
    final label = drive.media?.label;
    if (label == (drive.data.getString('DiskLabel') ?? '')) return;
    if (label == null) {
      drive.data.remove('DiskLabel');
    } else {
      drive.data.putString('DiskLabel', normaliseLabel(label));
    }
    _writeEntity(server, drive.world, drive.pos, _driveType, drive.data);
  }

  Future<void> _flushEjects(Server server) async {
    final keys = List.of(_pendingEjects);
    _pendingEjects.clear();
    for (final key in keys) {
      final drive = _drives[key];
      if (drive != null) await _ejectDisk(server, drive);
    }
  }

  Future<void> _flushPages(Server server) async {
    final pages = List.of(_pendingPages);
    _pendingPages.clear();
    for (final (worldId, pos, stack) in pages) {
      final world = server.getWorldByName(name: worldId);
      if (world == null) continue;
      try {
        await world.spawnItem(
          pos: (pos.x + 0.5, pos.y + 1.0, pos.z + 0.5),
          stack: stack,
          velocity: (0, 0, 0),
          pickupDelay: 10,
        );
      } finally {
        world.dispose();
      }
    }
  }

  Future<void> _flushPending(Server server) async {
    final pending = List.of(_pending);
    _pending.clear();
    for (final (worldId, computer, block) in pending) {
      _attachPair(server, worldId, BlockPos(x: computer.$1, y: computer.$2, z: computer.$3),
          BlockPos(x: block.$1, y: block.$2, z: block.$3));
    }
  }

  /// The relay: read the six inputs and publish the six outputs
  /// (`RedstoneRelayBlockEntity.update`).
  Future<void> _tickRelay(Server server, _Relay relay) async {
    final world = server.getWorldByName(name: relay.world);
    if (world == null) return;
    try {
      final pos = relay.pos;
      var changed = false;
      for (final direction in _allDirections) {
        final power = await world.getRedstonePower(pos: pos, direction: direction);
        final side = _localSide(relay.facing, _sideOfDirection(direction));
        if (relay.peripheral.redstone.setInput(side, power, 0)) changed = true;
      }
      if (changed) relay.peripheral.redstoneChanged();

      final changes = relay.peripheral.redstone.updateOutput();
      if (changes == 0) return;
      for (final direction in _allDirections) {
        final side = _localSide(relay.facing, _sideOfDirection(direction));
        if ((changes & (1 << side.index)) == 0) continue;
        final level = relay.peripheral.redstone.getExternalOutput(side);
        await world.setBlockRedstoneOutputFace(pos: pos, face: direction, weak: level, strong: level);
        await world.updateNeighbors(pos: pos, sourceBlock: relay.blockKey);
      }
    } finally {
      world.dispose();
    }
  }

  /// `DirectionUtil.toLocal(facing, side)`: the Lua side of a block whose
  /// `facing` is [facing] for the world direction [side]. `right` is the
  /// clockwise side of the facing, as it is for a computer (facing north,
  /// right is east).
  static ComputerSide _localSide(BlockDirection facing, ComputerSide side) {
    if (side == ComputerSide.top || side == ComputerSide.bottom) return side;
    if (side == _sideOfDirection(facing)) return ComputerSide.front;
    if (side == _sideOfDirection(_oppositeDirection(facing))) return ComputerSide.back;
    if (side == _sideOfDirection(_clockwise(facing))) return ComputerSide.right;
    return ComputerSide.left;
  }

  static BlockDirection _clockwise(BlockDirection direction) => switch (direction) {
    BlockDirection.north => BlockDirection.east,
    BlockDirection.east => BlockDirection.south,
    BlockDirection.south => BlockDirection.west,
    _ => BlockDirection.north,
  };

  static BlockDirection _oppositeDirection(BlockDirection direction) => switch (direction) {
    BlockDirection.north => BlockDirection.south,
    BlockDirection.south => BlockDirection.north,
    BlockDirection.east => BlockDirection.west,
    BlockDirection.west => BlockDirection.east,
    BlockDirection.up => BlockDirection.down,
    BlockDirection.down => BlockDirection.up,
  };

  /// The Lua side that looks towards the world direction [direction], for a
  /// block whose `facing` is north.
  static ComputerSide _sideOfDirection(BlockDirection direction) => switch (direction) {
    BlockDirection.north => ComputerSide.front,
    BlockDirection.south => ComputerSide.back,
    BlockDirection.east => ComputerSide.right,
    BlockDirection.west => ComputerSide.left,
    BlockDirection.up => ComputerSide.top,
    BlockDirection.down => ComputerSide.bottom,
  };

  // -- Drives ----------------------------------------------------------------------

  _Drive _drive(String worldId, BlockPos pos, NbtCompound save) {
    final key = _key(worldId, pos);
    final drive = _Drive(key, worldId, pos, save, DiskDrivePeripheral(_HostDrive(this, key)));
    _restoreMedia(save, drive);
    return drive;
  }

  /// Rebuilds the media of a drive from its save data.
  void _restoreMedia(NbtCompound save, _Drive drive) {
    final kind = save.getString('DiskKind');
    if (kind == null) return;
    if (kind == 'treasure') {
      final media = _treasureDisk(save.getString('TreasurePath'), save.getString('TreasureTitle') ?? '');
      if (media != null) drive.setMedia(media, path: save.getString('TreasurePath'));
      return;
    }
    if (kind == 'record') {
      drive.setMedia(RecordDisk(save.getString('DiskLabel')));
      return;
    }
    final id = save.getInt('DiskId');
    if (id == null || id < 0) return;
    drive.setMedia(
      DataDisk(StoreMount(DataFolderStore(_service.folder, 'disks/$id'), _floppySpaceLimit), id, save.getString('DiskLabel')),
    );
  }

  /// The media of the item [itemKey] with [stack], or null when the item is not
  /// a media of ours.
  Future<Media?> _mediaFor(String itemKey, ItemStack stack) async {
    switch (itemKey) {
      case 'computercraft:disk':
        final existing = stack.customComponent(CcComponents.key('disk_id'));
        final id = existing == null ? _allocateDiskId() : CcComponents.decodeComputerId(existing);
        final label = (await stack.getCustomName())?.getText();
        return DataDisk(
          StoreMount(DataFolderStore(_service.folder, 'disks/$id'), _floppySpaceLimit),
          id,
          label,
        );
      case 'computercraft:treasure_disk':
        final component = stack.customComponent(CcComponents.key('treasure_disk'));
        if (component == null) return null;
        final (title, path) = CcComponents.decodeTreasureDisk(component);
        return _treasureDisk(path, title);
    }
    // A vanilla record (`RecordMedia` in Java: anything the jukebox registry
    // says is playable). The song is in a datapack registry the plugin cannot
    // read, so the disk has audio but no title.
    if (itemKey.split(':').last.startsWith('music_disc')) return RecordDisk();
    return null;
  }

  String? _treasurePath(String itemKey, ItemStack stack) {
    final component = stack.customComponent(CcComponents.key('treasure_disk'));
    if (component == null) return null;
    return CcComponents.decodeTreasureDisk(component).$2;
  }

  /// A treasure disk's mount: the mod jar's `lua/treasure/<path>` (Java falls
  /// back to `deprecated/<path>`).
  Media? _treasureDisk(String? path, String title) {
    final archive = _service.image.archive;
    if (archive == null || path == null || path.isEmpty) return null;
    const root = 'data/computercraft/lua/treasure/';
    for (final candidate in [path, 'deprecated/$path']) {
      try {
        final mount = ArchiveMount(archive, '$root$candidate/');
        if (mount.fileCount == 0) continue;
        return TreasureDisk(mount, title);
      } on ZipException {
        continue;
      }
    }
    return null;
  }

  /// Puts [media] in [drive] and writes the entity
  /// (`DiskDriveBlockEntity.setDiskStack`).
  void _insertDisk(World world, _Drive drive, Media media) {
    drive.setMedia(media, path: drive.treasurePath);
    final data = drive.data;
    data
      ..putString('DiskKind', media is TreasureDisk ? 'treasure' : (media is RecordDisk ? 'record' : 'disk'))
      ..putInt('DiskId', media.diskId ?? -1);
    if (media.label != null) data.putString('DiskLabel', normaliseLabel(media.label!));
    if (media is TreasureDisk) {
      data
        ..putString('TreasureTitle', media.title)
        ..putString('TreasurePath', drive.treasurePath ?? '');
    }
    world.setPluginBlockEntity(drive.pos, _driveType, data);
  }

  /// The disk of [drive] leaves it: the item is dropped in front of the drive
  /// (`DiskDriveBlockEntity.ejectDisk`), with the id it had. The drop happens
  /// in the tick, which has a `Server`.
  void _queueEject(_Drive drive) {
    if (drive.media == null) return;
    if (!_pendingEjects.contains(drive.key)) _pendingEjects.add(drive.key);
  }

  Future<void> _ejectDisk(Server server, _Drive drive) async {
    final media = drive.media;
    if (media == null) return;
    drive.setMedia(null);
    final data = drive.data;
    for (final key in ['DiskKind', 'DiskId', 'DiskLabel', 'TreasurePath', 'TreasureTitle']) {
      data.remove(key);
    }
    _writeEntity(server, drive.world, drive.pos, _driveType, data);

    final itemKey = media is TreasureDisk ? 'computercraft:treasure_disk' : 'computercraft:disk';
    final stack = ItemStack.create(registryKey: itemKey, count: 1);
    if (media is DataDisk) {
      stack.setCustomComponent(CcComponents.key('disk_id'), CcComponents.encodeComputerId(media.id));
    }
    if (media is TreasureDisk) {
      stack.setCustomComponent(
        CcComponents.key('treasure_disk'),
        CcComponents.encodeTreasureDisk(media.title, drive.treasurePath ?? ''),
      );
    }
    final label = media.label;
    if (label != null) await stack.setCustomName(name: Text(label).build());

    final world = server.getWorldByName(name: drive.world);
    if (world == null) return;
    try {
      await world.spawnItem(
        pos: (drive.pos.x + 0.5, drive.pos.y + 0.7, drive.pos.z + 0.5),
        stack: stack,
        velocity: (0, 0, 0),
        pickupDelay: 10,
      );
    } finally {
      world.dispose();
    }
  }

  int _allocateDiskId() {
    final id = _nextDiskId++;
    _saveDisks();
    return id;
  }

  void _loadDisks() {
    try {
      final json = _service.folder.readJson('disks.json');
      if (json is Map<String, Object?> && json['next_id'] is num) {
        _nextDiskId = (json['next_id']! as num).toInt();
      }
    } on FileException catch (e) {
      if (!e.isNotFound) logger.error('Could not read disks.json: $e');
    } on FormatException catch (e) {
      logger.error('disks.json is not valid, starting from 0: $e');
    }
  }

  void _saveDisks() {
    try {
      _service.folder.writeJson('disks.json', {'next_id': _nextDiskId});
    } on FileException catch (e) {
      logger.error('Could not save disks.json: $e');
    }
  }

  // -- Printers --------------------------------------------------------------------

  _Printer _printer(String worldId, BlockPos pos, NbtCompound save) {
    final key = _key(worldId, pos);
    final peripheral = PrinterPeripheral(onPage: (page) => _queuePage(worldId, pos, page));
    final printer = _Printer(key, worldId, pos, save, peripheral);
    printer
      ..ink = save.getInt('Ink') ?? 0
      ..paper = save.getInt('Paper') ?? 0
      ..inkColour = save.getInt('InkColour') ?? 15;
    _applySupplies(printer);
    return printer;
  }

  void _applySupplies(_Printer printer) =>
      printer.peripheral.setSupplies(ink: printer.ink, paper: printer.paper, inkColour: printer.inkColour);

  void _writePrinter(World world, _Printer printer) {
    printer.data
      ..putInt('Ink', printer.ink)
      ..putInt('Paper', printer.paper)
      ..putInt('InkColour', printer.inkColour);
    world.setPluginBlockEntity(printer.pos, _printerType, printer.data);
  }

  /// A finished page: the printed page item is dropped in front of the printer
  /// (Java puts it in the printer's output tray, which needs its inventory).
  void _queuePage(String worldId, BlockPos pos, Printout page) {
    final stack = ItemStack.create(registryKey: 'computercraft:printed_page', count: 1);
    stack.setCustomComponent(
      CcComponents.key('printout'),
      CcComponents.encodePrintout(page.title, page.lines),
    );
    _pendingPages.add((worldId, pos, stack));
  }

  // -- Speakers --------------------------------------------------------------------

  _Speaker _speaker(String worldId, BlockPos pos) {
    final key = _key(worldId, pos);
    final at = (pos.x + 0.5, pos.y + 0.5, pos.z + 0.5);
    final sink = CcSpeakerSink(_network, newSpeakerSource(), worldId, () => at);
    return _Speaker(key, worldId, pos, NbtCompound(), SpeakerPeripheral(sink: sink, position: at), sink);
  }

  // -- Relays ----------------------------------------------------------------------

  _Relay _relay(String worldId, BlockPos pos, BlockDirection facing) {
    final key = _key(worldId, pos);
    return _Relay(key, worldId, pos, NbtCompound(), RedstoneRelayPeripheral())..facing = facing;
  }

  /// The `facing` state of the relay at [pos] (`DirectionUtil.toLocal` reads the
  /// block's own facing, so a relay's Lua sides are relative to where it was
  /// placed).
  BlockDirection _facingAt(World world, BlockPos pos) {
    final state = _states.decode(world.getBlockStateId(pos: pos));
    final facing = state?.values['facing'];
    return (facing == null ? null : BlockDirection.fromWireName(facing)) ?? BlockDirection.north;
  }

  /// The `modem` property of a cable at [pos]: `none` means the cable carries
  /// the network but has no modem; a full wired modem has its own `modem`
  /// boolean (`WiredModemFullBlockBlock.MODEM_ON`).
  String _modemVariantAt(World world, BlockPos pos, String kind) {
    final state = _states.decode(world.getBlockStateId(pos: pos));
    final value = state?.values['modem'];
    if (value == null) return kind == _fullModemType ? 'false' : 'none';
    return value;
  }

  // -- Wired modems and cables -------------------------------------------------------

  /// The modem of a cable or a full wired modem, or null when the block has no
  /// modem (`modem = none` on a cable, `modem = false` on a full modem).
  _Modem? _modem(String worldId, BlockPos pos, String kind, NbtCompound save, String variant) {
    final key = _key(worldId, pos);
    if (kind == _cableType && variant == 'none') return null;
    if (kind == _fullModemType && variant != 'true') return null;
    final modem = WiredModem(network: WiredNetwork());
    return _Modem(key, worldId, pos, save, kind, variant, modem);
  }

  /// The graph of the adjacent cable and wired-modem blocks: every modem of one
  /// component shares a network. Java connects and disconnects elements as
  /// neighbours change (`WiredElement#connect`); rebuilding the graph is
  /// simpler and always right.
  void _rebuildNetworks() {
    final parent = <String, String>{for (final key in _wired.keys) key: key};

    String find(String key) {
      var root = key;
      while (parent[root] != root) {
        root = parent[root]!;
      }
      var current = key;
      while (parent[current] != root) {
        final next = parent[current]!;
        parent[current] = root;
        current = next;
      }
      return root;
    }

    for (final key in _wired.keys) {
      final world = _worldOf(key);
      final pos = _pos(key);
      for (final entry in SimulatedAttach.neighbours.values) {
        final neighbour = _key(world, _offset(pos, entry.$1));
        if (!parent.containsKey(neighbour)) continue;
        final a = find(key);
        final b = find(neighbour);
        if (a != b) parent[a] = b;
      }
    }

    final networks = <String, WiredNetwork>{};
    for (final key in _modems.keys) {
      final root = find(key);
      networks[root] = networks[root] ?? WiredNetwork();
    }
    for (final entry in _modems.entries) {
      final modem = entry.value;
      final network = networks[find(entry.key)];
      if (network == null) continue;
      modem.peripheral.rejoin(network);
      modem.peripheral.element = _elementOf(modem);
    }
    for (final modem in _modems.values) {
      modem.peripheral.networkChanged();
    }
  }

  /// What a modem exposes to the network: the peripheral of the block it faces
  /// (`WiredModemLocalPeripheral`), named `<type>_<id>` with an id CC keeps in
  /// the block entity's save data.
  WiredElement _elementOf(_Modem modem) {
    final facing = _facingPos(modem);
    final peripheral = facing == null ? null : _peripheralAt(modem.world, facing);
    if (peripheral == null) return const WiredElement(null, null);
    return WiredElement('${peripheral.type}_${_peripheralId(modem, peripheral.type)}', peripheral);
  }

  /// The block a modem faces: a cable's `modem` property names the side; a full
  /// modem faces the first neighbouring computer or peripheral of ours
  /// (`WiredModemFullBlockEntity` has one modem per side; this port uses one for
  /// the block).
  BlockPos? _facingPos(_Modem modem) {
    final variant = modem.variant;
    if (variant != 'none' && variant != 'false' && variant != 'peripheral') {
      final offset = _directionNamed(variant);
      if (offset != null) return _offset(modem.pos, offset);
    }
    for (final entry in SimulatedAttach.neighbours.values) {
      final neighbour = _offset(modem.pos, entry.$1);
      if (_computers.containsKey(_key(modem.world, neighbour))) return neighbour;
      if (_peripheralAt(modem.world, neighbour) != null) return neighbour;
    }
    return null;
  }

  static (int, int, int)? _directionNamed(String name) => switch (name) {
    'up' => (0, 1, 0),
    'down' => (0, -1, 0),
    'north' => (0, 0, -1),
    'south' => (0, 0, 1),
    'east' => (1, 0, 0),
    'west' => (-1, 0, 0),
    _ => null,
  };

  int _peripheralId(_Modem modem, String type) {
    final data = modem.data;
    final existing = data.getInt('PeripheralId');
    if (data.getString('PeripheralType') == type && existing != null && existing >= 0) return existing;
    final id = _nextPeripheralIds[type] = (_nextPeripheralIds[type] ?? 0) + 1;
    data
      ..putString('PeripheralType', type)
      ..putInt('PeripheralId', id);
    return id;
  }

  /// The modem's block state changed (a cable gained or lost its modem): work
  /// out what it faces again.
  void _refreshModem(String worldId, BlockPos pos) {
    final key = _key(worldId, pos);
    final modem = _modems[key];
    if (modem == null) return;
    modem.peripheral.element = _elementOf(modem);
  }

  // -- Shared ------------------------------------------------------------------------

  /// Writes [data] as the save data of the block entity at [pos]. These blocks
  /// have no client data (`getUpdateTag` is not overridden for them except for
  /// a monitor).
  void _writeEntity(Server server, String worldId, BlockPos pos, String type, NbtCompound data) {
    final world = server.getWorldByName(name: worldId);
    if (world == null) return;
    try {
      world.setPluginBlockEntity(pos, type, data);
    } on PluginRegistryException catch (e) {
      logger.warn('Could not save the block entity of $type at $pos: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  /// Takes [count] of the item the player is holding.
  Future<void> _consume(PlayerUseBlockEventData event, int count) async {
    final held = event.player.getItemInHand(hand: event.hand);
    if (held == null) return;
    final have = await held.getCount();
    final left = have - count;
    if (left <= 0) {
      await event.player.setItemInHand(hand: event.hand, stack: null);
    } else {
      await held.setCount(count: left);
      await event.player.setItemInHand(hand: event.hand, stack: held);
    }
  }
}

/// A block this file tracks, with the entity's save data.
abstract class _PeripheralBlock {
  final String key;
  final String world;
  final BlockPos pos;
  final NbtCompound data;

  _PeripheralBlock(this.key, this.world, this.pos, this.data);

  Peripheral get peripheral;
}

final class _Drive extends _PeripheralBlock {
  @override
  final DiskDrivePeripheral peripheral;

  /// The path of the treasure disk in the drive, so its component can be
  /// written back when it is ejected.
  String? treasurePath;

  Media? _media;

  _Drive(super.key, super.world, super.pos, super.data, this.peripheral);

  Media? get media => _media;

  void setMedia(Media? media, {String? path}) {
    _media = media;
    treasurePath = media is TreasureDisk ? path : null;
    peripheral.mediaChanged();
  }
}

final class _Printer extends _PeripheralBlock {
  @override
  final PrinterPeripheral peripheral;
  int ink = 0;
  int paper = 0;
  int inkColour = 15;

  _Printer(super.key, super.world, super.pos, super.data, this.peripheral);
}

final class _Speaker extends _PeripheralBlock {
  @override
  final SpeakerPeripheral peripheral;
  final CcSpeakerSink sink;

  _Speaker(super.key, super.world, super.pos, super.data, this.peripheral, this.sink);
}

final class _Relay extends _PeripheralBlock {
  @override
  final RedstoneRelayPeripheral peripheral;

  /// The `facing` of the block, for the Lua-to-world side mapping.
  BlockDirection facing = BlockDirection.north;

  _Relay(super.key, super.world, super.pos, super.data, this.peripheral);

  /// The key of the relay block, for the host calls.
  String get blockKey => _relayType;
}

final class _Modem extends _PeripheralBlock {
  @override
  final WiredModem peripheral;
  final String typeKey;

  /// The `modem` property of the block the last time its state was read: the
  /// side a cable's modem faces, or `true`/`false` for a full modem.
  String variant;

  _Modem(super.key, super.world, super.pos, super.data, this.typeKey, this.variant, this.peripheral);
}

/// A computer or turtle whose block entity was read: what its neighbours see.
final class _ComputerBox {
  /// `computer` or `turtle`.
  final String type;

  /// The `ComputerId` of the entity, or null when it has none yet.
  final int? computerId;

  const _ComputerBox(this.type, this.computerId);
}

/// The drive this file hosts: its media, and ejecting it (which the tick does,
/// so it has a `Server`).
final class _HostDrive implements DiskDrive {
  final CcWorldPeripherals _peripherals;
  final String key;

  _HostDrive(this._peripherals, this.key);

  @override
  Media? get media => _peripherals._drives[key]?.media;

  @override
  void eject() {
    final drive = _peripherals._drives[key];
    if (drive != null) _peripherals._queueEject(drive);
  }
}

/// A computer as [ComputerPeripheral] sees it (`ComputerPeripheral` +
/// `ServerComputer`): the machine when its chunk is loaded, the record when it
/// is not (`owner.startOn` in Java).
final class _ServiceComputer implements ComputerController {
  final CcService _service;
  final int _id;

  _ServiceComputer(this._service, this._id);

  @override
  int get id => _id;

  @override
  String? get label => _service.computer(_id)?.label ?? _service.record(_id)?.label;

  @override
  bool get isOn => _service.computer(_id)?.isOn ?? _service.record(_id)?.on ?? false;

  @override
  void turnOn() {
    final computer = _service.computer(_id);
    if (computer != null) {
      computer.turnOn();
      return;
    }
    final record = _service.record(_id);
    if (record != null) {
      record.on = true;
      _service.save();
    }
  }

  @override
  void shutdown() {
    final computer = _service.computer(_id);
    if (computer != null) {
      computer.shutdown();
      return;
    }
    final record = _service.record(_id);
    if (record != null) {
      record.on = false;
      _service.save();
    }
  }

  @override
  void reboot() {
    final computer = _service.computer(_id);
    if (computer != null) {
      computer.reboot();
      return;
    }
    turnOn();
  }
}