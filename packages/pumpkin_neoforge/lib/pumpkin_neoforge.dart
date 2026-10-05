/// The server side of NeoForge's network negotiation and registry
/// synchronisation for Pumpkin plugins: a plugin that installs a
/// [NeoForgeServer] looks like a NeoForge server to a NeoForge client that has
/// the server's mods installed.
///
/// ```dart
/// final neoforge = NeoForgeServer(
///   NeoForgeServerSpec.vanillaPlus(
///     mods: [NeoForgeModInfo(id: 'lonsdaleite', version: '2.3.0')],
///     additions: {
///       'minecraft:item': ['lonsdaleite:raw_lonsdaleite'],
///       'minecraft:block': ['lonsdaleite:lonsdaleite_wardframe'],
///     },
///   ),
/// );
///
/// // in Plugin.onLoad:
/// neoforge.install(context);
/// ```
///
/// See README.md and docs/neoforge-protocol.md.
library;

export 'pumpkin_neoforge_core.dart';
export 'src/server.dart';
export 'src/play.dart' show NeoForgePlay;
