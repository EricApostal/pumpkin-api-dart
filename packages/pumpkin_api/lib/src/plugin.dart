import 'command_builder.dart' show commandNamespace;
import 'dart:async';

import 'package:wasm_components/wasm_components.dart'
    show Resource, ResourceKeep, ResourceScope, Result, printHandler;

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

  Context? _context;

  /// The context the server gave to [onLoad], valid for as long as the plugin
  /// is loaded. Unlike the `context` parameter of [onLoad] it can be used from
  /// later callbacks, to register events or commands at runtime and to wait for
  /// events with `context.next(...)`.
  Context get context =>
      _context ?? (throw StateError('The plugin has not been loaded yet.'));

  /// Called when the server loads the plugin. Register commands, event
  /// handlers and tasks here. Throwing aborts loading the plugin.
  ///
  /// May be `async`. The server waits for the host calls it awaits, but not for
  /// timers or futures that something else completes. [context] is only valid
  /// until the callback returns, use [Plugin.context] after that.
  FutureOr<void> onLoad(Context context) {}

  /// Called when the server unloads the plugin.
  FutureOr<void> onUnload(Context context) {}

  /// Called when another plugin sends this plugin a message. Return the reply,
  /// or throw to report an error to the sender.
  ///
  /// By default, messages go to the handlers registered with `IpcChannel.handle`.
  List<int> onMessage(String sender, List<int> message) =>
      handleIpc(sender, message);
}

/// Registers [plugin] with the server. Call this from `main`.
void runPlugin(Plugin plugin) {
  // `print` writes to the server log.
  printHandler = logger.info;
  commandNamespace = plugin.info.name;
  // One plugin per component: name it in lifetime errors, so a handle used
  // after the callback that received it returned says where it came from.
  Resource.pluginName = plugin.info.name;
  definePlugin(
    exports: _Exports(plugin),
    metadata: _Metadata(plugin),
    gametestCallbacks: _GametestCallbacks(),
  );
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

/// Plugins don't take part in the server's gametests, so the host never calls
/// these.
final class _GametestCallbacks implements GametestCallbacks {
  @override
  void invokeVoid({required VoidCallbackId callback}) {}

  @override
  void invokeTest({required TestCallbackId callback, required Test test}) {}

  @override
  Future<void> invokeAsyncTest({
    required AsyncTestCallbackId callback,
    required Test test,
  }) async {}

  @override
  bool invokeBlockPredicate({
    required BlockPredicateCallbackId callback,
    required BlockState permutation,
  }) => false;

  @override
  bool invokeEntityPredicate({
    required EntityPredicateCallbackId callback,
    required Entity entity,
  }) => false;
}

/// Implements the raw exports of the plugin world by calling into the Dart
/// closures registered through the wrapper API.
final class _Exports implements PluginExports {
  final Plugin _plugin;

  _Exports(this._plugin);

  @override
  void initPlugin() {}

  @override
  Future<Result<void, String>> onLoad(Context context) => _guard('onLoad', () {
    // The load context is owned: keep it for `Plugin.context`.
    _plugin._context = context.keep();
    return _plugin.onLoad(context);
  });

  @override
  Future<Result<void, String>> onUnload(Context context) =>
      _guard('onUnload', () async {
        try {
          await _plugin.onUnload(context);
          await runUnloadHooks();
        } finally {
          final loadContext = _plugin._context;
          _plugin._context = null;
          loadContext?.dispose();
        }
      });

  @override
  Future<Event> handleEvent(int eventId, Server server, Event event) async {
    // Names the event in lifetime errors: a resource received here and used
    // after this dispatch returned reports this event and the one that used it.
    // The value is the constant from the label table, so nothing is allocated
    // per dispatch.
    final label = eventHandlerLabels[eventId];
    final previous = Resource.receivingDuring;
    Resource.receivingDuring = label;
    if (label != null) ResourceScope.labelCurrent(label);
    try {
      return await _handleEvent(eventId, server, event);
    } finally {
      Resource.receivingDuring = previous;
    }
  }

  Future<Event> _handleEvent(int eventId, Server server, Event event) async {
    final group = eventGroups[eventId];
    if (group != null) {
      // One host handler for the whole group: run every member that wants the event, in
      // registration order, each exactly as the separate host handler it replaces would have run
      // it - its own callback scope, its own fallback, its own error handling. The list is walked
      // by index and never shrinks (a cancel only marks a member inactive), so the dispatch
      // copies nothing and a member a handler cancels mid-event is silenced like the registry
      // lookup that used to be its own dispatch.
      final count = group.length;
      var current = event;
      for (var i = 0; i < count; i++) {
        final member = group[i];
        if (!member.active || !member.wants(current)) continue;
        current = await _invokeEventHandler(eventId, member.handler, server, current);
      }
      return current;
    }
    return _invokeEventHandler(eventId, eventHandlers[eventId], server, event);
  }

  /// Runs one handler of [eventId] with the guest-side bookkeeping a host dispatch used to get:
  /// its own callback scope, a null-checked timing sink, and a failure that is logged without
  /// ending the dispatch.
  Future<Event> _invokeEventHandler(
    int eventId,
    FutureOr<Event> Function(Server server, Event event)? handler,
    Server server,
    Event event,
  ) async {
    if (handler == null) return event;
    Future<Event> invoke() async {
      try {
        return await runCallback<Event>(
          'event handler',
          () => handler(server, event),
          fallback: () => event,
        );
      } catch (e, s) {
        _logFailure('event handler', e, s);
        return event;
      }
    }

    // A plugin that wants to attribute its per-tick cost installs `eventTimingSink` (Create's
    // `Perf` does, when its `perf` file is present): the host knows how long it waited for this
    // callback, only the guest knows how much of that was the handler. Without a sink this is one
    // null check per dispatch.
    final sink = eventTimingSink;
    if (sink == null) return invoke();
    final watch = Stopwatch()..start();
    try {
      return await invoke();
    } finally {
      sink(eventHandlerLabels[eventId] ?? 'unknown', watch.elapsedMicroseconds);
    }
  }

  @override
  Future<Result<int, CommandError>> handleCommand(
    int commandId,
    CommandSender sender,
    Server server,
    ConsumedArgs args,
  ) async {
    final handler = commandHandlers[commandId];
    if (handler == null) {
      return Result.error(
        commandErrorFor(CommandException('Unknown command handler $commandId')),
      );
    }
    try {
      // The server can't wait for a command that waits for a timer, it gets 1.
      return Result.ok(
        await runCallback<int>(
          'command',
          () => handler(sender, server, args),
          fallback: () => 1,
        ),
      );
    } catch (e, s) {
      if (e is! CommandException) _logFailure('command', e, s);
      return Result.error(commandErrorFor(e));
    }
  }

  @override
  Future<CommandSuggestions> handleCommandSuggestion(
    int handlerId,
    CommandSender sender,
    Server server,
    SuggestionRequest request,
  ) async {
    CommandSuggestions none() =>
        CommandSuggestions(start: request.start, length: 0, values: const []);
    final handler = suggestionHandlers[handlerId];
    if (handler == null) return none();
    try {
      return await runCallback<CommandSuggestions>(
        'suggestion handler',
        () => handler(sender, server, request),
        fallback: none,
      );
    } catch (e, s) {
      _logFailure('suggestion handler', e, s);
      return none();
    }
  }

  @override
  Future<void> handleTask(int handlerId, Server server) async {
    final task = taskHandlers[handlerId];
    if (task == null) return;
    try {
      await runTask(task, server);
    } catch (e, s) {
      _logFailure('scheduled task', e, s);
    }
  }

  @override
  Future<Result<List<int>, String>> handleIpcMessage(
    String sender,
    List<int> message,
  ) async {
    try {
      return Result.ok(
        await runCallback<List<int>>(
          'onMessage',
          () => _plugin.onMessage(sender, message),
          fallback: () => const <int>[],
        ),
      );
    } catch (e) {
      return Result.error('$e');
    }
  }

  @override
  Future<bool> handleAiGoalCanStart(int goalId, Server server, Entity entity) =>
      _goal(goalId, false, (g) => g.canStart(server, entity));

  @override
  Future<bool> handleAiGoalShouldContinue(
    int goalId,
    Server server,
    Entity entity,
  ) => _goal(goalId, false, (g) => g.shouldContinue(server, entity));

  @override
  Future<void> handleAiGoalStart(int goalId, Server server, Entity entity) =>
      _goal<void>(goalId, null, (g) => g.start(server, entity));

  @override
  Future<void> handleAiGoalTick(int goalId, Server server, Entity entity) =>
      _goal<void>(goalId, null, (g) => g.tick(server, entity));

  @override
  Future<void> handleAiGoalStop(int goalId, Server server, Entity entity) =>
      _goal<void>(goalId, null, (g) => g.stop(server, entity));

  Future<R> _goal<R>(
    int goalId,
    R fallback,
    FutureOr<R> Function(AiGoal goal) call,
  ) async {
    final goal = aiGoals[goalId];
    if (goal == null) return fallback;
    try {
      return await runCallback<R>(
        'AI goal',
        () => call(goal),
        fallback: () => fallback,
      );
    } catch (e, s) {
      _logFailure('AI goal', e, s);
      return fallback;
    }
  }

  @override
  Future<void> handleGeneratePhase(
    int generatorId,
    GenerationPhase phase,
    ChunkBuffer chunk,
  ) async {
    final generator = chunkGenerators[generatorId];
    if (generator == null) return;
    try {
      await runCallback<void>('chunk generator', () {
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
      }, fallback: () {});
    } catch (e, s) {
      _logFailure('chunk generator', e, s);
    }
  }

  Future<Result<void, String>> _guard(
    String what,
    FutureOr<void> Function() body,
  ) async {
    try {
      await runCallback<void>(what, body, fallback: () {});
      return const Result.ok(null);
    } catch (e, s) {
      _logFailure(what, e, s);
      return Result.error('$e');
    }
  }

  void _logFailure(String what, Object error, StackTrace stack) {
    logger.error('Uncaught error in $what of ${_plugin.info.name}: $error\n$stack');
  }
}
