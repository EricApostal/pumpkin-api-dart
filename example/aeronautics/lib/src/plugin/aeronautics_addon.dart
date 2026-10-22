// Aeronautics as an addon of Create's declaration model: the mod id and the
// payload channels of `aeronautics_channels.dart`, contributed through Create's
// generic hook. Nothing here names Aeronautics in Create.
//
// Host: this file uses `pumpkin_api` (through `package:create/create.dart`).
//
// The addon class itself needs no host binding, and `package:create/create.dart`
// re-exports `core/registry.dart`, which does use one — so the imports are from
// `src/`, the way `simulated`'s `sim_channels.dart` does it, and the VM tests can
// read the addon (see `test/registry_order_test.dart`).
// ignore_for_file: implementation_imports
import 'package:create/src/core/addon.dart' show CreateAddon;
import 'package:create/src/core/payload.dart' show DeclaredPayload;

import '../../aeronautics_channels.dart';

/// The mod Aeronautics declares.
final class AeronauticsAddon extends CreateAddon {
  const AeronauticsAddon();

  @override
  String get modId => aeronauticsModId;

  @override
  String get version => '0.1.0';

  @override
  String get displayName => 'Aeronautics';

  /// The registries Aeronautics registers content in are the client's.
  ///
  /// The ids the host writes for an item or a block are positions in its dynamic registry
  /// (`vanilla count + registration index`), and a client only numbers them the same way when it
  /// is *told* the host's order: `RegistryManager.applySnapshot` gives each entry the id the
  /// snapshot gives it. Declaring the channels alone leaves the client on its own order, so every
  /// id past the vanilla entries resolves to a different entry — the "adding an item to my
  /// inventory gives a different item" divergence. Naming `minecraft:item` and the rest is the
  /// claim that makes the host send them, and the names are pinned against the Java mod's own
  /// order in `aero_java_order.dart` (`CreateRegistry.useOrder`).
  @override
  bool get contentVerified => true;

  @override
  Iterable<DeclaredPayload> get channels => aeronauticsChannels;
}
