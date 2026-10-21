// The Pumpkin plugin of Sable: declares the mod and the payload channels its
// `VeilPacketManager` registers, through Create's generic addon hook.
//
// Sable's content (sub-levels, physics, storage) is registered by the modules of
// `package:sable`; this plugin is the component that announces them to the
// NeoForge handshake. The host merges this declaration with Create's and with
// every other plugin's into the one `neoforge:register` answer, so a client with
// Sable installed negotiates instead of being refused.
//
// Host: this file uses `pumpkin_api`.
//
// Java: `dev.ryanhcode.sable.Sable`
import 'package:create/create.dart' show CreateAddon, DeclaredPayload, createAddonNeoForgeDeclaration;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../sable_channels.dart';

/// Sable as an addon of Create's declaration model.
final class SableAddon extends CreateAddon {
  const SableAddon();

  @override
  String get modId => 'sable';

  @override
  String get version => '0.1.0';

  @override
  String get displayName => 'Sable';

  @override
  Iterable<DeclaredPayload> get channels => sableChannels;
}

/// The plugin of Sable.
final class SablePlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'sable',
    version: '0.1.0',
    description: 'Server side of Sable for Pumpkin: sub-levels, their plots and their physics.',
    permissions: [Permissions.neoforge],
  );

  @override
  Future<void> onLoad(Context context) async {
    context.declareNeoForge(createAddonNeoForgeDeclaration(const SableAddon()));
    logger.info('Sable declared ${sableChannels.length} payload channels.');
  }
}
