// The sliding door API for other modules (trains, contraptions): `SlidingDoorBlock.setOpen`, door
// control mode (`DoorControl` / `DoorControlBehaviour`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/direction.dart';
import '../common/host_bridge.dart';
import '../core/block_entity.dart';
import 'door.dart';
import 'door_host.dart';
import 'runtime.dart';

/// `SlidingDoorBlock.setOpen(entity, level, state, pos, open)` and friends.
final class SlidingDoors {
  final DecorationRuntime _rt;

  SlidingDoors(this._rt);

  /// Whether [state] is one of the sliding doors.
  bool isSlidingDoor(BState state) => slidingDoorKeys.contains(state.key);

  /// `SlidingDoorBlock.isFoldingDoor`.
  bool isFoldingDoor(BState state) => foldingDoorKeys.contains(state.key);

  /// `setOpen`: opens or closes the door at [pos] (and the other door of a double door).
  Future<void> setOpen(World world, BlockPos pos, bool open) async {
    final level = HostBlockGetter(world);
    final p = pos.toPos();
    final state = level.stateAt(p);
    if (!isSlidingDoor(state)) return;
    await applyDoorAction(_rt, world, slidingDoorSetOpen(level, p, state, open));
  }

  /// `DoorBlock.isOpen`.
  bool isOpen(BState state) => state.flag('open');
}

/// `DoorControl`: which side of a door a station's door control opens it for.
enum DoorControl {
  all,
  north,
  east,
  south,
  west,
  none;

  /// `matches(doorDirection)`.
  bool matches(Direction doorDirection) => switch (this) {
    DoorControl.all => true,
    DoorControl.north => doorDirection == Direction.north,
    DoorControl.east => doorDirection == Direction.east,
    DoorControl.south => doorDirection == Direction.south,
    DoorControl.west => doorDirection == Direction.west,
    DoorControl.none => false,
  };
}

/// `DoorControlBehaviour`: the door mode stored in a station block entity.
final class DoorControlBehaviour extends BlockEntityBehaviour {
  static const String typeId = 'doorControl';

  @override
  String get id => typeId;

  DoorControl mode = DoorControl.all;

  /// `set(mode)`.
  void set(DoorControl newMode) {
    if (mode == newMode) return;
    mode = newMode;
    owner.sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putString('DoorControl', mode.name.toUpperCase());
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    final name = tag.getString('DoorControl') ?? '';
    mode = DoorControl.values.firstWhere((m) => m.name.toUpperCase() == name, orElse: () => DoorControl.all);
  }
}
