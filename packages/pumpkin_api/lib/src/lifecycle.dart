import 'dart:async';

import 'bindings.g.dart' show Context;
import 'infra_core.dart';
import 'logger.dart';

export 'infra_core.dart' show Disposable, DisposableBag, Subscription;

final UnloadHooks _unloadHooks = UnloadHooks();
final Logger _log = Logger('lifecycle');

/// Registering cleanup that runs when the plugin unloads.
extension LifecycleApi on Context {
  /// Runs [hook] when the plugin unloads. Hooks run newest first, each guarded
  /// (a failure is logged and the rest still run); `async` hooks are awaited
  /// in turn. Use the returned [Subscription] to remove a hook early.
  ///
  /// ```dart
  /// final timer = Timer.periodic(Duration(seconds: 30), (_) => save());
  /// context.onUnload(timer.cancel);
  /// context.onUnload(() async => await flush());
  /// ```
  Subscription onUnload(FutureOr<void> Function() hook) =>
      _unloadHooks.add(hook);
}

/// Same as `Context.onUnload`, usable where no context is at hand.
Subscription registerUnloadHook(FutureOr<void> Function() hook) =>
    _unloadHooks.add(hook);

/// Runs and clears the registered unload hooks. The plugin dispatcher calls
/// this from its `onUnload` export, after (or before) `Plugin.onUnload`.
/// Returns a future only if a hook was asynchronous; return it from the
/// export so the host callback keeps waiting.
FutureOr<void> runUnloadHooks() => _unloadHooks.run(_log.error);

/// Adds the bag's disposal to the plugin's unload hooks, so everything in it
/// is released when the plugin unloads.
extension DisposableBagUnload on DisposableBag {
  /// Disposes this bag on plugin unload.
  Subscription disposeOnUnload() => _unloadHooks.add(dispose);
}
