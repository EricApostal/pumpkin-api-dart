// The generic extension point: a package that adds content on top of Create
// declares its own mod and its own payload channels through this. Create never
// names an addon.
//
// An addon package implements [CreateAddon] once:
//
//   final class MyAddon extends CreateAddon {
//     const MyAddon();
//     @override String get modId => 'mymod';
//     @override String get version => '0.1.0';
//     @override Iterable<DeclaredPayload> get channels => myChannels;
//   }
//
// and its plugin declares it with `createAddonNeoForgeDeclaration` (see
// `plugin/create_addon.dart`). Adding another addon therefore needs no change to
// Create: the host merges every plugin's declaration into the single
// `neoforge:register` answer (`Aggregate::build` in
// `crates/pumpkin-core/src/net/neoforge/declaration.rs`), and `declare()` there
// refuses only a channel id or a mod id that two plugins both claim.
//
// Pure: no host imports, so the VM tests can load it.
import 'payload.dart';

/// A package that extends Create's declaration model.
abstract base class CreateAddon {
  const CreateAddon();

  /// The mod id; the namespace of the addon's channels (`mymod`).
  String get modId;

  /// The mod version shown to clients (`0.1.0`). Not the channel version: a
  /// channel carries the version of the registrar that declared it, which is
  /// per channel in [channels].
  String get version;

  /// Shown to players; defaults to [modId].
  String? get displayName => null;

  /// Channels the addon announces but does not decode here (the payload codec
  /// belongs to the addon, or is not ported yet). Play phase, like every
  /// channel of Create.
  Iterable<DeclaredPayload> get channels => const [];

  /// Whether the content the addon registered is verified against the client's
  /// release of the mod: every block, item, block entity type, menu, component,
  /// fluid, entity type, sound, particle and mob effect, name by name and in
  /// this order.
  ///
  /// `false` — the default, and what a port in progress keeps — announces the
  /// addon's channels but no registry: a `NeoForge` client that receives a
  /// registry entry it does not have disconnects with "The server sent
  /// registries with unknown keys", so the host keeps the content server-side
  /// until the port says it matches. Declaring the mod is enough for a client
  /// that has it to negotiate the channels; content is a separate claim.
  bool get contentVerified => false;

  /// Adds the addon's channels to [payloads], in the addon's order.
  ///
  /// An addon that handles a payload registers it on its own registry
  /// (`registry.serverbound` / `registry.clientbound`) in its module instead;
  /// both kinds end up in the declaration. An override must call `super` so the
  /// declared-only channels stay in it.
  void contribute<C>(PayloadRegistry<C> payloads) => payloads.declareAll(channels);
}
