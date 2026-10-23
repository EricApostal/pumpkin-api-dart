// Monitors in the world: the block entities of `computercraft:monitor_normal`
// and `computercraft:monitor_advanced`, the wall the blocks form, the `monitor`
// peripheral of that wall (whose terminal lives in one `MonitorPeripheral`), the
// right click that reaches a character cell, and the `monitor_client` screen
// updates.
//
// It mirrors, of CC: Tweaked (branch mc-26.3, `projects/common/src/main/java/
// dan200/computercraft/shared/peripheral/monitor/`):
//
//   MonitorBlockEntity.java  the save and client data (XIndex, YIndex, Width,
//                            Height), `resize`, `contractNeighbours`,
//                            `isCompatible`, `getDirection`/`getOrientation`/
//                            `getFront`/`getRight`/`getDown`, `toWorldPos`,
//                            `monitorTouched`, `updateBlockState`, `peripheral`
//   Expander.java            `expand` and `expandIn`
//   MonitorBlock.java        `useWithoutItem` and `setPlacedBy`
//   MonitorEdgeState.java    `fromConnections` and the 16 state names
//   XYPair.java              `of`
//   MonitorWatcher.java      `enqueue`, `onWatch`, `onTick` and the bandwidth cap
//   ServerMonitor.java       the terminal size (already in `MonitorPeripheral`)
//
// Where the port differs from Java it is noted inline; the two big ones are:
//
// * Java recomputes the wall from the world whenever a block entity ticks and
//   keeps the peripheral as a block capability the computer looks up on demand.
//   The port keeps its own map of the monitor block entities (like
//   `world_computers.dart` does for computers) and re-runs `Expander` from its
//   triggers, and attaches the wall's peripheral to the computers it touches
//   with `CcService.attachExternal`.
// * `monitor_client` is sent to the players tracking the chunk in Java
//   (`MonitorWatcher.onTick` → `ServerNetworking.sendToAllTracking`). The host
//   has no "players tracking this chunk" call, so the port approximates: every
//   player within 64 blocks of the wall's origin in the same world.
//
// Nothing here has run against a host or a client: see docs/host-requirements.md.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../compat/simulated_attach.dart' show SimulatedAttach;
import '../machine/peripherals.dart' show MonitorPeripheral;
import '../machine/side.dart';
import '../protocol/messages.dart';
import '../protocol/terminal_state.dart';
import 'block_states.dart';
import 'network.dart';
import 'service.dart';

/// The monitor blocks and whether they are advanced. The block key is also the
/// block entity type key (ModRegistry registers `monitor_normal` and
/// `monitor_advanced` once each for the block and the entity).
const Map<String, bool> _monitorBlocks = {
  'computercraft:monitor_normal': false,
  'computercraft:monitor_advanced': true,
};

/// The computer blocks, whose block entities the port watches so that a monitor
/// already standing next to a computer attaches when the computer comes back
/// (`AbstractComputerBlockEntity` recomputes its peripherals on load).
const Set<String> _computerBlocks = {
  'computercraft:computer_normal',
  'computercraft:computer_advanced',
  'computercraft:computer_command',
};

/// `Config.monitorWidth`/`Config.monitorHeight` (Config.java:39-40): how many
/// blocks a wall may have on each axis.
const int _maxWidth = 8;
const int _maxHeight = 6;

/// `Config.monitorBandwidth` (Config.java:23): the bytes of terminal state that
/// may be sent in one tick (`MonitorWatcher.onTick` decrements this per state).
const int _bandwidth = 1000000;

/// `MonitorBlockEntity.RENDER_BORDER`/`RENDER_MARGIN`.
const double _border = 2.0 / 16.0;
const double _margin = 0.5 / 16.0;

/// How far from a wall a player is sent its screen. Java sends to the players
/// tracking the chunk; see the file comment.
const double _viewDistance = 64.0;

/// How often the walls are rechecked for computers that appeared later.
const int _rescanInterval = 10;

/// How long a reshape that found no origin block is retried (chunk load order),
/// in ticks.
const int _reshapeRetries = 100;

/// The name of the `state` property for each `MonitorEdgeState` flag mask
/// (`MonitorEdgeState.Flags`: UP 1, DOWN 2, LEFT 4, RIGHT 8 → the enum's names).
const Map<int, String> _edgeNames = {
  0: 'none',
  1: 'u',
  2: 'd',
  3: 'ud',
  4: 'l',
  5: 'lu',
  6: 'ld',
  7: 'lud',
  8: 'r',
  9: 'ru',
  10: 'rd',
  11: 'rud',
  12: 'lr',
  13: 'lru',
  14: 'lrd',
  15: 'lrud',
};

/// A block direction (`net.minecraft.core.Direction`) as a unit vector.
final class _Dir {
  final int x, y, z;

  const _Dir(this.x, this.y, this.z);

  static const north = _Dir(0, 0, -1);
  static const south = _Dir(0, 0, 1);
  static const west = _Dir(-1, 0, 0);
  static const east = _Dir(1, 0, 0);
  static const up = _Dir(0, 1, 0);
  static const down = _Dir(0, -1, 0);

  /// The six directions, in `Direction.values()` order.
  static const List<_Dir> all = [down, up, north, south, west, east];

  _Dir get opposite => _Dir(-x, -y, -z);

  /// `Direction.getCounterClockWise()` around the Y axis (north → west → south
  /// → east); a direction that is not horizontal is itself.
  _Dir get counterClockWise => switch ((x, z)) {
    (0, -1) => west,
    (0, 1) => east,
    (-1, 0) => south,
    (1, 0) => north,
    _ => this,
  };

  static _Dir? parse(String name) => switch (name) {
    'down' => down,
    'up' => up,
    'north' => north,
    'south' => south,
    'west' => west,
    'east' => east,
    _ => null,
  };

  static _Dir? of(BlockDirection direction) => switch (direction) {
    BlockDirection.down => down,
    BlockDirection.up => up,
    BlockDirection.north => north,
    BlockDirection.south => south,
    BlockDirection.west => west,
    BlockDirection.east => east,
  };

  @override
  bool operator ==(Object other) => other is _Dir && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// One monitor block with its entity, as the plugin tracks it.
final class _Monitor {
  final String world;
  final int x, y, z;
  final String blockKey;
  final bool advanced;

  /// The `save-data` of the entity: kept so that keys the plugin does not know
  /// survive a rewrite.
  final NbtCompound data;

  _Dir facing = _Dir.north;
  _Dir orientation = _Dir.north;

  int xIndex = 0;
  int yIndex = 0;
  int width = 1;
  int height = 1;

  /// Whether the block entity is loaded (`BlockEntity.isRemoved()` is false and
  /// the chunk is in the world). An unloaded block stays part of its wall, like
  /// Java's `MonitorState.UNLOADED` does.
  bool present = true;

  _Wall? wall;

  _Monitor(this.world, this.x, this.y, this.z, this.blockKey, this.data, {required this.advanced});

  String get key => '$world|$x|$y|$z';

  /// `MonitorBlockEntity.getFront()`: the face the screen is on.
  _Dir get front => orientation == _Dir.north ? facing : orientation;

  /// `MonitorBlockEntity.getRight()`.
  _Dir get right => facing.counterClockWise;

  /// `MonitorBlockEntity.getDown()`.
  _Dir get down => switch (orientation) {
    _Dir.north || _Dir.down => orientation == _Dir.north ? _Dir.up : facing,
    _ => facing.opposite,
  };

  /// `MonitorBlockEntity.toWorldPos(x, y)`: monitor coordinates to a world
  /// position.
  (int, int, int) toWorldPos(int x, int y) {
    final r = right;
    final d = down;
    return (
      x + r.x * (-xIndex + x) + d.x * (-yIndex + y),
      y + r.y * (-xIndex + x) + d.y * (-yIndex + y),
      z + r.z * (-xIndex + x) + d.z * (-yIndex + y),
    );
  }

  /// `MonitorBlockEntity.isCompatible`: same kind, same orientation, same
  /// facing. A block the plugin no longer tracks cannot be reached here, which
  /// is Java's `!other.isRemoved() && !other.isRemoving`.
  bool isCompatible(_Monitor other) =>
      advanced == other.advanced && orientation == other.orientation && facing == other.facing;
}

/// A wall of monitors: the blocks it spans and the one peripheral (with the one
/// terminal) every block of the wall shares.
final class _Wall {
  int width;
  int height;
  final bool advanced;

  /// The monitor blocks of the wall, in `Expander` order (left to right, top to
  /// bottom of the rectangle).
  List<_Monitor> blocks = [];

  /// The peripheral of the whole wall (`MonitorBlockEntity.peripheral()`); every
  /// block of the wall and every computer next to it sees this instance.
  late final MonitorPeripheral peripheral;

  /// Whether the terminal changed since the last `monitor_client` send
  /// (`MonitorWatcher.enqueue`).
  bool dirty = false;

  /// No screen has ever been sent for this wall.
  bool everSent = false;

  /// The last `TerminalState` sent, and whether the last send said "no
  /// terminal" (Java sends `Optional.empty()` while no computer has wrapped the
  /// monitor).
  TerminalState? sent;
  bool sentEmpty = false;

  /// The players the last state was sent to (`MonitorWatcher.onWatch` sends to a
  /// player that starts watching).
  final Set<String> sentTo = {};

  /// The sides of computers that hold this peripheral now.
  final Map<String, (int, ComputerSide)> attached = {};

  bool removed = false;

  _Wall(this.width, this.height, {required this.advanced}) {
    peripheral = MonitorPeripheral(width, height, advanced: advanced, onChanged: () {
      if (!removed) dirty = true;
    });
  }
}

final class CcWorldMonitors {
  final CcService _service;
  // ignore: unused_field
  final CcNetwork _network;
  final CcBlockStates _states;
  final TypedChannel<MonitorMessage> _monitorChannel;

  final Map<String, _Monitor> _blocks = {};
  final Map<String, _Wall> _walls = {};

  /// Reshapes to retry because the origin block was not tracked yet (chunk load
  /// order): key → (world, position, the last tick to try).
  final Map<String, (String, (int, int, int), int)> _pending = {};

  int _tick = 0;

  CcWorldMonitors(this._service, this._network, this._states, this._monitorChannel);

  /// Number of monitor blocks with an entity the plugin tracks.
  int get blockCount => _blocks.length;

  static String _key(String world, int x, int y, int z) => '$world|$x|$y|$z';

  static BlockPos _pos(int x, int y, int z) => BlockPos(x: x, y: y, z: z);

  static (int, int, int) _coords(BlockPos pos) => (pos.x, pos.y, pos.z);

  /// Listens for the events that drive monitor blocks.
  void install(Context context) {
    context.intercept(Events.playerUseBlock, _onUseBlock);
    context.listen(Events.blockPlace, _onBlockPlace);
    context.listen(Events.blockEntityLoad, _onEntityLoad);
    context.listen(Events.blockEntityUnload, _onEntityUnload);
    _installNeighbourRefresh(context);
  }

  /// Asks the host to tell the monitor blocks when a neighbour changes: a
  /// computer may have appeared or vanished, or the wall's shape changed
  /// (`MonitorBlockEntity.updateNeighborsDeferred`/`expand`).
  void _installNeighbourRefresh(Context context) {
    final behavior = BlockBehavior(
      onNeighborUpdate: (server, event) => _onNeighbourUpdate(server, event),
    );
    for (final key in _monitorBlocks.keys) {
      try {
        context.registerBlockBehavior(key, behavior);
      } on HostException catch (e) {
        logger.warn('Could not listen for the neighbours of $key: $e');
      }
    }
  }

  Future<void> _onNeighbourUpdate(Server server, CustomBlockNeighborUpdateEventData event) =>
      _reshapeAt(server, event.targetWorld, _coords(event.pos));

  // -- Tracking the block entities -------------------------------------------------

  _Monitor? _blockAt(String world, (int, int, int) pos) => _blocks[_key(world, pos.$1, pos.$2, pos.$3)];

  /// Tracks a monitor block entity, reading the wall coordinates from [data].
  _Monitor _attach(String world, (int, int, int) pos, String blockKey, NbtCompound data) {
    final block = _Monitor(
      world,
      pos.$1,
      pos.$2,
      pos.$3,
      blockKey,
      data,
      advanced: _monitorBlocks[blockKey] ?? false,
    );
    block.xIndex = _intOr(data, 'XIndex', 0);
    block.yIndex = _intOr(data, 'YIndex', 0);
    block.width = _intOr(data, 'Width', 1);
    block.height = _intOr(data, 'Height', 1);
    _blocks[block.key] = block;
    return block;
  }

  static int _intOr(NbtCompound data, String key, int fallback) {
    try {
      return data.getInt(key) ?? fallback;
    } on FormatException {
      return fallback;
    }
  }

  /// Reads `facing` and `orientation` from the block state; false when the
  /// block there is not the monitor [block] stands for.
  bool _readDirections(World world, _Monitor block) {
    final state = _states.decode(world.getBlockStateId(pos: _pos(block.x, block.y, block.z)));
    if (state == null || state.key != block.blockKey) return false;
    block.facing = _Dir.parse(state.values['facing'] ?? '') ?? _Dir.north;
    block.orientation = _Dir.parse(state.values['orientation'] ?? '') ?? _Dir.north;
    return true;
  }

  // -- Placing ---------------------------------------------------------------------

  /// A monitor block was placed. The event fires before the block is in the
  /// world, so the entity is created a tick later, after checking the block.
  void _onBlockPlace(Server server, BlockPlaceEventData event) {
    if (!_monitorBlocks.containsKey(event.blockPlaced) || event.cancelled) return;
    final world = event.player.getWorld();
    final String worldId;
    try {
      worldId = world.getId();
    } finally {
      world.dispose();
    }
    final pos = _coords(event.blockPos);
    final blockKey = event.blockPlaced;
    server.runLater(1, (server) => _createEntity(server, worldId, pos, blockKey));
  }

  void _createEntity(Server server, String worldId, (int, int, int) pos, String blockKey) {
    final world = server.getWorldByName(name: worldId);
    if (world == null) return;
    try {
      if (_blocks.containsKey(_key(worldId, pos.$1, pos.$2, pos.$3))) return;
      // The placement may have been cancelled or the block replaced since.
      if (!_states.isBlock(world.getBlockStateId(pos: _pos(pos.$1, pos.$2, pos.$3)), blockKey)) return;
      final existing = world.pluginBlockEntityAt(_pos(pos.$1, pos.$2, pos.$3));
      if (existing != null) {
        if (_monitorBlocks.containsKey(existing.typeKey)) _attach(worldId, pos, existing.typeKey, existing.save);
        return;
      }
      final data = NbtCompound()
        ..putInt('XIndex', 0)
        ..putInt('YIndex', 0)
        ..putInt('Width', 1)
        ..putInt('Height', 1);
      // `MonitorBlockEntity.getUpdateTag` carries the four coordinates too, so a
      // fresh block starts out as a 1x1 origin on the client as well.
      world.setPluginBlockEntity(_pos(pos.$1, pos.$2, pos.$3), blockKey, data, client: data);
      _attach(worldId, pos, blockKey, data);
      unawaited(_reshape(server, _blockAt(worldId, pos)!));
    } on PluginRegistryException catch (e) {
      logger.warn('Could not create the monitor block entity at $worldId $pos: ${e.message}');
    } finally {
      world.dispose();
    }
  }

  // -- Loading and unloading chunks ------------------------------------------------------

  /// `BlockEntity.loadAdditional`: the chunk brought a monitor; track it and
  /// rebuild its wall. A computer block entity that comes back is handled too:
  /// a monitor next to it may not have found it before.
  void _onEntityLoad(Server server, BlockEntityLoadEventData event) {
    final worldId = event.targetWorld.getId();
    final pos = _coords(event.pos);
    if (_monitorBlocks.containsKey(event.typeKey)) {
      final NbtCompound data;
      try {
        data = event.save;
      } on FormatException catch (e) {
        logger.warn('The block entity data of ${event.typeKey} at $worldId $pos is not a compound: $e');
        return;
      }
      final block = _blocks[_key(worldId, pos.$1, pos.$2, pos.$3)] ?? _attach(worldId, pos, event.typeKey, data);
      block.present = true;
      unawaited(_reshape(server, block));
      return;
    }
    if (_computerBlocks.contains(event.typeKey)) {
      // A monitor next to the computer may be waiting for its id.
      for (final dir in _Dir.all) {
        final neighbour = (pos.$1 + dir.x, pos.$2 + dir.y, pos.$3 + dir.z);
        final block = _blockAt(worldId, neighbour);
        if (block != null) unawaited(_reshape(server, block));
      }
    }
  }

  /// The chunk unloads (the wall keeps standing) or the block was broken
  /// (`removed`). In both cases the block stops taking part until it comes back;
  /// a broken block is dropped for good and the neighbours re-form
  /// (`MonitorBlockEntity.contractNeighbours`).
  void _onEntityUnload(Server server, BlockEntityUnloadEventData event) {
    final worldId = event.targetWorld.getId();
    final pos = _coords(event.pos);
    if (_computerBlocks.contains(event.typeKey) && event.removed) {
      _detachComputer(event.save);
      return;
    }
    if (!_monitorBlocks.containsKey(event.typeKey)) return;
    if (!event.removed) {
      _blockAt(worldId, pos)?.present = false;
      return;
    }
    final key = _key(worldId, pos.$1, pos.$2, pos.$3);
    final block = _blocks.remove(key);
    block?.wall = null;
    for (final dir in _Dir.all) {
      final neighbour = (pos.$1 + dir.x, pos.$2 + dir.y, pos.$3 + dir.z);
      final other = _blockAt(worldId, neighbour);
      if (other != null) unawaited(_reshape(server, other));
    }
    _pruneWalls();
    unawaited(_sync(server));
  }

  /// A computer block entity went away: takes the monitors off its sides (the
  /// peripheral cannot stay on a computer that is no longer there).
  void _detachComputer(NbtCompound data) {
    final id = _intOr(data, 'ComputerId', -1);
    if (id < 0) return;
    for (final wall in _walls.values) {
      for (final entry in wall.attached.entries.toList()) {
        final (attachedId, side) = entry.value;
        if (attachedId != id) continue;
        if (identical(_service.peripheral(attachedId, side), wall.peripheral)) {
          _service.detachExternal(attachedId, side);
        }
        wall.attached.remove(entry.key);
      }
    }
  }

  // -- Expansion (Expander.java) -------------------------------------------------------

  /// Rebuilds the wall [block] is part of, starting at the wall's origin.
  Future<void> _reshape(Server server, _Monitor block) async {
    final originPos = block.toWorldPos(0, 0);
    final origin = _blockAt(block.world, originPos);
    if (origin == null || origin.xIndex != 0 || origin.yIndex != 0) {
      // The origin is not tracked yet: the chunk load order, retried for a few
      // ticks (Java's `getOrigin()` looks the chunk up, which loads it).
      _pending[block.key] = (block.world, (block.x, block.y, block.z), _tick + _reshapeRetries);
      return;
    }
    _pending.remove(block.key);
    await _Expander(this, origin).expand(server);
  }

  Future<void> _reshapeAt(Server server, World world, (int, int, int) pos) async {
    final block = _blockAt(world.getId(), pos);
    if (block == null) return;
    if (!_readDirections(world, block)) return;
    await _reshape(server, block);
  }

  /// The monitor blocks of the rectangle [width] by [height] whose origin is
  /// [origin], or `null` when one of them is not tracked (`resize` skips the
  /// ones it cannot find; the port refuses rather than half-apply).
  List<_Monitor>? _region(_Monitor origin, int width, int height) {
    final blocks = <_Monitor>[];
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        final block = _blockAt(origin.world, origin.toWorldPos(x, y));
        if (block == null) return null;
        blocks.add(block);
      }
    }
    return blocks;
  }

  /// `MonitorBlockEntity.resize`: gives every block of the rectangle its
  /// coordinates and shares one wall (and its peripheral) with all of them.
  Future<void> _applyWall(Server server, _Monitor origin, int width, int height) async {
    if (width > _maxWidth || height > _maxHeight) {
      logger.warn('Refusing a $width x $height monitor at ${origin.key} (limit $_maxWidth x $_maxHeight).');
      return;
    }
    final region = _region(origin, width, height);
    if (region == null) return;

    // The wall is the one the origin already has (the terminal survives a
    // resize), else the one another block of the rectangle brings.
    var wall = origin.wall;
    for (final block in region) {
      wall ??= block.wall;
    }
    final fresh = wall == null;
    wall ??= _Wall(width, height, advanced: origin.advanced);

    // Blocks that leave the rectangle lose the wall (a wall that shrank).
    for (final block in _blocks.values) {
      if (identical(block.wall, wall) && !region.contains(block)) block.wall = null;
    }

    wall
      ..blocks = region
      ..removed = false;
    for (var i = 0; i < region.length; i++) {
      region[i].wall = wall;
    }

    final world = server.getWorldByName(name: origin.world);
    if (world == null) return;
    try {
      final resized = fresh || wall.width != width || wall.height != height;
      wall
        ..width = width
        ..height = height;
      for (var i = 0; i < region.length; i++) {
        final block = region[i];
        final x = i % width;
        final y = i ~/ width;
        final moved = block.xIndex != x || block.yIndex != y || block.width != width || block.height != height;
        block
          ..xIndex = x
          ..yIndex = y
          ..width = width
          ..height = height;
        if (!block.present) continue;
        if (moved || fresh) _writeBlock(world, block);
        await _writeState(world, block);
      }
      // `resize`: the terminal of the wall follows the new block size.
      if (resized) {
        wall.peripheral.resizeBlocks(width, height);
        wall.dirty = true;
      }
      _attachWall(world, wall);
      _rekey(wall, origin);
    } finally {
      world.dispose();
    }
  }

  /// Keeps `_walls` keyed by the wall's origin block (the origin can move when
  /// the expander merges a wall on its left or above).
  void _rekey(_Wall wall, _Monitor origin) {
    _walls.removeWhere((_, other) => identical(other, wall));
    _walls[origin.key] = wall;
  }

  /// Writes `XIndex`, `YIndex`, `Width`, `Height` to the save data and to the
  /// client data (`MonitorBlockEntity.saveAdditional` and `getUpdateTag`), and
  /// resends the client data.
  void _writeBlock(World world, _Monitor block) {
    try {
      final pos = _pos(block.x, block.y, block.z);
      final data = block.data
        ..putInt('XIndex', block.xIndex)
        ..putInt('YIndex', block.yIndex)
        ..putInt('Width', block.width)
        ..putInt('Height', block.height);
      final client = NbtCompound()
        ..putInt('XIndex', block.xIndex)
        ..putInt('YIndex', block.yIndex)
        ..putInt('Width', block.width)
        ..putInt('Height', block.height);
      world.setPluginBlockEntity(pos, block.blockKey, data, client: client);
      world.syncPluginBlockEntity(pos);
    } on PluginRegistryException catch (e) {
      logger.warn('Could not write the monitor block entity at ${block.key}: ${e.message}');
    }
  }

  /// `MonitorBlockEntity.updateBlockState`: the `state` property follows where
  /// the block sits in the wall.
  Future<void> _writeState(World world, _Monitor block) async {
    final pos = _pos(block.x, block.y, block.z);
    final current = world.getBlockStateId(pos: pos);
    if (!_states.isBlock(current, block.blockKey)) return;
    final name = _edgeState(block.xIndex, block.yIndex, block.width, block.height);
    if (_states.decode(current)?.values['state'] == name) return;
    final next = _states.withValues(current, {'state': name});
    if (next == null || next == current) return;
    await world.setBlockState(pos: pos, state: next, updateFlags: const {BlockFlagsFlag.notifyListeners});
  }

  // -- The peripheral on the computers next to the wall ----------------------------------

  /// Attaches [wall]'s peripheral to the side of every loaded computer that
  /// touches a block of the wall, and takes it off the sides that no longer do
  /// (Java registers the monitor for all directions:
  /// `registerForBlockEntity(MONITOR_*, (b, d) -> b.peripheral())`).
  void _attachWall(World world, _Wall wall) {
    final needed = <String, (int, ComputerSide)>{};
    for (final block in wall.blocks) {
      if (!block.present) continue;
      for (final dir in _Dir.all) {
        final neighbour = (block.x + dir.x, block.y + dir.y, block.z + dir.z);
        final entity = _entityAt(world, neighbour);
        if (entity == null || !_computerBlocks.contains(entity.typeKey)) continue;
        final id = _intOr(entity.save, 'ComputerId', -1);
        if (id < 0 || !_service.hasComputer(id)) continue;
        final side = SimulatedAttach.sideTowards((block.x, block.y, block.z), neighbour);
        if (side == null) continue;
        needed['$id/${side.luaName}'] = (id, side);
      }
    }
    for (final entry in needed.entries) {
      if (wall.attached.containsKey(entry.key)) continue;
      _service.attachExternal(entry.value.$1, entry.value.$2, wall.peripheral);
    }
    for (final entry in wall.attached.entries.toList()) {
      if (needed.containsKey(entry.key)) continue;
      final (id, side) = entry.value;
      if (identical(_service.peripheral(id, side), wall.peripheral)) _service.detachExternal(id, side);
      wall.attached.remove(entry.key);
    }
    wall.attached
      ..clear()
      ..addAll(needed);
  }

  PluginBlockEntityState? _entityAt(World world, (int, int, int) pos) {
    try {
      return world.pluginBlockEntityAt(_pos(pos.$1, pos.$2, pos.$3));
    } on Object catch (e) {
      logger.warn('Could not read the block entity at $pos: $e');
      return null;
    }
  }

  /// Takes the peripheral off the computers of [wall] and forgets it.
  void _finalizeWall(_Wall wall) {
    wall.removed = true;
    for (final entry in wall.attached.values) {
      final (id, side) = entry;
      if (identical(_service.peripheral(id, side), wall.peripheral)) _service.detachExternal(id, side);
    }
    wall.attached.clear();
    wall.blocks = [];
    _walls.removeWhere((_, other) => identical(other, wall));
  }

  /// Drops the walls no block refers to any more.
  void _pruneWalls() {
    for (final wall in _walls.values.toList()) {
      final live = wall.blocks.where((block) => identical(block.wall, wall)).toList();
      wall.blocks = live;
      if (live.isEmpty) _finalizeWall(wall);
    }
  }

  // -- The right click that touches a cell ------------------------------------------------

  /// `MonitorBlock.useWithoutItem`: a click without sneaking on the monitor's
  /// front face touches a character cell.
  Future<PlayerUseBlockEventData> _onUseBlock(Server server, PlayerUseBlockEventData event) async {
    if (event.sneaking || !_monitorBlocks.containsKey(event.block)) return event;
    final world = event.player.getWorld();
    try {
      final worldId = world.getId();
      final pos = _coords(event.blockPos);
      final block = _blockAt(worldId, pos);
      if (block == null) return event;
      // The block state is the source of truth for which face is the screen.
      if (!_readDirections(world, block)) return event;
      final face = _Dir.of(event.face);
      if (face == null || block.front != face) return event;
      final wall = block.wall;
      if (wall == null) return event;
      final (xPos, yPos, zPos) = event.cursor;
      _touch(wall, block, xPos, yPos, zPos);
    } finally {
      world.dispose();
    }
    return event.cancel();
  }

  /// `MonitorBlockEntity.monitorTouched`: the hit position becomes a cell of the
  /// wall's terminal.
  void _touch(_Wall wall, _Monitor block, double xPos, double yPos, double zPos) {
    final (pairX, pairY) = _xyPair(xPos, yPos, zPos, block.facing, block.orientation);
    final px = pairX + block.xIndex;
    final py = pairY + block.height - block.yIndex - 1;
    if (px > block.width - _border || py > block.height - _border || px < _border || py < _border) return;

    // Java reads this from the wall's ServerMonitor, which is null while no
    // computer has wrapped the monitor.
    if (!wall.peripheral.hasComputers) return;
    final terminal = wall.peripheral.terminal;
    final xCharWidth = (block.width - (_border + _margin) * 2.0) / terminal.width;
    final yCharHeight = (block.height - (_border + _margin) * 2.0) / terminal.height;
    final xCharPos = math.min(terminal.width, math.max((px - _border - _margin) / xCharWidth + 1.0, 1.0)).toInt();
    final yCharPos = math.min(terminal.height, math.max((py - _border - _margin) / yCharHeight + 1.0, 1.0)).toInt();
    wall.peripheral.touch(xCharPos, yCharPos);
  }

  // -- The server tick -----------------------------------------------------------------------

  /// Rechecks pending reshapes and, every [_rescanInterval] ticks, the computers
  /// next to every wall, then sends the screens that changed.
  Future<void> tick(Server server) async {
    _tick++;
    await _flushPending(server);
    if (_tick % _rescanInterval == 0) await _rescan(server);
    await _sync(server);
  }

  Future<void> _flushPending(Server server) async {
    if (_pending.isEmpty) return;
    final now = _tick;
    final due = [
      for (final entry in _pending.entries)
        if (entry.value.$3 > now) entry,
    ];
    _pending.removeWhere((_, value) => value.$3 <= now);
    var budget = 32;
    for (final entry in due) {
      if (budget-- <= 0) break;
      final (worldId, pos, _) = entry.value;
      final block = _blockAt(worldId, pos);
      if (block != null) await _reshape(server, block);
    }
  }

  /// Rebuilds the walls that have none and re-attaches every wall. Java's
  /// capability lookup is on demand, so a computer that gets its machine later
  /// still finds the monitor; the port has to look again.
  Future<void> _rescan(Server server) async {
    for (final block in _blocks.values.toList()) {
      if (block.wall == null) await _reshape(server, block);
    }
    final byWorld = <String, World>{};
    try {
      for (final wall in _walls.values.toList()) {
        final origin = wall.blocks.isEmpty ? null : wall.blocks.first;
        if (origin == null) continue;
        final world = byWorld[origin.world] ?? server.getWorldByName(name: origin.world);
        if (world == null) continue;
        byWorld[origin.world] = world;
        _attachWall(world, wall);
      }
    } finally {
      for (final world in byWorld.values) {
        world.dispose();
      }
    }
  }

  /// `MonitorWatcher.onTick`: sends each changed wall to the players around it,
  /// within the bandwidth the config allows.
  Future<void> _sync(Server server) async {
    if (_walls.isEmpty) return;
    var budget = _bandwidth;
    final players = server.getAllPlayers();
    final wallByWorld = <String, World>{};
    try {
      for (final wall in _walls.values.toList()) {
        final origin = wall.blocks.isEmpty ? null : wall.blocks.first;
        if (origin == null) continue;
        if (budget <= 0) break;
        // The terminal snapshot is the expensive part (`TerminalState.of`
        // copies every cell), so it is only built when something happened: the
        // terminal changed (`MonitorWatcher.enqueue`), or the set of players
        // changed (a player starts watching, `MonitorWatcher.onWatch`).
        final mayNeed = wall.dirty || !wall.everSent || wall.sentTo.length != players.length;
        if (!mayNeed) continue;
        // A wall with no computer wrapped sends `Optional.empty()`, which is
        // what tells the client to drop the terminal it draws.
        final state = wall.peripheral.hasComputers ? TerminalState.of(wall.peripheral.terminal) : null;
        final changed = !wall.everSent || (state == null ? !wall.sentEmpty : (wall.sentEmpty || !wall.sent!.sameAs(state)));

        var sent = false;
        for (final player in players) {
          final uuid = player.getId().asString;
          // An unchanged terminal still goes to a player that has not been sent
          // it yet.
          if (!changed && wall.sentTo.contains(uuid)) continue;
          final playerWorld = player.getWorld();
          final String playerWorldId;
          final (double px, double py, double pz) = player.getPosition();
          try {
            playerWorldId = playerWorld.getId();
          } finally {
            playerWorld.dispose();
          }
          if (playerWorldId != origin.world) continue;
          final dx = px - origin.x;
          final dy = py - origin.y;
          final dz = pz - origin.z;
          if (dx * dx + dy * dy + dz * dz > _viewDistance * _viewDistance) continue;
          try {
            await _monitorChannel.send(player, MonitorMessage((origin.x, origin.y, origin.z), state));
          } on UnsupportedError {
            // A Bedrock player has no custom payloads.
            continue;
          } on Object catch (e) {
            logger.warn('Could not send the monitor at ${origin.key}: $e');
            continue;
          }
          wall.sentTo.add(uuid);
          sent = true;
        }
        if (sent) {
          wall
            ..everSent = true
            ..dirty = false
            ..sent = state
            ..sentEmpty = state == null;
          budget -= state?.size ?? 0;
        }
      }
    } finally {
      for (final world in wallByWorld.values) {
        world.dispose();
      }
      for (final player in players) {
        player.dispose();
      }
    }
  }
}

/// `MonitorEdgeState.fromConnections(up, down, left, right)`.
String _edgeState(int xIndex, int yIndex, int width, int height) {
  var flags = 0;
  if (yIndex < height - 1) flags |= 1; // UP
  if (yIndex > 0) flags |= 2; // DOWN
  if (xIndex > 0) flags |= 4; // LEFT
  if (xIndex < width - 1) flags |= 8; // RIGHT
  return _edgeNames[flags]!;
}

/// `XYPair.of(xPos, yPos, zPos, facing, orientation)`: the hit position relative
/// to the block, in the monitor's own axes.
(double, double) _xyPair(double xPos, double yPos, double zPos, _Dir facing, _Dir orientation) {
  if (orientation == _Dir.north) {
    return switch (facing) {
      _Dir.north => (1 - xPos, 1 - yPos),
      _Dir.south => (xPos, 1 - yPos),
      _Dir.west => (zPos, 1 - yPos),
      _Dir.east => (1 - zPos, 1 - yPos),
      _ => (xPos, zPos),
    };
  }
  if (orientation == _Dir.down) {
    return switch (facing) {
      _Dir.north => (1 - xPos, zPos),
      _Dir.south => (xPos, 1 - zPos),
      _Dir.west => (zPos, xPos),
      _Dir.east => (1 - zPos, 1 - xPos),
      _ => (xPos, zPos),
    };
  }
  if (orientation == _Dir.up) {
    return switch (facing) {
      _Dir.north => (1 - xPos, 1 - zPos),
      _Dir.south => (xPos, zPos),
      _Dir.west => (zPos, 1 - xPos),
      _Dir.east => (1 - zPos, xPos),
      _ => (xPos, zPos),
    };
  }
  return (xPos, zPos);
}

/// `Expander`: grows a monitor wall in each direction until a fixed point.
final class _Expander {
  final CcWorldMonitors _owner;
  _Monitor origin;
  int width;
  int height;
  late _Dir down = origin.down;
  late _Dir right = origin.right;

  _Expander(this._owner, this.origin)
    : width = origin.width,
      height = origin.height;

  Future<void> expand(Server server) async {
    var changedCount = 0;
    // The same guard Java uses against an infinite loop (a monitor with a width
    // or height of 0 in the world).
    final changeLimit = _maxWidth * _maxHeight + 1;
    while (_expandIn(true, false) || _expandIn(true, true) || _expandIn(false, false) || _expandIn(false, true)) {
      changedCount++;
      if (changedCount > changeLimit) {
        logger.error('Monitor has grown too much. This suggests there is an empty monitor in the world.');
        break;
      }
    }
    await _owner._applyWall(server, origin, width, height);
  }

  bool _expandIn(bool useXAxis, bool isPositive) {
    final pos = (origin.x, origin.y, origin.z);
    final offset = isPositive ? (useXAxis ? width : height) : -1;
    final (ox, oy, oz) = pos;
    final otherPos = useXAxis
        ? (ox + right.x * offset, oy + right.y * offset, oz + right.z * offset)
        : (ox + down.x * offset, oy + down.y * offset, oz + down.z * offset);
    final other = _owner._blockAt(origin.world, otherPos);
    if (other == null || !origin.isCompatible(other)) return false;

    if (useXAxis) {
      if (other.yIndex != 0 || other.height != height) return false;
      width += other.width;
      if (width > _maxWidth) return false;
    } else {
      if (other.xIndex != 0 || other.width != width) return false;
      height += other.height;
      if (height > _maxHeight) return false;
    }

    if (!isPositive) {
      final otherOrigin = _owner._blockAt(origin.world, other.toWorldPos(0, 0));
      if (otherOrigin == null || !origin.isCompatible(otherOrigin)) return false;
      origin = otherOrigin;
      down = origin.down;
      right = origin.right;
    }

    return true;
  }
}