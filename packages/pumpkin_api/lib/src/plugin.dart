import 'package:wasm_components/wasm_components.dart' show Result;

import 'bindings.g.dart';

/// Base class for Pumpkin plugins.
///
/// The WIT `plugin` world requires every plugin component to export all of the
/// host callbacks below, so [PluginExports] has to be fully implemented. This
/// class provides a default for each of them, so plugins only override what
/// they actually use:
///
/// ```dart
/// final class MyPlugin extends Plugin {
///   @override
///   PluginMetadata get metadata => const PluginMetadata(...);
///
///   @override
///   Result<void, String> onLoad(Context context) { ... }
/// }
///
/// void main() => runPlugin(MyPlugin());
/// ```
abstract base class Plugin implements PluginExports {
  Plugin();

  /// Describes this plugin to the server.
  PluginMetadata get metadata;

  @override
  void initPlugin() {}

  @override
  Result<void, String> onLoad(Context context) => const Result.ok(null);

  @override
  Result<void, String> onUnload(Context context) => const Result.ok(null);

  @override
  Event handleEvent(int eventId, Server server, Event event) => event;

  @override
  Result<int, CommandError> handleCommand(
    int commandId,
    CommandSender sender,
    Server server,
    ConsumedArgs args,
  ) => const Result.error(CommandErrorInvalidRequirement());

  @override
  CommandSuggestions handleCommandSuggestion(
    int handlerId,
    CommandSender sender,
    Server server,
    SuggestionRequest request,
  ) => CommandSuggestions(start: request.start, length: 0, values: const []);

  @override
  void handleTask(int handlerId, Server server) {}

  @override
  Result<List<int>, String> handleIpcMessage(
    String sender,
    List<int> message,
  ) => const Result.error('This plugin does not handle IPC messages');

  @override
  bool handleAiGoalCanStart(int goalId, Server server, Entity entity) => false;

  @override
  bool handleAiGoalShouldContinue(int goalId, Server server, Entity entity) =>
      false;

  @override
  void handleAiGoalStart(int goalId, Server server, Entity entity) {}

  @override
  void handleAiGoalTick(int goalId, Server server, Entity entity) {}

  @override
  void handleAiGoalStop(int goalId, Server server, Entity entity) {}

  @override
  void handleGeneratePhase(
    int generatorId,
    GenerationPhase phase,
    ChunkBuffer chunk,
  ) {}
}

/// Registers [plugin] with the host. Call this from `main`.
void runPlugin(Plugin plugin) {
  definePlugin(exports: plugin, metadata: _PluginMetadataProvider(plugin));
}

final class _PluginMetadataProvider implements Metadata {
  final Plugin _plugin;

  _PluginMetadataProvider(this._plugin);

  @override
  PluginMetadata getMetadata() => _plugin.metadata;
}
