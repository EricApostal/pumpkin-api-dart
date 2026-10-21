// Every payload Simulated registers, by id and direction, on the Veil channel
// `simulated:0.1`.
//
// The order is the Java `SimPacketManager.init` order — the serverbound
// registrations interleaved with the clientbound ones, exactly as the Java
// method reads. Veil identifies a payload by its `CustomPacketPayload.Type`
// (the id), not by position, so the order is documentation and test stability,
// not wire compatibility; the *ids and directions* are the compatibility.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.network.SimPacketManager
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:create/src/core/payload.dart' show DeclaredPayload;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import 'payloads/assembly_packets.dart';
import 'payloads/control_packets.dart';
import 'payloads/diagram_packets.dart';
import 'payloads/handle_packets.dart';
import 'payloads/honey_glue_packets.dart';
import 'payloads/physics_staff_packets.dart';
import 'payloads/placement_packets.dart';
import 'payloads/rope_packets.dart';
import 'payloads/sensor_packets.dart';
import 'payloads/typewriter_packets.dart';
import '../content/end_sea/end_sea_physics.dart';
import 'sim_packet.dart';

/// The payload table of the mod.
abstract final class SimPayloads {
  /// Every payload, in `SimPacketManager.init` order.
  static final List<SimPacketCodec<SimPacket>> all = [
    _cast(AssemblePacket.codec),
    _cast(BlockEntityObservedPacket.codec),
    _cast(ConfigureAltitudeSensorPacket.codec),
    _cast(ConfigureModulatingLinkedRecieverPacket.codec),
    _cast(ThrottleLeverSignalPacket.codec),
    _cast(NameplateChangeNamePacket.codec),
    _cast(TypewriterKeyInteractionPacket.codec),
    _cast(TypewriterKeySavePacket.codec),
    _cast(TypewriterDisconnectUser.codec),
    _cast(TypewriterMenuModifySlots.codec),
    _cast(TypewriterSaveKeyToItemPacket.codec),
    _cast(SteeringWheelPacket.codec),
    _cast(PlaceSpringPacket.codec),
    _cast(PlaceMergingGluePacket.codec),
    _cast(UpdatePlayerUsingHandlePacket.codec),
    _cast(HoneyGlueSpawnPacket.codec),
    _cast(HoneyGlueChangeBoundsPacket.codec),
    _cast(HoneyGlueSyncBoundsPacket.codec),
    _cast(RopeRidingPacket.codec),
    _cast(RopeBreakPacket.codec),
    _cast(PhysicsStaffActionPacket.codec),
    _cast(PhysicsStaffDragPacket.codec),
    _cast(PhysicsStaffBeamPacket.codec),
    _cast(PhysicsStaffLocksPacket.codec),
    _cast(PhysicsStaffDragSessionsPacket.codec),
    _cast(PlungerLauncherShootPacket.codec),
    _cast(PhysicsAssemblerFailedPacket.codec),
    _cast(PhysicsAssemblerFlickAndHoldLeverPacket.codec),
    _cast(ClientboundPlayersHoldingHandlePacket.codec),
    _cast(ClientboundRopeDataPacket.codec),
    _cast(ClientboundRopeStoppedPacket.codec),
    _cast(ClientboundEndSeaPacket.codec),
    _cast(RequestDiagramDataPacket.codec),
    _cast(DiagramDataPacket.codec),
    _cast(DiagramSaveConfigPacket.codec),
    _cast(DiagramOpenPacket.codec),
    _cast(UpdateClientLodestonePositionPacket.codec),
  ];

  /// The codecs by payload id.
  static final Map<String, SimPacketCodec<SimPacket>> byId = {
    for (final codec in all) codec.id: codec,
  };

  /// The clientbound codecs, in registration order.
  static Iterable<SimPacketCodec<SimPacket>> get clientbound =>
      all.where((c) => c.direction == SimPacketDirection.clientbound);

  /// The serverbound codecs, in registration order.
  static Iterable<SimPacketCodec<SimPacket>> get serverbound =>
      all.where((c) => c.direction == SimPacketDirection.serverbound);

  /// The channel declaration of every payload: version `0.1`, play phase,
  /// required.
  static List<DeclaredPayload> get declarations => [
    for (final codec in all)
      DeclaredPayload(
        codec.id,
        SimChannel.version,
        serverbound: codec.direction == SimPacketDirection.serverbound,
        optional: false,
      ),
  ];

  /// Encodes a payload body (no type id; Veil writes that).
  static Uint8List encode(SimPacket packet) {
    final codec = byId[packet.id] ?? (throw ArgumentError.value(packet.id, 'packet', 'is not a Simulated payload'));
    return codec.encode(packet);
  }

  /// Decodes a payload body; throws for an unknown id.
  static SimPacket decode(String id, List<int> data) {
    final codec = byId[id] ?? (throw ArgumentError.value(id, 'id', 'is not a Simulated payload'));
    return codec.decode(data);
  }

  /// Widens a typed codec to `SimPacket`.
  static SimPacketCodec<SimPacket> _cast<T extends SimPacket>(SimPacketCodec<T> codec) => _WidenedCodec<T>(codec);
}

/// A codec viewed as its supertype.
final class _WidenedCodec<T extends SimPacket> implements SimPacketCodec<SimPacket> {
  final SimPacketCodec<T> _inner;

  _WidenedCodec(this._inner);

  @override
  String get id => _inner.id;

  @override
  SimPacketDirection get direction => _inner.direction;

  @override
  void write(PacketWriter buf, SimPacket value) => _inner.write(buf, value as T);

  @override
  SimPacket read(PacketReader buf) => _inner.read(buf);

  @override
  Uint8List encode(SimPacket value) => _inner.encode(value as T);

  @override
  SimPacket decode(List<int> data) => _inner.decode(data);
}
