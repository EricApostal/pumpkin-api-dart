// The `SimConfigService` of the Java mod, with the loader abstraction removed.
//
// Java loads the service through `ServiceLoader` and has a NeoForge and a
// Fabric implementation. A Pumpkin plugin has exactly one implementation, so
// this is a plain holder: the plugin sets [SimConfigService.instance] once,
// when it reads its config file.
//
// Pure: no host imports.
import '../config/sim_config.dart';

/// Holds the loaded config.
final class SimConfigService {
  /// The installed service. Starts with the defaults so anything that reads the
  /// config before the plugin loaded still sees sane values.
  static SimConfigService instance = SimConfigService(SimConfig.defaults);

  SimConfigService(this._config);

  SimConfig _config;

  /// The whole config.
  SimConfig get config => _config;

  /// `server()`.
  SimServerConfig get server => _config.server;

  /// `serverLoaded()`: the server config is always available in a plugin.
  bool get serverLoaded => true;

  /// `clientLoaded()`: a server plugin has no client config.
  bool get clientLoaded => false;

  /// Replaces the config (the plugin calls this after reading its file).
  void load(SimConfig config) => _config = config;

  /// Replaces the config from a parsed JSON document.
  void loadFromMap(Map<String, Object?> map) => _config = SimConfig.fromMap(map);

  /// The installed server config.
  static SimServerConfig get serverConfig => instance.server;
}
