// The physics staff payloads: the actions, the drag stream, and the three
// clientbound views.
//
// `physics_staff_drag` is hand-written (`StreamCodec.of`) and carries a
// quaternion as **four floats**; `physics_staff_action` carries the action as a
// VarInt ordinal and the location as a raw three-double vector.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.physics_staff.*
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports

import 'package:sable/sable.dart' show Quaterniond, Vector3d;

import '../../content/physics_staff/physics_staff_action.dart';
import '../sim_packet.dart';
import '../sim_wire.dart';

/// `simulated:physics_staff_action` — lock / stop-drag / start-drag.
final class PhysicsStaffActionPacket implements SimPacket {
  static const String type = 'simulated:physics_staff_action';

  final PhysicsStaffAction action;

  /// The sub-level the action applies to.
  final String subLevel;

  /// Where the player pointed.
  final Vector3d location;

  PhysicsStaffActionPacket(this.action, this.subLevel, Vector3d location)
    : location = Vector3d.copy(location);

  @override
  String get id => type;

  static final SimCodec<PhysicsStaffActionPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      p.action.write(w);
      w.writeUuid(p.subLevel);
      SimWire.writeVector3d(w, p.location);
    },
    (r) => PhysicsStaffActionPacket(
      PhysicsStaffAction.read(r),
      r.readUuid(),
      SimWire.readVector3d(r),
    ),
  );
}

/// `simulated:physics_staff_drag` — one frame of a drag, in the player's space.
final class PhysicsStaffDragPacket implements SimPacket {
  static const String type = 'simulated:physics_staff_drag';

  final String subLevel;

  /// The goal, relative to the player.
  final Vector3d playerRelativeGoal;

  /// The point on the sub-level the player holds.
  final Vector3d localAnchor;

  /// The sub-level's orientation.
  final Quaterniond orientation;

  PhysicsStaffDragPacket(
    this.subLevel,
    Vector3d playerRelativeGoal,
    Vector3d localAnchor,
    Quaterniond orientation,
  ) : playerRelativeGoal = Vector3d.copy(playerRelativeGoal),
      localAnchor = Vector3d.copy(localAnchor),
      orientation = Quaterniond.copy(orientation);

  @override
  String get id => type;

  static final SimCodec<PhysicsStaffDragPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w.writeUuid(p.subLevel);
      SimWire.writeVector3d(w, p.playerRelativeGoal);
      SimWire.writeVector3d(w, p.localAnchor);
      SimWire.writeQuaterniond(w, p.orientation);
    },
    (r) => PhysicsStaffDragPacket(
      r.readUuid(),
      SimWire.readVector3d(r),
      SimWire.readVector3d(r),
      SimWire.readQuaterniond(r),
    ),
  );
}

/// `simulated:physics_staff_beam` — the beam another player is drawing.
final class PhysicsStaffBeamPacket implements SimPacket {
  static const String type = 'simulated:physics_staff_beam';

  final String uuid;
  final Vector3d start;
  final Vector3d end;

  PhysicsStaffBeamPacket(this.uuid, Vector3d start, Vector3d end)
    : start = Vector3d.copy(start),
      end = Vector3d.copy(end);

  @override
  String get id => type;

  static final SimCodec<PhysicsStaffBeamPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w.writeUuid(p.uuid);
      SimWire.writeVector3d(w, p.start);
      SimWire.writeVector3d(w, p.end);
    },
    (r) => PhysicsStaffBeamPacket(r.readUuid(), SimWire.readVector3d(r), SimWire.readVector3d(r)),
  );
}

/// `simulated:physics_staff_locks` — every sub-level uuid locked in a dimension.
final class PhysicsStaffLocksPacket implements SimPacket {
  static const String type = 'simulated:physics_staff_locks';

  /// `ResourceKey<Level>`: the dimension id.
  final String dimension;

  final List<String> locks;

  PhysicsStaffLocksPacket(this.dimension, Iterable<String> locks) : locks = List<String>.unmodifiable(locks);

  @override
  String get id => type;

  static final SimCodec<PhysicsStaffLocksPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      SimWire.writeResourceLocation(w, p.dimension);
      w.writeList(p.locks, (w, uuid) => w.writeUuid(uuid));
    },
    (r) => PhysicsStaffLocksPacket(
      SimWire.readResourceLocation(r),
      r.readList((r) => r.readUuid()),
    ),
  );
}

/// `simulated:physics_staff_drag_sessions` — who is dragging what, in a
/// dimension.
final class PhysicsStaffDragSessionsPacket implements SimPacket {
  static const String type = 'simulated:physics_staff_drag_sessions';

  final String dimension;

  /// `(player uuid, goal)` pairs, in order.
  final List<(String, Vector3d)> sessions;

  PhysicsStaffDragSessionsPacket(this.dimension, Iterable<(String, Vector3d)> sessions)
    : sessions = List<(String, Vector3d)>.unmodifiable(sessions);

  @override
  String get id => type;

  static final SimCodec<PhysicsStaffDragSessionsPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      SimWire.writeResourceLocation(w, p.dimension);
      w.writeList(p.sessions, (w, session) {
        w.writeUuid(session.$1);
        SimWire.writeVector3d(w, session.$2);
      });
    },
    (r) => PhysicsStaffDragSessionsPacket(SimWire.readResourceLocation(r), [
      for (var i = 0, n = r.readVarInt(); i < n; i++) (r.readUuid(), SimWire.readVector3d(r)),
    ]),
  );
}
