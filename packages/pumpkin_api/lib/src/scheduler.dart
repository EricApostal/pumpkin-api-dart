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
