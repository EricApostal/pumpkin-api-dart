// `ElevatorContactBlockEntity`: a floor contact of an elevator column. It owns the floor names, the
// door control mode and the "activate" pulse that redstone contact checks read.
//
// Java: `content/contraptions/elevator/ElevatorContactBlockEntity`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/decoration.dart' show DoorControlBehaviour;
import '../../api/blocks.dart' show HostBlockGetter;
import '../../core/block_entity.dart';
import 'elevator_column.dart';

final class ElevatorContactBlockEntity extends CreateBlockEntity {
  ElevatorContactBlockEntity(super.worldId, super.pos) {
    // `addBehaviours`: added at construction so `read` restores the saved door control mode.
    doorControls = addBehaviour(DoorControlBehaviour());
  }

  DoorControlBehaviour? doorControls;
  ColumnCoords? columnCoords;
  bool activateBlock = false;

  String shortName = '';
  String longName = '';
  String lastReportedCurrentFloor = '';

  int _yTargetFromNbt = _intMin;
  bool _deferNameGenerator = false;

  static const int _intMin = -0x80000000;

  @override
  void onLoad() {
    super.onLoad();
    columnCoords = ElevatorColumn.contactColumnCoords(
      HostBlockGetter.stateOfId(world!.getBlockStateId(pos: this.pos)),
      (this.pos.x, this.pos.y, this.pos.z),
    );
    if (columnCoords == null) return;
    final column = ElevatorColumn.getOrCreate(worldId, columnCoords!);
    column.add((this.pos.x, this.pos.y, this.pos.z));
    if (shortName.trim().isEmpty) _deferNameGenerator = true;
    if (_yTargetFromNbt == _intMin) return;
    column.target(_yTargetFromNbt);
    _yTargetFromNbt = _intMin;
  }

  @override
  void tick() {
    super.tick();
    if (!_deferNameGenerator) return;
    final coords = columnCoords;
    if (coords != null) ElevatorColumn.getOrCreate(worldId, coords).initNames();
    _deferNameGenerator = false;
  }

  @override
  void onRemoved() {
    final coords = columnCoords;
    if (coords != null)
      ElevatorColumn.get(
        worldId,
        coords,
      )?.remove((this.pos.x, this.pos.y, this.pos.z));
    super.onRemoved();
  }

  /// `updateDisplayedFloor`.
  void updateDisplayedFloor(String floor) {
    if (floor == lastReportedCurrentFloor) return;
    lastReportedCurrentFloor = floor;
    markDirty();
    sendData();
  }

  /// `updateName`.
  void updateName(String shortName, String longName) {
    this.shortName = shortName;
    this.longName = longName;
    _deferNameGenerator = false;
    markDirty();
    sendData();
    final coords = columnCoords;
    if (coords != null) ElevatorColumn.get(worldId, coords)?.namesChanged();
  }

  /// `getNames`.
  (String, String) getNames() => (shortName, longName);

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putString('ShortName', shortName);
    tag.putString('LongName', longName);
    tag.putString('LastReportedCurrentFloor', lastReportedCurrentFloor);
    if (!clientPacket) {
      tag.putBool('Activate', activateBlock);
      final coords = columnCoords;
      if (coords != null) {
        final column = ElevatorColumn.get(worldId, coords);
        if (column != null) {
          tag.putInt('ColumnTarget', column.getTargetedYLevel());
          if (column.isActive) tag.putCompound('ColumnActive', NbtCompound());
        }
      }
    }
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    shortName = tag.getString('ShortName') ?? '';
    longName = tag.getString('LongName') ?? '';
    final reported = tag.getString('LastReportedCurrentFloor');
    if (reported != null) lastReportedCurrentFloor = reported;
    super.read(tag, clientPacket: clientPacket);
    if (clientPacket) return;
    activateBlock = tag.getBool('Activate') ?? false;
    if (!tag.containsKey('ColumnTarget')) return;
    final target = tag.getInt('ColumnTarget') ?? 0;
    final active = tag.containsKey('ColumnActive');
    final coords = columnCoords;
    if (coords == null) {
      _yTargetFromNbt = target;
      return;
    }
    final column = ElevatorColumn.getOrCreate(worldId, coords);
    column.target(target);
    column.setActive(active);
  }
}
