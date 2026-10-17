// Makes `async`/`await`, `Future.delayed` and `Timer` work in plugins.
//
// Calls from the host run as tasks of the async component model (see
// `package:wasm_components`): a callback can await host calls, and the host
// keeps the task alive until they have finished. Standalone dart2wasm has no
// event loop of its own, so scheduling anything outside of a task throws.
// Every callback from the host runs in a zone (below) that:
//
//  * lets the task run microtasks, so `await` on completed futures just works,
//  * implements timers on top of the server's tick scheduler (20 ticks per
//    second, so timers have a resolution of 50ms),
//  * keeps the resources received by the callback alive for as long as the
//    asynchronous work it started is running.
//
// The host waits for a callback until it has nothing left to await but a timer
// or a future that something else completes. It is then given a fallback result,
// and the work continues in a later tick, from the `handle-task` callback of the
// scheduler.
import 'dart:async';
import 'dart:collection';

import 'bindings.g.dart' as wit;
import 'bindings.g.dart' show Server;
import 'package:wasm_components/wasm_components.dart'
    show AsyncTask, ResourceScope, drainMicrotasks, onDrain;

import 'logger.dart';
import 'registry.dart';

/// Milliseconds in one server tick.
const millisecondsPerTick = 50;

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

/// Zero-delay timers, which run right after the microtasks.
final Queue<_Entry> _immediate = Queue();

final _activityKey = Object();

final _zoneSpecification = ZoneSpecification(
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

/// Runs one zero-delay timer. The task runtime calls this whenever the
/// microtasks are done.
bool _runImmediate() {
  if (_immediate.isEmpty) return false;
  final entry = _immediate.removeFirst();
  entry.zone.runGuarded(entry.callback);
  return true;
}

var _hooked = false;

/// Connects the timers to the task runtime. Done once, by the first callback.
void _hook() {
  if (_hooked) return;
  _hooked = true;
  onDrain = _runImmediate;
}

/// Runs [body] in a fresh plugin zone, as a callback from the host, and
/// completes with its result.
///
/// If the body still waits for something that is not a host call (a timer, or
/// a future another callback completes) once everything else is done, the
/// result is [fallback] instead, so the host doesn't wait for it. The body
/// carries on in a later tick, and its failures are logged.
///
/// Failures of the body complete the future with an error.
Future<T> runCallback<T>(
  String what,
  FutureOr<T> Function() body, {
  required T Function() fallback,
}) {
  _hook();
  final activity = _Activity(ResourceScope.current);
  final zone = Zone.current.fork(
    specification: _zoneSpecification,
    zoneValues: {_activityKey: activity},
  );

  final FutureOr<T> result;
  try {
    result = zone.run(body);
  } catch (e, s) {
    activity.bodyDone = true;
    drainMicrotasks();
    activity.maybeFinish();
    return Future<T>.error(e, s);
  }

  if (result is! Future<T>) {
    activity.bodyDone = true;
    drainMicrotasks();
    if (activity.pendingTimers > 0) activity.hold();
    return Future<T>.value(result);
  }
  final Future<T> future = result;

  final completer = Completer<T>();
  zone.run(() {
    future.then<void>(
      (T value) {
        activity.bodyDone = true;
        if (!completer.isCompleted) completer.complete(value);
        activity.maybeFinish();
      },
      onError: (Object error, StackTrace stack) {
        activity.bodyDone = true;
        if (completer.isCompleted) {
          logger.error('Uncaught error in $what: $error\n$stack');
        } else {
          completer.completeError(error, stack);
        }
        activity.maybeFinish();
      },
    );
  });

  AsyncTask.current?.onIdle(() {
    if (completer.isCompleted) return false;
    // Keep the resources alive for the work that carries on.
    activity.hold();
    completer.complete(fallback());
    return true;
  });
  return completer.future;
}

/// Runs a scheduled task and everything it unblocked.
Future<void> runTask(TaskHandler task, Server server) async {
  _hook();
  task(server);
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
