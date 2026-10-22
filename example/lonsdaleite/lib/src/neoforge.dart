// The mod's NeoForge declaration. The host runs the handshake now (`neoforge.wit`,
// see `docs/neoforge-host.md` of pumpkin_api), so the plugin does not speak the
// protocol itself and no longer installs `pumpkin_neoforge`'s `NeoForgeServer`
// (which the library says only one plugin per server may do, and which would talk
// to the client on top of the host's handshake).
//
// What the declaration has to carry is the *vouch*: naming a registry is the claim
// that the entries the plugin registered in it are the client's, in the host's
// order. The host numbers them itself (`vanilla count + index`) and writes those
// ids in chunk data and packets, and a client that is not sent the snapshot
// resolves each id against its own order — a different item or block, silently. A
// registry the host numbers is sent whole or not at all
// (`crates/pumpkin-core/src/net/neoforge/registries.rs`, `syncable`), so leaving one
// out drops it from the sync for *every* plugin, not only for this one.
//
// Lonsdaleite has no payload channels, so nothing else is declared: the client's
// mod needs the ids, and a client without the mod is refused (`reject`), the way
// the plugin's own handshake refused it before.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'declared_registries.dart';
import 'manifest.dart';

/// The declaration of the mod in [manifest], for `Context.declareNeoForge`.
///
/// The registries come from [lonsdaleiteDeclaredRegistries] — the two the plugin
/// registers content into. Both are host-numbered, so the addition's `entries` are
/// ignored for them: what the host sends is its own dynamic registry, which is what
/// the plugin registered, in registration order.
///
/// `reject`: a client without the mod has none of the items, and a block the server
/// places would arrive as a different one, so such clients are disconnected with
/// [rejectMessage] (`{mods}` is replaced by the mod list; the host formats it).
NeoForgeDeclaration lonsdaleiteDeclaration(Manifest manifest) => NeoForgeDeclaration(
  mod: NeoForgeMod(
    id: manifest.mod.id,
    version: manifest.mod.version,
    displayName: manifest.mod.name,
  ),
  registries: [
    for (final key in lonsdaleiteDeclaredRegistries)
      NeoForgeRegistryAddition(key, const []),
  ],
  policy: NonNeoForgeClientPolicy.reject,
  rejectMessage:
      'This server runs the ${manifest.mod.name} port for Pumpkin: install the mod '
      '({mods}) to join.',
);