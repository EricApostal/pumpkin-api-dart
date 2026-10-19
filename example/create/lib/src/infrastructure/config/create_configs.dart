// `AllConfigs` (pure): the server and common config of Create with the manifest defaults.
//
//   final configs = ctx.services.require<CreateConfigs>();
//   configs.server.kinetics.maxBeltLength.value          // AllConfigs.server().kinetics.maxBeltLength.get()
//   configs.stress.impact('mechanical_press')            // BlockStressValues.getImpact(block)
import '../../manifest/manifest.dart';
import 'config_tree.dart';
import 'config_values.dart';
import 'create_configs.g.dart';

export 'config_tree.dart';
export 'config_values.dart';
export 'create_configs.g.dart';

/// `BlockStressValues`: stress numbers per block path (`mechanical_press`), from the config.
final class BlockStressValues {
  final CStress _stress;

  BlockStressValues(this._stress);

  /// `BlockStressValues.getImpact(block)`: the base impact at 1 RPM, 0 when the block has none.
  double impact(String blockPath) => _stress.impacts[_path(blockPath)]?.value ?? 0;

  /// `BlockStressValues.getCapacity(block)`: the base capacity at 1 RPM, 0 when the block has none.
  double capacity(String blockPath) => _stress.capacities[_path(blockPath)]?.value ?? 0;

  /// Whether the block has a configured impact.
  bool hasImpact(String blockPath) => _stress.impacts.containsKey(_path(blockPath));

  /// Whether the block has a configured capacity.
  bool hasCapacity(String blockPath) => _stress.capacities.containsKey(_path(blockPath));

  /// `BlockStressValues.RPM`: the speed a generator advertises (tooltips), `null` for none.
  ({int rpm, bool mayGenerateLess})? generatedRpm(String blockPath) {
    final e = _rpm[_path(blockPath)];
    return e;
  }

  static String _path(String key) => key.startsWith('create:') ? key.substring(7) : key;

  static final Map<String, ({int rpm, bool mayGenerateLess})> _rpm = {
    for (final s in stressDefaults)
      if (s.generatedRpm != null) s.block: (rpm: s.generatedRpm!, mayGenerateLess: s.mayGenerateLess ?? false),
  };
}

/// All of Create's configs.
final class CreateConfigs {
  /// File name of the synced server config as NeoForge names it.
  static const String serverFile = 'create-server.toml';
  static const String commonFile = 'create-common.toml';

  /// The mod id of the config files in the NeoForge declaration.
  static const String modId = 'create';

  final ConfigTree serverTree = ConfigTree(serverFile);
  final ConfigTree commonTree = ConfigTree(commonFile);
  late final CServer server = CServer(serverTree);
  late final CCommon common = CCommon(commonTree);

  CreateConfigs() {
    // Touch the lazy fields so every value is registered.
    server;
    common;
  }

  late final BlockStressValues stress = BlockStressValues(server.kinetics.stressValues);

  /// All values of both files by dotted path prefixed with the file kind: `server.kinetics.maxBeltLength`.
  ConfigValue<Object>? find(String qualifiedPath) {
    if (qualifiedPath.startsWith('server.')) return serverTree[qualifiedPath.substring(7)];
    if (qualifiedPath.startsWith('common.')) return commonTree[qualifiedPath.substring(7)];
    return serverTree[qualifiedPath] ?? commonTree[qualifiedPath];
  }

  /// Applies the nested JSON of the plugin's config section (`{"server": {...}, "common": {...}}`).
  /// Problems (unknown keys, invalid values) are added to [warnings].
  void load(Map<String, dynamic> json, {List<String>? warnings}) {
    final s = json['server'];
    if (s is Map<String, dynamic>) serverTree.load(s, warnings: warnings);
    final c = json['common'];
    if (c is Map<String, dynamic>) commonTree.load(c, warnings: warnings);
  }

  /// Everything as nested JSON, for the plugin's config section.
  Map<String, dynamic> toJson() => {'server': serverTree.toJson(), 'common': commonTree.toJson()};

  /// The text of `create-server.toml` with the current values.
  String serverToml() => serverTree.toToml();

  /// The text of `create-common.toml`.
  String commonToml() => commonTree.toToml();
}
