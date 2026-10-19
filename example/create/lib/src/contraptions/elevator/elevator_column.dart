// `ElevatorColumn` (pure data + world access): the contacts of one elevator column, their floor
// names and the target floor. Java keeps one per `(x, z, side)` per level in a `WorldAttached`;
// this keeps one per world id.
//
// Java: `content/contraptions/elevator/ElevatorColumn`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/block_state.dart';
import '../../api/blocks.dart' show HostBlockGetter, manifestBlocksByKey;
import '../../common/common.dart';
import '../../common/host_bridge.dart';
import '../../core/block_entity.dart';
import '../blocks/actuator_runtime.dart';
import '../core/nbt_map.dart';
import 'elevator_contact_block_entity.dart';

/// `ElevatorColumn.ColumnCoords`: the column of a contact: its block x/z and the side the contact
/// faces.
final class ColumnCoords {
  final int x;
  final int z;
  final Direction side;

  const ColumnCoords(this.x, this.z, this.side);

  ColumnCoords relative(Pos anchor) =>
      ColumnCoords(x + anchor.$1, z + anchor.$3, side);

  NbtMap write() => NbtMap()
    ..putInt('X', x)
    ..putInt('Z', z)
    ..putString('Side', side.name);

  static ColumnCoords read(NbtMap tag) => ColumnCoords(
    tag.getInt('X'),
    tag.getInt('Z'),
    Direction.byName(tag.getString('Side')) ?? Direction.north,
  );

  @override
  bool operator ==(Object other) =>
      other is ColumnCoords &&
      other.x == x &&
      other.z == z &&
      other.side == side;

  @override
  int get hashCode => Object.hash(x, z, side);

  @override
  String toString() => 'ColumnCoords($x, $z, $side)';
}

/// `ElevatorColumn`.
final class ElevatorColumn {
  /// One map per world id (`WorldAttached<Map<ColumnCoords, ElevatorColumn>>`).
  static final Map<String, Map<ColumnCoords, ElevatorColumn>> _loaded = {};

  final String worldId;
  final ColumnCoords coords;

  /// The contact y levels, sorted.
  final List<int> contacts = [];
  int targetedYLevel = 0;
  bool isActive = false;
  bool targetAvailable = false;
  int namesListVersion = 0;

  ElevatorColumn(this.worldId, this.coords);

  static ElevatorColumn? get(String worldId, ColumnCoords? coords) {
    if (coords == null) return null;
    return _loaded[worldId]?[coords];
  }

  static ElevatorColumn getOrCreate(String worldId, ColumnCoords coords) =>
      _loaded.putIfAbsent(worldId, () => {})[coords] ??= ElevatorColumn(
        worldId,
        coords,
      );

  /// Forgets the columns of a world (world unload).
  static void forgetWorld(String worldId) => _loaded.remove(worldId);

  static void clear() => _loaded.clear();

  BlockEntityStore get _store => ActuatorRuntime.instance.store;
  World? get _world => ActuatorRuntime.instance.worlds.byId(worldId);

  void markDirty() {
    for (final pos in getContacts()) {
      final be = _store.at(worldId, pos.toBlockPos());
      if (be is ElevatorContactBlockEntity) be.markDirty();
    }
  }

  /// `floorReached`: the contacts show the floor name they just reached.
  void floorReached(String name) {
    for (final pos in getContacts()) {
      final be = _store.at(worldId, pos.toBlockPos());
      if (be is ElevatorContactBlockEntity) be.updateDisplayedFloor(name);
    }
  }

  /// `compileNamesList`: `(y, (shortName, longName))` for the contacts, top first.
  List<(int, (String, String))> compileNamesList() {
    final result = <(int, (String, String))>[];
    for (final pos in getContacts()) {
      final be = _store.at(worldId, pos.toBlockPos());
      if (be is ElevatorContactBlockEntity) result.add((pos.$2, be.getNames()));
    }
    return result;
  }

  void namesChanged() => namesListVersion++;

  /// The contact positions of the column, `(x, y, z)`.
  List<Pos> getContacts() => [for (final y in contacts) contactAt(y)];

  /// `gatherAll`: redstone contacts in the column become elevator contacts.
  Future<void> gatherAll() async {
    final world = _world;
    if (world == null) return;
    final minY = world.getMinY();
    final maxY = world.getMinY() + 383;
    for (var y = minY; y <= maxY + 1; y++) {
      final pos = contactAt(y);
      final state = _stateAt(pos);
      final column = contactColumnCoords(state, pos);
      if (column != coords) continue;
      if (state.key == 'create:elevator_contact') continue;
      // `BlockHelper.copyProperties`: only the properties the elevator contact has survive.
      final contactProps =
          manifestBlocksByKey['elevator_contact']?.properties ?? const [];
      final names = {for (final p in contactProps) p.name};
      final props = {
        for (final e in state.props.entries)
          if (names.contains(e.key)) e.key: e.value,
      };
      await world.setBlockState(
        pos: pos.toBlockPos(),
        state:
            BlockRegistry.resolveState('create:elevator_contact', props) ?? 0,
        updateFlags: BlockUpdateFlags.normal,
      );
    }
  }

  Pos contactAt(int y) => (coords.x, y, coords.z);

  void setActive(bool active) {
    isActive = active;
    markDirty();
    _checkEmpty();
  }

  void target(int yLevel) {
    targetedYLevel = yLevel;
    targetAvailable = true;
  }

  int getTargetedYLevel() => targetedYLevel;

  /// `initNames`: fills the missing short names with consecutive floor numbers.
  void initNames() {
    int? prevLevel;
    for (var i = 0; i < contacts.length; i++) {
      final y = contacts[i];
      final be = _store.at(worldId, contactAt(y).toBlockPos());
      if (be is! ElevatorContactBlockEntity) continue;

      int? currentLevel;
      if (be.shortName.trim().isNotEmpty) {
        currentLevel = int.tryParse(be.shortName);
        if (currentLevel == null) continue;
      }
      if (prevLevel != null) currentLevel = prevLevel + 1;

      int? nextLevel;
      for (var peekI = i + 1; peekI < contacts.length; peekI++) {
        final peek = _store.at(
          worldId,
          contactAt(contacts[peekI]).toBlockPos(),
        );
        if (peek is! ElevatorContactBlockEntity) continue;
        final value = int.tryParse(peek.shortName);
        if (value == null) continue;
        if (currentLevel != null && currentLevel >= value) {
          peek.shortName = '';
          break;
        }
        nextLevel = value;
        break;
      }

      currentLevel ??= nextLevel != null ? nextLevel - 1 : 0;
      be.updateName('$currentLevel', be.longName);
      prevLevel = currentLevel;
    }
  }

  void add(Pos contactPos) {
    final coord = contactPos.$2;
    if (contacts.contains(coord)) return;
    var index = 0;
    for (; index < contacts.length; index++) {
      if (contacts[index] > coord) break;
    }
    contacts.insert(index, coord);
    namesChanged();
  }

  void remove(Pos contactPos) {
    contacts.remove(contactPos.$2);
    _checkEmpty();
    namesChanged();
  }

  void _checkEmpty() {
    if (contacts.isEmpty && !isActive) _loaded[worldId]?.remove(coords);
  }

  /// `ElevatorContactBlock.getColumnCoords`: the column of an elevator or redstone contact at
  /// [pos], `null` for any other block.
  static ColumnCoords? contactColumnCoords(BState state, Pos pos) {
    if (state.key != 'create:elevator_contact' &&
        state.key != 'create:redstone_contact')
      return null;
    final facing = state.dir('facing') ?? Direction.south;
    return ColumnCoords(pos.$1, pos.$3, facing);
  }

  BState _stateAt(Pos pos) {
    final world = _world;
    if (world == null) return BState.air;
    return HostBlockGetter.stateOfId(
      world.getBlockStateId(pos: pos.toBlockPos()),
    );
  }
}
