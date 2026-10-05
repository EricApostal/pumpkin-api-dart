/// The only file that talks to the host (apart from the plugin class): the
/// item registry (the block registry is `BlockRegistries.host`, used by the
/// plugin class), and the block transformer call that does not exist yet.
library;

import 'package:pumpkin_api/pumpkin_api.dart';

import 'item_install.dart';
import 'omnitool.dart';

/// The host does not offer the call yet.
final class HostApiMissing extends UnsupportedError {
  HostApiMissing(super.what);
}

/// Registers items with Pumpkin's runtime item registry (`item-registry.wit`,
/// permission `registry.items`): the manifest's components are encoded with
/// the byte formats of the host's readers (`component_codec.dart`) and sent
/// with `register-item`, in call order, which decides the ids.
///
/// Only works while the server loads (`Plugin.onLoad`); after that the host
/// refuses with "items can only be registered before players connect".
final class HostItemRegistrar extends BackendItemRegistrar {
  HostItemRegistrar() : super(ItemRegistries.host);
}

/// Applies `minecraft:axe`, `minecraft:hoe` and `minecraft:shovel` block
/// transformers for the block the player just right-clicked.
///
/// Needed from the host: run a named transformer at a position and face on
/// behalf of a player (state change, sound, particles, durability and loot as
/// the dedicated tool does) and report whether it applied. The click's face
/// and hand are not in the interact event; the host call should take them from
/// the player's last use-item-on packet. Until then this throws
/// [HostApiMissing] and the omnitool handler leaves the click alone.
BlockTransformerPort blockTransformersFor(PlayerInteractEventData event) =>
    throw HostApiMissing('The host cannot run block transformers.');
