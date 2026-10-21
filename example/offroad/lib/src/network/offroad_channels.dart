// The payload channel Offroad registers, as its `VeilPacketManager` reports it in
// `neoforge:register`. Pure data (no host imports), so the VM tests and the
// plugin both use it.
//
// Java (26.3 branch):
// `Simulated-Project/offroad/common/src/main/java/dev/ryanhcode/offroad/network/OffroadPacketManager.java`
// registers it with `VeilPacketManager.create(Offroad.MOD_ID, "0.1")`; the packet
// is `network/borehead_bearing/ClientboundMultiMiningSync.java` and flows
// `playToClient`. It does not pass `optional = true`, so a client without Offroad
// is refused exactly as it would be by a NeoForge server that has it installed.
//
// Pure: no host imports, so the VM tests can load it.
// ignore_for_file: implementation_imports
import 'package:create/src/core/payload.dart' show DeclaredPayload;

/// The version of the Veil channel (`OffroadPacketManager.create(Offroad.MOD_ID, "0.1")`).
const String offroadChannelVersion = '0.1';

/// Offroad's channels, in the Java registration order.
const List<DeclaredPayload> offroadChannels = [
  DeclaredPayload('offroad:borehead_sync_blocks', offroadChannelVersion, serverbound: false, optional: false),
];