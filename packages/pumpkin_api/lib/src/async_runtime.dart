// Makes `async`/`await`, `Future.delayed` and `Timer` work in plugins.
//
// Standalone dart2wasm has no event loop, so scheduling anything outside of a
// component async task throws. Instead, every callback from the host runs in a
// zone (below) that:
//
//  * collects microtasks, and runs them before the host call returns, so
//    `await` on completed futures just works,
//  * implements timers on top of the server's tick scheduler (20 ticks per
//    second, so timers have a resolution of 50ms),
//  * keeps the resources received by the callback alive for as long as the
//    asynchronous work it started is running.
//
// A future that is waiting on a timer continues in a later tick, from the
// `handle-task` callback of the scheduler.
import 'dart:async';
import 'dart:collection';

import 'bindings.g.dart' as wit;
import 'bindings.g.dart' show Server;
import 'package:wasm_components/wasm_components.dart' show ResourceScope;

import 'logger.dart';
import 'registry.dart';

/// Milliseconds in one server tick.
const millisecondsPerTick = 50;

/// What a plugin callback did when it returned to the host.
final class Outcome<T> {
  /// Whether [value] is set. If not, the callback is still waiting for a timer
  /// or another future, and will continue in a later tick.
  final bool completed;
  final T? value;

  const Outcome.completed(this.value) : completed = true;
  const Outcome.pending() : value = null, completed = false;
}

typedef TaskHandler = void Function(Server server);

final taskHandlers = HandlerRegistry<TaskHandler>();

/// Work that belongs together: one host callback and everything it started.
final class _Activity {
  final ResourceScope? scope;
  int pendingTimers = 0;
  bool bodyDone = false;
  bool _held = false;

  _Activity(this.scope);

  void hold() {
    if (_held) return;
    _held = true;
    scope?.hold();
  }

  void maybeFinish() {
    if (_held && bodyDone && pendingTimers == 0) {
      _held = false;
      scope?.release();
    }
  }
}

final class _Entry {
  final Zone zone;
  final void Function() callback;

  _Entry(this.zone, this.callback);
}

final Queue<_Entry> _microtasks = Queue();
final Queue<_Entry> _immediate = Queue();

final _activityKey = Object();

final _zoneSpecification = ZoneSpecification(
  scheduleMicrotask: (self, parent, zone, f) {
    _microtasks.add(_Entry(zone, f));
  },
  createTimer: (self, parent, zone, duration, f) {
    return _PluginTimer(
      zone[_activityKey] as _Activity?,
      duration,
      null,
      (_) => zone.runGuarded(f),
    );
  },
  createPeriodicTimer: (self, parent, zone, period, f) {
    late final _PluginTimer timer;
    timer = _PluginTimer(
      zone[_activityKey] as _Activity?,
      period,
      period,
      (_) => zone.runUnaryGuarded(f, timer),
    );
    return timer;
  },
  handleUncaughtError: (self, parent, zone, error, stackTrace) {
    logger.error('Uncaught error in plugin: $error\n$stackTrace');
  },
  run: <R>(self, parent, zone, f) {
    final scope = (zone[_activityKey] as _Activity?)?.scope;
    return scope == null ? parent.run(zone, f) : scope.run(() => parent.run(zone, f));
  },
  runUnary: <R, T>(self, parent, zone, f, arg) {
    final scope = (zone[_activityKey] as _Activity?)?.scope;
    return scope == null
        ? parent.runUnary(zone, f, arg)
        : scope.run(() => parent.runUnary(zone, f, arg));
  },
  runBinary: <R, T1, T2>(self, parent, zone, f, a, b) {
    final scope = (zone[_activityKey] as _Activity?)?.scope;
    return scope == null
        ? parent.runBinary(zone, f, a, b)
        : scope.run(() => parent.runBinary(zone, f, a, b));
  },
);

/// Runs microtasks (and zero-delay timers) until nothing is left to do.
void drainEventLoop() {
  while (true) {
    final _Entry entry;
    if (_microtasks.isNotEmpty) {
      entry = _microtasks.removeFirst();
    } else if (_immediate.isNotEmpty) {
      entry = _immediate.removeFirst();
    } else {
      return;
    }
    entry.zone.runGuarded(entry.callback);
  }
}

/// Runs [body] in a fresh plugin zone, as a callback from the host.
///
/// Errors thrown synchronously are rethrown. If the body returns a future that
/// completes later, its error is logged instead.
Outcome<T> runCallback<T>(String what, FutureOr<T> Function() body) {
  final activity = _Activity(ResourceScope.current);
  final zone = Zone.root.fork(
    specification: _zoneSpecification,
    zoneValues: {_activityKey: activity},
  );

  final FutureOr<T> result;
  try {
    result = zone.run(body);
  } catch (_) {
    activity.bodyDone = true;
    drainEventLoop();
    activity.maybeFinish();
    rethrow;
  }

  if (result is! Future<T>) {
    activity.bodyDone = true;
    drainEventLoop();
    if (activity.pendingTimers > 0) activity.hold();
    return Outcome.completed(result as T);
  }
  final Future<T> future = result;

  var done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  zone.run(() {
    future.then<void>(
      (T v) {
        done = true;
        value = v;
        activity.bodyDone = true;
        activity.maybeFinish();
      },
      onError: (Object e, StackTrace s) {
        done = true;
        error = e;
        stack = s;
        activity.bodyDone = true;
        activity.maybeFinish();
      },
    );
  });
  drainEventLoop();

  if (done) {
    if (activity.pendingTimers > 0) activity.hold();
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return Outcome.completed(value);
  }

  // Still waiting: keep the resources alive, and report failures when they
  // happen since nobody is waiting for the result anymore.
  activity.hold();
  future.then<void>((_) {}, onError: (Object e, StackTrace s) {
    logger.error('Uncaught error in $what: $e\n$s');
  });
  return Outcome.pending();
}

/// Runs a scheduled task and everything it unblocked.
void runTask(TaskHandler task, Server server) {
  try {
    task(server);
  } finally {
    drainEventLoop();
  }
}

/// A timer backed by the server's tick scheduler.
final class _PluginTimer implements Timer {
  final _Activity? _activity;
  final void Function(Server? server) _callback;
  final bool _periodic;

  int _tick = 0;
  bool _active = true;
  int? _handlerId;
  int? _taskId;

  _PluginTimer(
    this._activity,
    Duration delay,
    Duration? period,
    this._callback,
  ) : _periodic = period != null {
    _activity?.pendingTimers++;

    final delayTicks = _toTicks(delay);
    if (delayTicks == 0 && period == null) {
      // Like the event loop, run zero-delay timers right after microtasks.
      _immediate.add(_Entry(Zone.current, _fireImmediately));
      return;
    }

    _handlerId = taskHandlers.add(_fire);
    if (period == null) {
      _taskId = wit.scheduler.scheduleDelayedTask(
        handlerId: _handlerId!,
        delayTicks: delayTicks,
      );
    } else {
      _taskId = wit.scheduler.scheduleRepeatingTask(
        handlerId: _handlerId!,
        delayTicks: delayTicks,
        periodTicks: _toTicks(period).clamp(1, 1 << 30),
      );
    }
  }

  static int _toTicks(Duration duration) {
    if (duration <= Duration.zero) return 0;
    final ms = duration.inMilliseconds;
    return (ms + millisecondsPerTick - 1) ~/ millisecondsPerTick;
  }

  @override
  int get tick => _tick;

  @override
  bool get isActive => _active;

  void _fireImmediately() {
    if (!_active) return;
    _finishIfOneShot();
    _callback(null);
  }

  void _fire(Server server) {
    if (!_active) return;
    _tick++;
    _finishIfOneShot();
    _callback(server);
    _activity?.maybeFinish();
  }

  void _finishIfOneShot() {
    if (_periodic) return;
    _active = false;
    _release();
  }

  void _release() {
    final handlerId = _handlerId;
    if (handlerId != null) taskHandlers.remove(handlerId);
    _activity?.pendingTimers--;
  }

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    final taskId = _taskId;
    if (taskId != null) wit.scheduler.cancelTask(taskId: taskId);
    _release();
    _activity?.maybeFinish();
  }
}

/// Schedules [callback] to run after [delayTicks] ticks, and then every
/// [periodTicks] ticks if given. Used by `runLater`/`runRepeating`.
Timer scheduleTicks(
  int delayTicks,
  int? periodTicks,
  void Function(Server server) callback,
) {
  void run(Server? server) => callback(server!);
  final activity = _currentActivity();
  final millis = delayTicks * millisecondsPerTick;
  return _PluginTimer(
    activity,
    Duration(milliseconds: millis < 1 ? 1 : millis),
    periodTicks == null
        ? null
        : Duration(milliseconds: periodTicks * millisecondsPerTick),
    run,
  );
}

_Activity? _currentActivity() => Zone.current[_activityKey] as _Activity?;
