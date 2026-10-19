// `ElevatorContraption`: the structure of an elevator pulley. It knows its column, the contact it
// belongs to and the floor it is heading to, and it publishes the floor list to the clients.
//
// Java: `content/contraptions/elevator/ElevatorContraption`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../common/common.dart';
import '../blocks/actuator_contract.dart';
import '../blocks/actuator_runtime.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/nbt_map.dart';
import '../core/structure_info.dart';
import '../pulley/pulley_contraption.dart';
import 'elevator_column.dart';
import 'elevator_contact_block_entity.dart';
import 'elevator_controls_handler.dart';

class ElevatorContraption extends PulleyContraption {
  ColumnCoords? column;
  int contactYOffset = 0;
  bool arrived = false;

  int maxContactY = 0;
  int minContactY = 0;
  int clientYTarget = 0;

  List<(int, (String, String))> namesList = const [];
  int _namesListVersion = -1;
  int _ticks = 0;

  // during assembly only
  int _contacts = 0;

  ElevatorContraption([super.initialOffset = 0]);

  @override
  String get typeId => 'create:elevator';

  /// `getGlobalColumn`.
  ColumnCoords? getGlobalColumn() => column?.relative(anchor);

  /// `getCurrentTargetY`: the target the column is set to, `null` when there is none or it is out
  /// of the column's range.
  int? getCurrentTargetY() {
    final coords = getGlobalColumn();
    if (coords == null) return null;
    final elevatorColumn = ElevatorColumn.get(_worldId, coords);
    if (elevatorColumn == null) return null;
    if (!elevatorColumn.targetAvailable) return null;
    final target = elevatorColumn.getTargetedYLevel();
    if (isTargetUnreachable(target)) return null;
    return target;
  }

  bool isTargetUnreachable(int contactY) =>
      contactY < minContactY || contactY > maxContactY;

  /// `disableActorOnStart` is a no-op for elevators: the floor controls stay usable while the
  /// contraption moves.
  @override
  void startMoving(ContraptionLevel level) {
    super.startMoving(level);
    for (final stack in List.of(disabledActors)) {
      setActorsActive(stack, true);
    }
    disabledActors.clear();
  }

  @override
  Future<bool> assemble(ContraptionLevel level, Pos pos) async {
    if (!searchMovedStructure(level, pos, null)) return false;
    if (blocks.isEmpty) return false;
    if (_contacts == 0) throw AssemblyException.noContacts();
    if (_contacts > 1) throw AssemblyException.tooManyContacts();
    final elevatorColumn = ElevatorColumn.get(level.worldId, getGlobalColumn());
    if (elevatorColumn != null && elevatorColumn.isActive)
      throw AssemblyException.columnConflict();
    startMoving(level);
    return true;
  }

  /// `capture`: the redstone contact in the structure is the elevator's contact.
  @override
  CapturedBlock capture(ContraptionLevel level, Pos pos) {
    final state = level.stateAt(pos);
    if (state.key == 'create:redstone_contact') {
      final facing = state.dir('facing') ?? Direction.south;
      if (facing.axis != Axis.y) {
        _contacts++;
        final local = toLocalPos(pos.relative(facing));
        column = ColumnCoords(local.$1, local.$3, facing.opposite);
        contactYOffset = local.$2;
      }
    }
    return super.capture(level, pos);
  }

  int getContactYOffset() => contactYOffset;

  /// `broadcastFloorData`: the reached contact shows its own floor name.
  void broadcastFloorData(ContraptionLevel level, Pos contactPos) {
    final elevatorColumn = ElevatorColumn.get(level.worldId, getGlobalColumn());
    final be = ActuatorRuntime.maybe?.store.at(
      level.worldId,
      BlockPos(x: contactPos.$1, y: contactPos.$2, z: contactPos.$3),
    );
    if (be is ElevatorContactBlockEntity)
      elevatorColumn?.floorReached(be.shortName);
  }

  @override
  void tickStorage(ContraptionEntityHandle entity) {
    super.tickStorage(entity);
    _ticks++;
    if (_ticks % 10 != 0) return;

    final coords = getGlobalColumn();
    if (coords == null) return;
    final elevatorColumn = ElevatorColumn.get(_worldId, coords);
    if (elevatorColumn == null) return;
    if (elevatorColumn.namesListVersion == _namesListVersion) return;

    namesList = elevatorColumn.compileNamesList();
    _namesListVersion = elevatorColumn.namesListVersion;
    ActuatorHosts.payloadBus?.sendToTrackingAt(
      'create:update_elevator_floors',
      _worldId,
      (
        entity.position.$1.floor(),
        entity.position.$2.floor(),
        entity.position.$3.floor(),
      ),
      {
        'entityId': entity.entityId,
        'floors': [
          for (final (y, names) in namesList)
            {
              'first': y,
              'second': {'first': names.$1, 'second': names.$2},
            },
        ],
      },
    );
  }

  String get _worldId => levelForColliders?.worldId ?? '';

  @override
  NbtMap writeNbt({bool spawnPacket = false}) {
    final tag = super.writeNbt(spawnPacket: spawnPacket);
    tag.putBool('Arrived', arrived);
    if (column != null) tag.putCompound('Column', _writeColumn(column!));
    tag.putInt('ContactY', contactYOffset);
    tag.putInt('MaxContactY', maxContactY);
    tag.putInt('MinContactY', minContactY);
    return tag;
  }

  @override
  void readNbt(ContraptionLevel level, NbtMap nbt, {bool spawnData = false}) {
    arrived = nbt.getBool('Arrived');
    final columnTag = nbt.getCompoundOrNull('Column');
    column = columnTag == null ? null : _readColumn(columnTag);
    contactYOffset = nbt.getInt('ContactY');
    maxContactY = nbt.getInt('MaxContactY');
    minContactY = nbt.getInt('MinContactY');
    super.readNbt(level, nbt, spawnData: spawnData);
  }

  /// `setClientYTarget`.
  void setClientYTarget(int target) {
    if (clientYTarget == target) return;
    clientYTarget = target;
    syncControlDisplays();
  }

  /// `syncControlDisplays`: the floor selection of the controls actor follows the target.
  void syncControlDisplays() {
    if (namesList.isEmpty) return;
    for (var i = 0; i < namesList.length; i++) {
      if (namesList[i].$1 == clientYTarget) setAllControlsToFloor(i);
    }
  }

  /// `setAllControlsToFloor`.
  void setAllControlsToFloor(int floorIndex) {
    for (final context in actors) {
      final data = context.temporaryData;
      if (data is ElevatorFloorSelection) data.currentIndex = floorIndex;
    }
  }

  static NbtMap _writeColumn(ColumnCoords coords) => coords.write();

  static ColumnCoords _readColumn(NbtMap tag) => ColumnCoords.read(tag);
}
