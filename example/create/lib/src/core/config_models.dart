import 'package:dart_mappable/dart_mappable.dart';

part 'config_models.mapper.dart';

/// `mod_version` in Create's gradle.properties (the 26.3 port).
const String createModVersion = '6.0.11';

/// The `core` section of `config.json`.
@MappableClass()
class CoreSettings with CoreSettingsMappable {
  /// Declare the plugin to the host's NeoForge handshake. The real Create client
  /// needs it: NeoForge clients reject a server that does not answer the
  /// handshake ("not running NeoForge"). The host only runs the handshake once a
  /// plugin declares something, and non-NeoForge clients are still let in.
  final bool neoforge;

  /// The version of the Create mod the channels are declared for.
  final String modVersion;

  /// Registers the framework smoke test block (`create:smoke_block`).
  final bool debugSmokeTest;

  /// How often dirty block entities and saved data are written, in ticks.
  final int saveIntervalTicks;

  /// Log every registry id after applying (verbose).
  final bool logRegistryIds;

  /// Module name to enabled; a module that is not listed is enabled.
  final Map<String, bool> modules;

  const CoreSettings({
    this.neoforge = true,
    this.modVersion = createModVersion,
    this.debugSmokeTest = false,
    this.saveIntervalTicks = 20,
    this.logRegistryIds = false,
    this.modules = const {},
  });
}
