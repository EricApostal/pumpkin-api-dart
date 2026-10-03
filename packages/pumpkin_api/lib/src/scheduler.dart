import 'dart:async';

import 'async_runtime.dart';
import 'bindings.g.dart' show Context, Server;

/// Code that runs on the server's tick loop.
typedef TickCallback = void Function(Server server);

/// A task scheduled with `runLater` or `runRepeating`.
final class ScheduledTask {
  final Timer _timer;

  ScheduledTask._(this._timer);

  bool get isActive => _timer.isActive;

  /// Stops the task. Does nothing if it already ran or was cancelled.
  void cancel() => _timer.cancel();
}

/// Durations in server ticks. The server runs 20 ticks per second.
extension Ticks on int {
  /// This many ticks as a [Duration]: `20.ticks` is one second.
  Duration get ticks => Duration(milliseconds: this * millisecondsPerTick);
}

extension DurationTicks on Duration {
  /// How many whole ticks this duration lasts, rounding up.
  int get inTicks =>
      (inMilliseconds + millisecondsPerTick - 1) ~/ millisecondsPerTick;
}

/// Schedules closures to run on the server's tick loop.
///
/// Plain Dart timers and `Future.delayed` work as well, with a resolution of
/// one tick (50ms).
extension SchedulerApi on Server {
  /// Runs [task] once, after [delayTicks] ticks.
  ScheduledTask runLater(int delayTicks, TickCallback task) =>
      ScheduledTask._(scheduleTicks(delayTicks, null, task));

  /// Runs [task] every [periodTicks] ticks, starting after [delayTicks].
  ScheduledTask runRepeating(
    int periodTicks,
    TickCallback task, {
    int delayTicks = 0,
  }) => ScheduledTask._(scheduleTicks(delayTicks, periodTicks, task));
}

/// Same as [SchedulerApi], available while the plugin is loading.
extension ContextSchedulerApi on Context {
  ScheduledTask runLater(int delayTicks, TickCallback task) =>
      ScheduledTask._(scheduleTicks(delayTicks, null, task));

  ScheduledTask runRepeating(
    int periodTicks,
    TickCallback task, {
    int delayTicks = 0,
  }) => ScheduledTask._(scheduleTicks(delayTicks, periodTicks, task));
}

/// Scheduling with [Duration]s instead of ticks. Durations are rounded up to
/// whole ticks (50ms), and a zero duration runs on the next tick.
extension DurationScheduling on Server {
  /// Runs [task] once, after [delay].
  ScheduledTask after(Duration delay, TickCallback task) =>
      runLater(delay.inTicks, task);

  /// Runs [task] every [period] (at least one tick), starting after
  /// [initialDelay], or after one [period] by default.
  ScheduledTask every(
    Duration period,
    TickCallback task, {
    Duration? initialDelay,
  }) => runRepeating(
    _atLeastOneTick(period),
    task,
    delayTicks: (initialDelay ?? period).inTicks,
  );
}

/// Same as [DurationScheduling], available while the plugin is loading.
extension ContextDurationScheduling on Context {
  ScheduledTask after(Duration delay, TickCallback task) =>
      runLater(delay.inTicks, task);

  ScheduledTask every(
    Duration period,
    TickCallback task, {
    Duration? initialDelay,
  }) => runRepeating(
    _atLeastOneTick(period),
    task,
    delayTicks: (initialDelay ?? period).inTicks,
  );
}

int _atLeastOneTick(Duration period) {
  final ticks = period.inTicks;
  return ticks < 1 ? 1 : ticks;
}

/// Collapses a burst of calls into one: [call] (re)starts a timer, and
/// [action] runs when [delay] passes without another call.
final class Debouncer {
  final Duration delay;
  final void Function() action;
  Timer? _timer;

  Debouncer(this.delay, this.action);

  void call() {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Drops the pending call, if any.
  void cancel() => _timer?.cancel();
}

/// Lets [action] run at most once per [interval]: [call] runs it right away
/// unless it ran less than [interval] ago, and returns whether it did.
final class Throttle {
  final Duration interval;
  final void Function() action;
  DateTime? _last;

  Throttle(this.interval, this.action);

  bool call() {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < interval) return false;
    _last = now;
    action();
    return true;
  }
}
