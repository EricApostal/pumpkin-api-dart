// The channels whose codec *and* handler the plugin registers, in
// `SimPacketManager.init` order: the serverbound handlers over
// `CreateRegistry.serverbound`, plus the one clientbound channel the server
// pushes (`simulated:honey_glue_sync`).
//
// This list is the contract between the two halves of the payload layer: the
// plugin registers exactly these, and `SimulatedAddon` declares the other 30 as
// declared-only. A channel in both would throw `DuplicateChannelException` when
// the declaration is built, and a channel in neither would silently disappear
// from the NeoForge answer, so the two are kept in one place and checked by
// `test/payload_codec_test.dart`.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.SimPacketManager#init (the subset
//       whose block entity or entity is ported)
import 'payloads/assembly_packets.dart';
import 'payloads/control_packets.dart';
import 'payloads/honey_glue_packets.dart';
import 'payloads/placement_packets.dart';
import 'sim_packet.dart';
import 'sim_payloads.dart';

/// The payload ids the plugin handles.
abstract final class SimHandledPayloads {
  /// The handled channel ids, in registration order: the serverbound handlers
  /// first, then the one clientbound channel the plugin sends
  /// (`simulated:honey_glue_sync`, the resize of a live volume).
  static const List<String> ids = [
    AssemblePacket.type,
    ThrottleLeverSignalPacket.type,
    SteeringWheelPacket.type,
    PlaceSpringPacket.type,
    HoneyGlueSpawnPacket.type,
    HoneyGlueChangeBoundsPacket.type,
    HoneyGlueSyncBoundsPacket.type,
  ];

  /// The ids of [ids] that travel from the client to the server.
  static List<String> get serverboundIds => [
    for (final id in ids)
      if (SimPayloads.byId[id]?.direction == SimPacketDirection.serverbound) id,
  ];

  /// The handled ids as a set (the addon's filter).
  static final Set<String> idSet = Set<String>.unmodifiable(ids);
}
