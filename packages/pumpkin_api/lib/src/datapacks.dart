import 'package:wasm_components/wasm_components.dart' show ErrorResult, OkResult, Result;

import 'bindings.g.dart';

/// Thrown when the server refuses a datapack operation.
final class DatapackException implements Exception {
  /// The reason given by the server.
  final String message;

  DatapackException(this.message);

  @override
  String toString() => 'DatapackException: $message';
}

T _unwrap<T>(Result<T, String> result) => switch (result) {
  OkResult(:final value) => value,
  ErrorResult(:final value) => throw DatapackException(value),
};

/// Conveniences for [Server].
extension ServerDatapacks on Server {
  /// The manager for this server's datapacks.
  DatapackManager get datapacks => getDatapackManager();
}

/// Conveniences for [DatapackManager]. Operations that can fail throw a
/// [DatapackException] instead of returning a `Result`.
extension DatapackManagerHelpers on DatapackManager {
  /// All known datapacks, enabled or not.
  List<DatapackInfo> get all => listAllPacks();

  /// The enabled datapacks.
  List<DatapackInfo> get enabled => listEnabledPacks();

  /// The datapacks that are available but disabled.
  List<DatapackInfo> get available => listAvailablePacks();

  /// The datapack called [name] (name or id), or `null`.
  DatapackInfo? operator [](String name) {
    final pack = getPack(name: name);
    return pack.hasValue ? pack.requireValue() : null;
  }

  /// Whether the datapack [name] is enabled.
  bool isPackEnabled(String name) => isEnabled(name: name);

  /// Enables the datapack [name] at [position], last by default. Throws a
  /// [DatapackException] if that fails. Call [reloadPacks] to apply it.
  void enable(
    String name, {
    EnablePosition position = const EnablePositionLast(),
  }) => _unwrap(enablePack(name: name, position: position));

  /// Disables the datapack [name]. Throws a [DatapackException] if that fails.
  void disable(String name) => _unwrap(disablePack(name: name));

  /// Reloads the enabled datapacks. Throws a [DatapackException] if that
  /// fails.
  void reloadPacks() => _unwrap(reload());

  /// Runs a datapack function (`namespace:fn`) or function tag
  /// (`#namespace:tag`) and returns how many commands ran. Throws a
  /// [DatapackException] if that fails.
  int runFunction(String name) =>
      _unwrap(executeFunction(name: name));
}
