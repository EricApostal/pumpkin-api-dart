// The payload channels Sable registers, as its `VeilPacketManager` reports them
// in `neoforge:register`. Pure data (no host imports), so the VM tests and the
// plugin both use it.
//
// Java (26.3 branch): `sable/common/src/main/java/dev/ryanhcode/sable/network/tcp/SableTCPPackets.java`
// registers every channel below with `VeilPacketManager.create(Sable.MOD_ID, "1")`
// and `playToClient`/`playToServer`; the two dual snapshot payloads also travel
// over UDP, which is why they are declared here as well.
//
// None of them passes `optional = true`, so a client without one is refused
// exactly as it would be by a NeoForge server that has Sable installed.
// Pure: no host imports, so the VM tests can load it.
// ignore_for_file: implementation_imports
import 'package:create/src/core/payload.dart' show DeclaredPayload;

/// The mod id the channels live in.
const String sableModId = 'sable';

/// Sable's channels, in the Java registration order.
const List<DeclaredPayload> sableChannels = [
  // ClientboundSableSnapshotDualPacket (TCP and UDP)
  DeclaredPayload('sable:snapshot_packet', '1', serverbound: false, optional: false),
  // ClientboundSableSnapshotInfoDualPacket (TCP and UDP)
  DeclaredPayload('sable:snapshot_info_packet', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:stop_moving_sub_level', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:change_sub_level_name', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:start_tracking_sub_level', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:finalize_sub_level', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:stop_tracking_sub_level', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:change_bounds_sublevel', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:freeze_player', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:physics_property', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:floating_material', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:dimension_physics', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:recently_split_sub_level', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:udp_activation', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:enter_gizmo_mode', '1', serverbound: false, optional: false),
  DeclaredPayload('sable:punch_sub_level', '1', serverbound: true, optional: false),
  DeclaredPayload('sable:gizmo_move_sub_level', '1', serverbound: true, optional: false),
];
