import 'package:wasm_components/wasm_components.dart' show Result;

import 'src_exports.dart';

/// Describes a plugin to the server.
final class PluginInfo {
  final String name;
  final String version;
  final List<String> authors;
  final String description;

  /// Names of plugins that must be loaded before this one.
  final List<String> dependencies;

  /// Host features this plugin needs, see [Permissions].
  final List<String> permissions;

  const PluginInfo({
    required this.name,
    required this.version,
    this.authors = const [],
    this.description = '',
    this.dependencies = const [],
    this.permissions = const [],
  });
}

/// Base class for Pumpkin plugins.
///
/// Override [info] and whichever callbacks you need, then pass an instance to
/// [runPlugin] from `main`:
///
/// ```dart
/// void main() => runPlugin(MyPlugin());
///
/// final class MyPlugin extends Plugin {
///   @override
///   PluginInfo get info => const PluginInfo(name: 'my_plugin', version: '1.0.0');
///
///   @override
///   void onLoad(Context context) {
///     context.listen(Events.playerJoin, (server, event) {
///       logger.info('${event.player.getName()} joined');
///     });
///   }
/// }
/// ```
///
/// Throwing from a callback reports the failure to the server instead of
/// crashing the plugin.
abstract class Plugin {
  Plugin();

  PluginInfo get info;

  /// Called when the server loads the plugin. Register commands, event
  /// handlers and tasks here. Throwing aborts loading the plugin.
  void onLoad(Context context) {}

  /// Called when the server unloads the plugin.
  void onUnload(Context context) {}

  /// Called when another plugin sends this plugin a message. Return the reply,
  /// or throw to report an error to the sender.
  List<int> onMessage(String sender, List<int> message) {
    throw UnsupportedError('This plugin does not accept messages.');
  }
}

/// Registers [plugin] with the server. Call this from `main`.
void runPlugin(Plugin plugin) {
  definePlugin(exports: _Exports(plugin), metadata: _Metadata(plugin));
}

final class _Metadata implements Metadata {
  final Plugin _plugin;

  _Metadata(this._plugin);

  @override
  PluginMetadata getMetadata() {
    final info = _plugin.info;
    return PluginMetadata(
      name: info.name,
      version: info.version,
      authors: info.authors,
      description: info.description,
      dependencies: info.dependencies,
      permissions: info.permissions,
    );
  }
}

/// Implements the raw exports of the plugin world by calling into the Dart
/// closures registered through the wrapper API.
final class _Exports implements PluginExports {
  final Plugin _plugin;

  _Exports(this._plugin);

  @override
  void initPlugin() {}

  @override
  Result<void, String> onLoad(Context context) =>
      _guard('onLoad', () => _plugin.onLoad(context));

  @override
  Result<void, String> onUnload(Context context) =>
      _guard('onUnload', () => _plugin.onUnload(context));

  @override
  Event handleEvent(int eventId, Server server, Event event) {
    final handler = eventHandlers[eventId];
    if (handler == null) return event;
    try {
      return handler(server, event);
    } catch (e, s) {
      _logFailure('event handler', e, s);
      return event;
    }
  }

  @override
  Result<int, CommandError> handleCommand(
    int commandId,
    CommandSender sender,
    Server server,
    ConsumedArgs args,
  ) {
    final handler = commandHandlers[commandId];
    if (handler == null) {
      return Result.error(
        commandErrorFor(CommandException('Unknown command handler $commandId')),
      );
    }
    try {
      return Result.ok(handler(sender, server, args));
    } catch (e, s) {
      if (e is! CommandException) _logFailure('command', e, s);
      return Result.error(commandErrorFor(e));
    }
  }

  @override
  CommandSuggestions handleCommandSuggestion(
    int handlerId,
    CommandSender sender,
    Server server,
    SuggestionRequest request,
  ) {
    final none = CommandSuggestions(
      start: request.start,
      length: 0,
      values: const [],
    );
    final handler = suggestionHandlers[handlerId];
    if (handler == null) return none;
    try {
      return handler(sender, server, request);
    } catch (e, s) {
      _logFailure('suggestion handler', e, s);
      return none;
    }
  }

  @override
  void handleTask(int handlerId, Server server) {
    final task = taskHandlers[handlerId];
    if (task == null) return;
    try {
      task(server);
    } catch (e, s) {
      _logFailure('scheduled task', e, s);
    }
  }

  @override
  Result<List<int>, String> handleIpcMessage(
    String sender,
    List<int> message,
  ) {
    try {
      return Result.ok(_plugin.onMessage(sender, message));
    } catch (e) {
      return Result.error('$e');
    }
  }

  // Mob AI goals and chunk generators don't have a wrapper API yet.
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

  Result<void, String> _guard(String what, void Function() body) {
    try {
      body();
      return const Result.ok(null);
    } catch (e, s) {
      _logFailure(what, e, s);
      return Result.error('$e');
    }
  }

  void _logFailure(String what, Object error, StackTrace stack) {
    logger.error('Uncaught error in $what: $error\n$stack');
  }
}
