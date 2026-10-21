// The NeoForge declaration of Simulated: one `CreateAddon`, one mod id, the 37
// channels of `SimPacketManager`.
//
// Create's own plugin knows nothing about Simulated; this package adds itself
// through the generic addon hook (`CreateAddon`), and the host merges the two
// declarations into the single `neoforge:register` answer.
//
// Pure: no host imports, so the VM tests can load the channel table.
//
// Java: dev.simulated_team.simulated.Simulated
//       dev.simulated_team.simulated.network.SimPacketManager
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'package:create/src/core/addon.dart';
import 'package:create/src/core/payload.dart' show DeclaredPayload;

import '../network/sim_payloads.dart';

/// The mod id (`Simulated.MOD_ID`).
const String simulatedModId = 'simulated';

/// The mod version the declaration shows.
const String simulatedModVersion = '0.1.0';

/// Every channel, in `SimPacketManager.init` order, version `0.1`, play phase,
/// required (Veil's convenience overloads never pass `optional = true`).
final List<DeclaredPayload> simChannels = SimPayloads.declarations;

/// Simulated as a Create addon.
///
/// [handled] is the set of channels whose codec *and* handler the plugin
/// registers on its own registry (`CreateRegistry.serverbound`), so the addon
/// must not declare them again: `PayloadRegistry._claim` refuses a second
/// registration of an id. Everything else is declared-only.
final class SimulatedAddon extends CreateAddon {
  const SimulatedAddon({this.handled = const {}});

  /// Channel ids registered with a handler elsewhere.
  final Set<String> handled;

  @override
  String get modId => simulatedModId;

  @override
  String get version => simulatedModVersion;

  @override
  String get displayName => 'Simulated';

  @override
  Iterable<DeclaredPayload> get channels => simChannels.where((c) => !handled.contains(c.id));
}
