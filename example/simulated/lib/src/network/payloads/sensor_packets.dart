// The sensor and label payloads: altitude sensor thresholds, the modulating
// receiver's window, a nameplate's text, and the lodestone compass position.
//
// `nameplate_change_name` carries `ByteBufCodecs.optional(STRING_UTF8)`, i.e. a
// boolean then the string — an empty name is *present* and empty, not absent.
// `update_client_lodestone` writes the position with its own
// `StreamCodec.of` (three doubles), not the Sable vector helper, but the bytes
// are identical.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.ConfigureAltitudeSensorPacket
//       …packets.ConfigureModulatingLinkedRecieverPacket
//       …packets.name_plate.NameplateChangeNamePacket
//       …packets.lodestone_compass.UpdateClientLodestonePositionPacket
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/common/pos.dart' show Pos;

import 'package:sable/sable.dart' show Vector3d;

import '../sim_packet.dart';
import '../sim_wire.dart';

/// `simulated:configure_altitude_sensor` — the two thresholds, clamped to 0..1
/// by the Java constructor.
final class ConfigureAltitudeSensorPacket implements SimPacket {
  static const String type = 'simulated:configure_altitude_sensor';

  /// The signal at the high end of the range.
  final double highSignal;

  /// The signal at the low end.
  final double lowSignal;

  final Pos pos;

  ConfigureAltitudeSensorPacket(this.pos, double highSignal, double lowSignal)
    : highSignal = _clamp01(highSignal),
      lowSignal = _clamp01(lowSignal);

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  String get id => type;

  static final SimCodec<ConfigureAltitudeSensorPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.pos)
      ..writeFloat(p.highSignal)
      ..writeFloat(p.lowSignal),
    (r) => ConfigureAltitudeSensorPacket(r.readBlockPos(), r.readFloat(), r.readFloat()),
  );
}

/// `simulated:configure_modulating_linked_reciever` — the signal window.
final class ConfigureModulatingLinkedRecieverPacket implements SimPacket {
  static const String type = 'simulated:configure_modulating_linked_reciever';

  final Pos pos;
  final int minRange;
  final int maxRange;

  const ConfigureModulatingLinkedRecieverPacket(this.pos, this.minRange, this.maxRange);

  @override
  String get id => type;

  static final SimCodec<ConfigureModulatingLinkedRecieverPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.pos)
      ..writeInt(p.minRange)
      ..writeInt(p.maxRange),
    (r) => ConfigureModulatingLinkedRecieverPacket(r.readBlockPos(), r.readInt(), r.readInt()),
  );
}

/// `simulated:nameplate_change_name` — the new text, or no text at all.
final class NameplateChangeNamePacket implements SimPacket {
  static const String type = 'simulated:nameplate_change_name';

  final Pos controllerPos;

  /// The new name; `null` clears it.
  final String? name;

  const NameplateChangeNamePacket(this.controllerPos, this.name);

  @override
  String get id => type;

  static final SimCodec<NameplateChangeNamePacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w
      ..writeBlockPos(p.controllerPos)
      ..writeOptional(p.name, (w, v) => w.writeString(v)),
    (r) => NameplateChangeNamePacket(r.readBlockPos(), r.readOptional((r) => r.readString())),
  );
}

/// `simulated:update_client_lodestone` — where a tracked lodestone is now.
final class UpdateClientLodestonePositionPacket implements SimPacket {
  static const String type = 'simulated:update_client_lodestone';

  final String id_;

  final Vector3d sentPosition;

  UpdateClientLodestonePositionPacket(this.id_, Vector3d sentPosition) : sentPosition = Vector3d.copy(sentPosition);

  @override
  String get id => type;

  static final SimCodec<UpdateClientLodestonePositionPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w.writeUuid(p.id_);
      SimWire.writeVector3d(w, p.sentPosition);
    },
    (r) => UpdateClientLodestonePositionPacket(r.readUuid(), SimWire.readVector3d(r)),
  );
}
