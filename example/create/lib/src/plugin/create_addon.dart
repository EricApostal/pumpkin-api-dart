// The NeoForge half of the addon hook: turns a [CreateAddon] into the
// declaration of its mod. See `core/addon.dart` for the extension point itself.
//
// One plugin, one declaration, one mod id — but not one *answer*: the host
// merges every plugin's declaration into the single `neoforge:register` answer
// (`Aggregate::build` in `crates/pumpkin-core/src/net/neoforge/declaration.rs`, and its
// `aggregation_merges_all_plugins` test), so a client sees the union of Create's
// channels and every addon's, exactly as it would see the union of the Java
// mods' channels.
//
// Host: this file uses `pumpkin_api` (the declaration types).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/addon.dart';
import '../core/registry.dart';
import 'create_neoforge.dart';

/// The NeoForge declaration of [addon]: [registry] (the addon's own content
/// registry, when it has one) with the addon's channels contributed to it.
///
/// ```dart
/// context.declareNeoForge(createAddonNeoForgeDeclaration(const MyAddon(), registry: myRegistry));
/// ```
///
/// The addon's channels always go into the declaration. Its *content* goes only
/// when [CreateAddon.contentVerified] says it matches the client's release of the
/// mod; until then the registries are not named and the host keeps the content
/// server-side (a client that lacks an entry would disconnect on it).
///
/// `context.declareNeoForge` throws a [HostException] when the declaration is
/// invalid, when a channel or mod id is already declared by another plugin, or
/// when players can connect already. Needs `Permissions.neoforge`.
NeoForgeDeclaration createAddonNeoForgeDeclaration(CreateAddon addon, {CreateRegistry? registry}) {
  final target = registry ?? CreateRegistry();
  addon.contribute(target.payloads);
  return createNeoForgeDeclaration(
    target,
    mod: NeoForgeMod(id: addon.modId, version: addon.version, displayName: addon.displayName),
    contentVerified: addon.contentVerified,
  );
}
