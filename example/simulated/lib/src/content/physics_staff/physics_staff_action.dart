// The physics staff's action, as the serverbound payload carries it.
//
// `PhysicsStaffAction.STREAM_CODEC` is `CatnipStreamCodecBuilders.ofEnum`, which
// is a **VarInt ordinal**, not a byte: the order below is the Java declaration
// order and may not be sorted.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.physics_staff.PhysicsStaffAction
import 'package:pumpkin_api/pumpkin_api_core.dart';

/// What the player did with the staff.
enum PhysicsStaffAction {
  /// Let go of the dragged sub-level.
  stopDrag,

  /// Toggle the lock on the sub-level.
  lock,

  /// Start dragging the sub-level.
  startDrag;

  /// The Java constant name (`STOP_DRAG`, `LOCK`, `START_DRAG`).
  String get javaName => switch (this) {
    PhysicsStaffAction.stopDrag => 'STOP_DRAG',
    PhysicsStaffAction.lock => 'LOCK',
    PhysicsStaffAction.startDrag => 'START_DRAG',
  };

  /// `PhysicsStaffAction.STREAM_CODEC`: a VarInt ordinal.
  static PhysicsStaffAction read(PacketReader r) {
    final ordinal = r.readVarInt();
    if (ordinal < 0 || ordinal >= PhysicsStaffAction.values.length) {
      throw PacketException('Invalid PhysicsStaffAction ordinal $ordinal');
    }
    return PhysicsStaffAction.values[ordinal];
  }

  /// The writer of [read].
  void write(PacketWriter w) => w.writeVarInt(index);
}
