import 'dart:async';

import 'package:wasm_components/wasm_components.dart' show Result, printHandler;

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
  ///
  /// May be `async`, though the server doesn't wait for work that happens after
  /// the first `await`. [context] is only valid until the first `await`.
  FutureOr<void> onLoad(Context context) {}

  /// Called when the server unloads the plugin.
  FutureOr<void> onUnload(Context context) {}

  /// Called when another plugin sends this plugin a message. Return the reply,
  /// or throw to report an error to the sender.
  List<int> onMessage(String sender, List<int> message) {
    throw UnsupportedError('This plugin does not accept messages.');
  }
}

/// Registers [plugin] with the server. Call this from `main`.
void runPlugin(Plugin plugin) {
  // `print` writes to the server log.
  printHandler = logger.info;
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
      final outcome = runCallback<Event>(
        'event handler',
        () => handler(server, event),
      );
      return outcome.completed ? outcome.value! : event;
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
      final outcome = runCallback<int>(
        'command',
        () => handler(sender, server, args),
      );
      // The server can't wait for a command that is still running.
      return Result.ok(outcome.completed ? outcome.value! : 1);
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
      final outcome = runCallback<CommandSuggestions>(
        'suggestion handler',
        () => handler(sender, server, request),
      );
      return outcome.completed ? outcome.value! : none;
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
      runTask(task, server);
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
      final outcome = runCallback<List<int>>(
        'onMessage',
        () => _plugin.onMessage(sender, message),
      );
      return Result.ok(outcome.value!);
    } catch (e) {
      return Result.error('$e');
    }
  }

  @override
  bool handleAiGoalCanStart(int goalId, Server server, Entity entity) =>
      _goal(goalId, false, (g) => g.canStart(server, entity));

  @override
  bool handleAiGoalShouldContinue(int goalId, Server server, Entity entity) =>
      _goal(goalId, false, (g) => g.shouldContinue(server, entity));

  @override
  void handleAiGoalStart(int goalId, Server server, Entity entity) =>
      _goal(goalId, null, (g) => g.start(server, entity));

  @override
  void handleAiGoalTick(int goalId, Server server, Entity entity) =>
      _goal(goalId, null, (g) => g.tick(server, entity));

  @override
  void handleAiGoalStop(int goalId, Server server, Entity entity) =>
      _goal(goalId, null, (g) => g.stop(server, entity));

  R _goal<R>(int goalId, R fallback, R Function(AiGoal goal) call) {
    final goal = aiGoals[goalId];
    if (goal == null) return fallback;
    try {
      return runCallback<R>('AI goal', () => call(goal)).value ?? fallback;
    } catch (e, s) {
      _logFailure('AI goal', e, s);
      return fallback;
    }
  }

  @override
  void handleGeneratePhase(
    int generatorId,
    GenerationPhase phase,
    ChunkBuffer chunk,
  ) {
    final generator = chunkGenerators[generatorId];
    if (generator == null) return;
    try {
      runCallback<void>('chunk generator', () {
        switch (phase) {
          case GenerationPhase.biomes:
            generator.generateBiomes(chunk);
          case GenerationPhase.noise:
            generator.generateNoise(chunk);
          case GenerationPhase.surface:
            generator.generateSurface(chunk);
          case GenerationPhase.features:
            generator.generateFeatures(chunk);
        }
      });
    } catch (e, s) {
      _logFailure('chunk generator', e, s);
    }
  }

  Result<void, String> _guard(String what, FutureOr<void> Function() body) {
    try {
      runCallback<void>(what, body);
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
