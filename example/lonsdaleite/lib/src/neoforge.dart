import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge.dart';

import 'block_install.dart';
import 'item_install.dart';
import 'manifest.dart';
import 'neoforge_spec.dart';

/// How the plugin opens the NeoForge negotiation: `adhoc` (the default, see
/// [installNeoForge]) or `full` (the real order, with the pre-brand hold). A
/// constant, not a config file: the plugin has no config of its own.
const NeoForgeNegotiation lonsdaleiteNegotiation = NeoForgeNegotiation.adhoc;

/// Makes the server speak NeoForge's configuration protocol so clients with
/// the Lonsdaleite mod can join: the registry sync (items and the wardframe
/// block, from which the client numbers the block states) and the check that
/// the client has all of it. See `packages/pumpkin_neoforge` and
/// `docs/neoforge-protocol.md`.
///
/// Call this **after** the items and the block are registered
/// ([installManifestItems], [installManifestBlock]): the sync tells clients
/// the ids the host assigned, [installation] and [blocks] carry them.
///
/// The negotiation is [lonsdaleiteNegotiation], by default the library's
/// `adhoc` mode (no `neoforge:register` query; the host's play packets stay
/// vanilla), and clients that are not NeoForge are refused with a message, since
/// they lack the mod's items and would break on the first stack of one.
///
/// Why `adhoc` and not `full`: Lonsdaleite has no payloads of its own, so the
/// mod needs no channel negotiation, and the registry sync with its
/// acknowledgement already proves that the client has every entry. `full`
/// makes the client treat the connection as NeoForge for good, which costs
/// something that is not verified against a live client: the elytra attribute
/// and `neoforge:recipe_content` have to be sent by the plugin
/// (`NeoForgeServer.installPlay`), the host writes NeoForge encodings for
/// particles, and the vanilla attribute list of the host has to match the
/// client's. Switch to `full` by changing [lonsdaleiteNegotiation] (the plugin
/// then installs the play helpers as well) once a live client has been tried.
NeoForgeServer installNeoForge(
  Context context,
  Manifest manifest,
  ItemInstallation installation,
  BlockInstallation blocks, {
  NeoForgeServerOptions options = const NeoForgeServerOptions(
    negotiation: lonsdaleiteNegotiation,
  ),
}) {
  final spec = neoForgeSpecFor(
    manifest,
    installation.items,
    blocks: [blocks.block],
  );
  final server = NeoForgeServer(spec, options: options);
  server.install(context);
  // Only the full mode marks connections as NeoForge, and only those need the
  // play-phase extras (elytra attribute, recipe content).
  if (options.negotiation == NeoForgeNegotiation.full) {
    server.installPlay(context);
  }
  // NeoForgeServer logs every decided handshake (joined, refused, not NeoForge).
  logger.info(
    'NeoForge registry sync installed: ${manifest.mod.name} ${manifest.mod.version}, '
    '${installation.items.length} items (ids ${installation.vanillaCount} to '
    '${installation.vanillaCount + installation.items.length - 1}), '
    'block ${blocks.block.key} (id ${blocks.block.id}, ${blocks.block.stateCount} states from state id '
    '${blocks.block.baseStateId}), '
    'negotiation ${options.negotiation.name}.',
  );
  return server;
}
