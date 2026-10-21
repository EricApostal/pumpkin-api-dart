// The contraption-diagram payloads.
//
// `diagram_data` is a map whose keys are force-group resource locations and
// whose values are lists of `PointForce`. Both wrappers add a VarInt count, and
// the point force itself is `VarInt 2, (VarInt 3, 3 doubles), (VarInt 3, 3
// doubles)` — see `SimWire.writePointForce`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.packets.contraption_diagram.*
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../../content/entities/diagram/diagram_config.dart';
import '../sim_packet.dart';
import '../sim_wire.dart';

/// `simulated:request_diagram_data` — the client opened a diagram and asks for
/// one frame of forces.
final class RequestDiagramDataPacket implements SimPacket {
  static const String type = 'simulated:request_diagram_data';

  /// The sub-level's uuid.
  final String subLevel;

  const RequestDiagramDataPacket(this.subLevel);

  @override
  String get id => type;

  static final SimCodec<RequestDiagramDataPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) => w.writeUuid(p.subLevel),
    (r) => RequestDiagramDataPacket(r.readUuid()),
  );
}

/// `simulated:diagram_data` — the recorded forces of one physics tick, keyed by
/// force group, plus the mass they were recorded for.
final class DiagramDataPacket implements SimPacket {
  static const String type = 'simulated:diagram_data';

  /// Force group id to the forces recorded in it.
  final Map<String, List<PointForce>> forces;

  final double mass;

  DiagramDataPacket(Map<String, List<PointForce>> forces, this.mass)
    : forces = Map<String, List<PointForce>>.unmodifiable({
        for (final entry in forces.entries) entry.key: List<PointForce>.unmodifiable(entry.value),
      });

  @override
  String get id => type;

  static final SimCodec<DiagramDataPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w.writeVarInt(p.forces.length);
      p.forces.forEach((groupId, forces) {
        w.writeString(groupId);
        w.writeList(forces, SimWire.writePointForce);
      });
      w.writeDouble(p.mass);
    },
    (r) {
      final count = r.readVarInt();
      if (count < 0) throw PacketException('Negative force group count $count');
      final forces = <String, List<PointForce>>{};
      for (var i = 0; i < count; i++) {
        final id = r.readString();
        forces[id] = r.readList(SimWire.readPointForce);
      }
      return DiagramDataPacket(forces, r.readDouble());
    },
  );
}

/// `simulated:save_diagram` — the client changed the diagram's settings.
final class DiagramSaveConfigPacket implements SimPacket {
  static const String type = 'simulated:save_diagram';

  final int entityID;
  final DiagramConfig config;

  const DiagramSaveConfigPacket(this.entityID, this.config);

  @override
  String get id => type;

  static final SimCodec<DiagramSaveConfigPacket> codec = SimCodec(
    type,
    SimPacketDirection.serverbound,
    (w, p) {
      w.writeInt(p.entityID);
      p.config.write(w);
    },
    (r) => DiagramSaveConfigPacket(r.readInt(), DiagramConfig.read(r)),
  );
}

/// `simulated:open_diagram` — the server tells the client to open the screen.
final class DiagramOpenPacket implements SimPacket {
  static const String type = 'simulated:open_diagram';

  final int entityID;
  final DiagramConfig config;

  const DiagramOpenPacket(this.entityID, this.config);

  @override
  String get id => type;

  static final SimCodec<DiagramOpenPacket> codec = SimCodec(
    type,
    SimPacketDirection.clientbound,
    (w, p) {
      w.writeInt(p.entityID);
      p.config.write(w);
    },
    (r) => DiagramOpenPacket(r.readInt(), DiagramConfig.read(r)),
  );
}
