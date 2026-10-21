// The payload channels Aeronautics registers, as its `VeilPacketManager` reports
// them in `neoforge:register`. Pure data (no host imports), so the VM tests and
// the plugin both use it.
//
// Java (26.3 branch):
// `Simulated-Project/aeronautics/common/src/main/java/dev/eriksonn/aeronautics/network/AeroPacketManager.java`
// registers it with `VeilPacketManager.create(Aeronautics.MOD_ID, "0.1")` and
// `playToServer`; the packet is
// `network/packets/LevititeCatalystCrystallizationPacket.java`. It does not pass
// `optional = true`, so a client without Aeronautics is refused exactly as it
// would be by a NeoForge server that has it installed.
//
// Pure: no host imports, so the VM tests can load it.
// ignore_for_file: implementation_imports
import 'package:create/src/core/payload.dart' show DeclaredPayload;

/// The mod id the channels live in.
const String aeronauticsModId = 'aeronautics';

/// Aeronautics' channels, in the Java registration order.
const List<DeclaredPayload> aeronauticsChannels = [
  DeclaredPayload('aeronautics:levitite_blend_crystallize', '0.1', serverbound: true, optional: false),
];
